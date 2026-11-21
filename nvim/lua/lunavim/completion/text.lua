local M = {}
local api = vim.api
local prose = { text = true, gitcommit = true, NeogitCommitMessage = true }
local aliases = { ["c++"] = "cpp", js = "javascript", ts = "typescript", py = "python", bash = "sh", shell = "sh" }

local function syntax_at(ctx, ft)
  local row, col = ctx.cursor[1] - 1, math.max(0, ctx.cursor[2] - 1)
  local ok, parser = pcall(vim.treesitter.get_parser, ctx.bufnr)
  if not ok or not parser then
    return ft == "markdown" and "prose" or "code"
  end
  parser:parse { row, row + 1 }
  local range = { row, col, row, col }
  local node = parser:named_node_for_range(range, { ignore_injections = true })
  while node do
    local kind = node:type()
    if kind == "fenced_code_block" then
      local info = node:field("info_string")[1]
      local language = info and info:named_child(0)
      local name = language and vim.treesitter.get_node_text(language, ctx.bufnr):lower()
      return "code", aliases[name] or name
    elseif kind == "indented_code_block" then
      return "code"
    elseif kind:find("comment", 1, true) then
      return "comment"
    elseif kind == "string" or kind:find("string_literal", 1, true) or kind == "string_content" or kind == "char_literal" then
      return "string"
    end
    node = node:parent()
  end
  if ft == "markdown" then
    node = parser:named_node_for_range(range, { ignore_injections = false })
    while node do
      if node:type() == "code_span" then
        return "code"
      end
      node = node:parent()
    end
    return "prose"
  end
  return "code"
end

local last = {}
function M.kind(ctx)
  local ft = vim.bo[ctx.bufnr].filetype
  if ctx.mode ~= "default" then
    return "code"
  end
  if prose[ft] or ft == "" then
    return (ft == "gitcommit" or ft == "NeogitCommitMessage") and ctx.line:match "^%s*#" and "comment" or "prose"
  end
  local tick = api.nvim_buf_get_changedtick(ctx.bufnr)
  if last.buf ~= ctx.bufnr or last.tick ~= tick or last.ft ~= ft or last.row ~= ctx.cursor[1] or last.col ~= ctx.cursor[2] then
    local kind, language = syntax_at(ctx, ft)
    last = { buf = ctx.bufnr, ft = ft, tick = tick, row = ctx.cursor[1], col = ctx.cursor[2], kind = kind, language = language }
  end
  return last.kind, last.language
end

function M.snippet_filetype(ctx)
  local ft = vim.bo[ctx.bufnr].filetype
  if ft == "markdown" then
    local kind, language = M.kind(ctx)
    if kind == "code" then
      return language or ""
    end
  end
  return ft
end

-- Read only the link destination before the cursor, including incomplete links.
-- The capture position is a byte offset in the original document.
local function link_target(ctx, before)
  if vim.bo[ctx.bufnr].filetype ~= "markdown" or M.kind(ctx) ~= "prose" then
    return
  end
  local start, target = before:match "%b[]%(%s*<()([^<>]*)$"
  if not start then
    start, target = before:match "%b[]%(%s*()([^%s<>()]*)$"
  end
  return target, start
end

local function nonlocal_target(target)
  return target:match "^%a[%w+.-]*:" or target:match "^//" or target:find "[?#]"
end

function M.is_path(ctx)
  if ctx.mode ~= "default" then
    return false
  end
  local before = ctx.line:sub(1, ctx.cursor[2])
  local target = link_target(ctx, before)
  if target then
    return not nonlocal_target(target)
  end
  local token = before:match [[([^%s<>()"'%[%]`]+)$]] or ""
  return token:match "^%.%./" ~= nil or token:match "^%./" ~= nil or token:match "^~/" ~= nil or token:match "^/[^/]" ~= nil
end

function M.path_completions(source, ctx, callback)
  local target, start
  if ctx.mode == "default" then
    target, start = link_target(ctx, ctx.line:sub(1, ctx.cursor[2]))
  end
  if target and nonlocal_target(target) then
    return callback { items = {}, is_incomplete_forward = true, is_incomplete_backward = true }
  end
  if not target or target:match "^[/~$]" then
    return source:get_completions(ctx, callback)
  end

  local parent, leaf = target:match "^(.*[/])([^/]*)$"
  local dirname = vim.fs.normalize(vim.fs.joinpath(source.opts.get_cwd(ctx), parent or ""))
  local basename = leaf or target
  local start_col = start - 1 + #(parent or "")
  local deliver = vim.schedule_wrap(function(items)
    -- Blink enqueues directory chunks on the main loop before its scan task resolves.
    for _, item in ipairs(items or {}) do
      item.textEdit.range.start.character = start_col
    end
    callback { items = items or {}, is_incomplete_forward = false, is_incomplete_backward = false }
  end)
  -- Reuse Blink's directory scan, item kinds, slash insertion, and resolve data.
  local task = require("blink.cmp.sources.path.lib").candidates(ctx, dirname, basename:sub(1, 1) == "." or source.opts.show_hidden_files_by_default, source.opts)
  task:map(deliver):catch(function()
    deliver()
  end)
  return function()
    task:cancel()
  end
end

function M.dictionary_provider()
  local wordlist
  for _, path in ipairs { "/usr/share/dict/words", "/usr/dict/words" } do
    if vim.fn.filereadable(path) == 1 then
      wordlist = path
      break
    end
  end
  return {
    name = "Dict",
    module = "blink-cmp-dictionary",
    enabled = wordlist ~= nil,
    min_keyword_length = 4,
    max_items = 3,
    score_offset = -20,
    opts = {
      dictionary_files = wordlist and { wordlist } or {},
      get_prefix = function(ctx)
        local before = ctx.line:sub(1, ctx.cursor[2])
        local prefix = before:match "([A-Za-z]+)$"
        if not prefix or #prefix < 4 or before:sub(1, -#prefix - 1):match "[%w_]$" or (before:match "%S+$" or ""):find "[/@_]" then
          return ""
        end
        if M.kind(ctx) ~= "prose" or link_target(ctx, before) then
          return ""
        end
        return prefix
      end,
    },
  }
end

return M
