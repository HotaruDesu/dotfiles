local M = {}
local config = require "lunavim.config.search"
local roots = require "lunavim.search.root"

local function backend()
  return require "lunavim.search.fff"
end

local function warm(root)
  if config.files ~= "fff" and config.grep ~= "fff" then
    return
  end
  if root then
    local ok, native = pcall(backend)
    if ok then
      pcall(native.warm, root)
    end
  end
end

local function configure(kind, opts)
  local root, err = roots.resolve { cwd = opts.cwd }
  if not root then
    error(err, 0)
  end
  opts.cwd = root
  opts.show_delay = 0

  -- Snacks may evaluate the same source hook through both global and source
  -- configuration. Nested preview callbacks cannot share their item identity.
  if not opts._lunavim_preview_attached then
    opts._lunavim_preview_attached = true
    local original_preview = Snacks.picker.config.preview(opts)
    local preview, close = require("lunavim.search.preview").wrap(original_preview)
    opts.preview = preview
    local on_close = opts.on_close
    opts.on_close = function(picker)
      close(picker)
      if on_close then
        on_close(picker)
      end
    end
  end

  if kind == "files" or kind == "grep" then
    local native = backend()
    warm(root)
    if config[kind] == "fff" then
      opts = require("lunavim.search.finder").attach(opts, kind, native)
    end
  end
  return opts
end

---Source hooks keep the existing Snacks entry points and keyboard mappings.
function M.sources()
  local sources = {}
  for _, kind in ipairs { "files", "grep", "grep_word", "recent", "smart" } do
    sources[kind] = {
      config = function(opts)
        return configure(kind, opts)
      end,
    }
  end
  return sources
end

local function refresh()
  backend().refresh()
  for _, picker in ipairs(Snacks.picker.get()) do
    if picker.opts.source == "files" or picker.opts.source == "grep" then
      require("lunavim.search.finder").invalidate(picker)
      picker:find { refresh = true }
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("LunaVimSearch", { clear = true })
  local pending = 0
  local function warm_current()
    if config.files ~= "fff" and config.grep ~= "fff" then
      return
    end
    pending = pending + 1
    local ticket = pending
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= "" or vim.api.nvim_buf_get_name(buf) == "" then
      return
    end
    vim.defer_fn(function()
      if ticket ~= pending or not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then
        return
      end
      warm(roots.resolve { buf = buf })
    end, 150)
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, { group = group, callback = warm_current })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { ".gitignore", ".ignore", ".fdignore", ".rgignore" },
    callback = function()
      local ok, native = pcall(backend)
      if ok and native.status().pid then
        refresh()
      end
    end,
  })
  warm_current()

  vim.api.nvim_create_user_command("LunaSearchBackend", function(args)
    if #args.fargs == 0 then
      vim.notify(vim.inspect { files = config.files, grep = config.grep, native = backend().status() }, vim.log.levels.INFO)
      return
    end
    local kind, name = unpack(args.fargs)
    if (kind ~= "files" and kind ~= "grep") or (name ~= "fff" and name ~= "snacks") or #args.fargs ~= 2 then
      error "Usage: LunaSearchBackend [files|grep fff|snacks]"
    end
    config[kind] = name
    if name == "fff" then
      warm(roots.resolve())
    elseif config.files == "snacks" and config.grep == "snacks" then
      backend().stop()
    end
    vim.notify(("%s search backend: %s (new pickers)"):format(kind, name), vim.log.levels.INFO)
  end, {
    nargs = "*",
    desc = "Inspect or select the search backend for this session",
    force = true,
    complete = function()
      return { "files", "grep", "fff", "snacks" }
    end,
  })
  vim.api.nvim_create_user_command("LunaSearchRefresh", refresh, { desc = "Refresh the current project's native search index", force = true })
end

return M
