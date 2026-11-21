-- RPC worker for tightly interleaved baseline/current measurements.
return function(root, directory)
  vim.opt.rtp:prepend(root)
  for _, plugin in ipairs { "snacks.nvim", "nvim-treesitter" } do
    vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/" .. plugin)
  end
  vim.o.swapfile, vim.o.showmode = false, false
  vim.o.columns, vim.o.lines = 160, 50
  vim.g.neovide = true
  _G.LunaVim = require "lunavim"
  require("snacks").setup(require("lunavim.ui_specs.snacks")[1].opts)
  local function now()
    return vim.uv.hrtime() / 1e6
  end
  local function wait(fn)
    assert(vim.wait(10000, fn, 1), "Benchmark condition timed out")
  end
  local function pause(ms)
    vim.wait(ms, function()
      return false
    end, 1)
  end
  local function settled(p)
    wait(function()
      return p.shown and not p:is_active() and p.list:count() > 0
    end)
  end
  local function open(kind, query)
    return Snacks.picker(kind, { cwd = directory, pattern = kind == "files" and query or nil, search = kind == "grep" and query or nil })
  end
  local current
  local B = {}
  function B.close()
    if current then
      current:close()
      current = nil
    end
    pause(10)
  end
  function B.prepare(kind)
    B.close()
    current = open(kind, kind == "files" and "config" or "BufEnter")
    settled(current)
    pause(250)
  end
  function B.first(kind, query)
    local start = now()
    local p = open(kind, query)
    wait(function()
      return p.shown and p.list:count() > 0 and vim.api.nvim_buf_get_lines(p.list.win.buf, 0, 1, false)[1] ~= ""
    end)
    local elapsed = now() - start
    settled(p)
    p:close()
    pause(10)
    return elapsed
  end
  function B.input(kind, query, typing)
    local p = assert(current)
    settled(p)
    local start, task, tick
    for length = typing and 1 or #query, #query do
      task, tick = p.finder.task, p.matcher.tick
      start = now()
      vim.api.nvim_buf_set_lines(p.input.win.buf, 0, -1, false, { query:sub(1, length) })
      vim.api.nvim_exec_autocmds("TextChangedI", { buffer = p.input.win.buf })
      if length < #query then
        pause(math.max(0, 20 - (now() - start)))
      end
    end
    wait(function()
      local item = p.list:get(1)
      local text = item and (kind == "files" and item.file or item.line)
      return (p.finder.task ~= task or p.matcher.tick ~= tick) and not p:is_active() and text and text:lower():find(query:lower(), 1, true) ~= nil
    end)
    return now() - start
  end
  function B.hold()
    local p = open("files", "lua")
    settled(p)
    local action = assert(vim.fn.maparg("<C-j>", "i", false, true).callback)
    local file = assert(io.open(Snacks.picker.util.path(p.list:get(51)), "r"))
    local expected_line = file:read "*l" or ""
    file:close()
    local limit = p.opts.previewers.file.max_line_length
    if #expected_line > limit then
      expected_line = expected_line:sub(1, limit) .. "..."
    end
    local samples, last, updates = {}, nil, 0
    for key = 1, 50 do
      local start = now()
      action()
      assert(p.list.cursor == key + 1)
      samples[#samples + 1] = now() - start
      pause(math.max(0, 20 - (now() - start)))
      local buf = p.preview.win.buf
      local revision = buf .. ":" .. vim.api.nvim_buf_get_changedtick(buf) .. ":" .. tostring(p.preview.title)
      if last and revision ~= last then
        updates = updates + 1
      end
      last = revision
    end
    local start = now()
    local title = vim.fn.fnamemodify(p:current().file, ":t")
    wait(function()
      return p.preview.title == title and vim.api.nvim_buf_get_lines(p.preview.win.buf, 0, 1, false)[1] == expected_line
    end)
    local final = now() - start
    p:close()
    pause(10)
    return { selection_ms = samples, hold_updates = updates, final_preview_ms = final }
  end
  _G.MotionBench = B
end
