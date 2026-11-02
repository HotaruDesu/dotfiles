-- Run: nvim --headless -u NONE -i NONE -n -l tests/search_preview.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/snacks.nvim")
vim.o.swapfile = false
vim.o.columns = 150
vim.o.lines = 45
require("snacks").setup { picker = { enabled = true } }
local default_preview = require("snacks.picker.preview").file
local wrap = require("lunavim.search.preview").wrap
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local function file(name, lines)
  local path = temporary .. "/" .. name
  vim.fn.writefile(lines, path)
  return path
end
local first = file("a.cpp", { "int first = 1;", "int target = 2;" })
local second = file("b.cpp", { "int second = 2;" })
local medium = file("medium.cpp", vim.fn["repeat"]({ string.rep("x", 80) }, 4000))
local huge = file("huge.cpp", { string.rep("z", 1024 * 1024 + 1) })
local broken = temporary .. "/missing.cpp"

local function wait_for(predicate, message)
  assert(vim.wait(1500, predicate, 5), message)
end
local function pause(ms)
  vim.wait(ms, function()
    return false
  end)
end
local function contents(picker)
  if not picker.preview.win:valid() then
    return ""
  end
  return table.concat(vim.api.nvim_buf_get_lines(picker.preview.win.buf, 0, -1, false), "\n")
end
local function open(items, callback, opts)
  local preview, close = wrap(callback or default_preview, opts)
  local picker = Snacks.picker {
    items = items,
    format = "file",
    preview = preview,
    on_close = close,
    show_delay = 0,
    sort = { fields = { "idx" } },
    layout = { preset = "default", preview = true },
  }
  wait_for(function()
    return picker.preview.win:valid() and picker:count() == #items
  end, "Picker failed to open")
  return picker
end
local function select(picker, path, pos)
  for i = 1, picker:count() do
    local item = picker.list:get(i)
    if item.file == path then
      if pos then
        item.pos = pos
      end
      picker.list:move(i, true)
      picker.preview:show(picker, { force = true })
      return item
    end
  end
  error("Missing item: " .. path)
end

local ok, err = xpcall(function()
  -- Reconfiguring a source must not put one delayed callback around another.
  -- Nested wrappers cannot compare a copied item to the picker's real item.
  local once, once_close = wrap(default_preview, { delay_ms = 10 })
  local twice, twice_close = wrap(once, { delay_ms = 50 })
  assert(twice == once and twice_close == once_close, "Wrapped callbacks must be idempotent")
  local independent = wrap(default_preview, { delay_ms = 50 })
  assert(independent ~= once, "Different source options must not share a wrapper")
  local nested = Snacks.picker {
    items = { { file = first, text = first } },
    format = "file",
    preview = twice,
    on_close = twice_close,
    show_delay = 0,
  }
  wait_for(function()
    return contents(nested):find("int first", 1, true) ~= nil
  end, "Repeated wrapping left the actual picker preview empty")
  nested:close()

  local rendered = {}
  local p = open({ { file = first, text = first }, { file = second, text = second } }, function(ctx)
    rendered[#rendered + 1] = { item = ctx.item.file, previous = ctx.prev and ctx.prev.file }
    return default_preview(ctx)
  end)
  pause(30)
  assert(#rendered == 0, "Default 120ms delay must leave input/results first")
  select(p, second)
  select(p, first, { 2, 0 })
  wait_for(function()
    return contents(p):find("int first", 1, true) ~= nil
  end, "Latest settled selection did not render")
  assert(#rendered == 1 and not rendered[1].previous, "Cancelled item must not be treated as rendered: " .. vim.inspect(rendered))
  assert(vim.api.nvim_win_get_cursor(p.preview.win.win)[1] == 2, "Match line moved")
  assert(p.preview.title == "a.cpp", "Delayed title did not update")
  assert(vim.trim(p.preview.win.opts.title) == "a.cpp", "Real floating title did not update: " .. vim.inspect(p.preview.win.opts.title))

  select(p, second)
  wait_for(function()
    return contents(p):find("int second", 1, true) ~= nil
  end, "Second preview failed")
  assert(rendered[2].previous == first)
  p.input:set("NoSuchPreviewQuery", "")
  p:find()
  wait_for(function()
    return p.list:count() == 0 and contents(p) == ""
  end, "No-match query did not reset the preview")
  p.input:set("", "")
  p:find()
  wait_for(function()
    return p.list:count() == 2
  end, "Cleared query did not restore results")
  select(p, second)
  wait_for(function()
    return contents(p):find("int second", 1, true) ~= nil
  end, "Returning to a file after no matches reused an empty scratch")
  assert(#rendered == 3 and not rendered[3].previous, "Cleared scratch must not be treated as a cached file")
  select(p, first)
  p:close()
  pause(180)
  assert(#rendered == 3, "Closing picker did not cancel timer")

  p = open({ { file = first, text = first } }, function(ctx)
    rendered[#rendered + 1] = ctx.item.file
    return default_preview(ctx)
  end)
  p:toggle("preview", { enable = false })
  pause(150)
  assert(#rendered == 3, "Hidden preview did work")
  p:toggle("preview", { enable = true })
  wait_for(function()
    return contents(p):find("int first", 1, true) ~= nil
  end, "Reopened preview did not recover")
  p:close()

  local original_calls = 0
  p = open({ { file = medium, text = medium, pos = { 3000, 0 } } }, function(ctx)
    original_calls = original_calls + 1
    return default_preview(ctx)
  end, { delay_ms = 10 })
  wait_for(function()
    return p.preview.title and p.preview.title:find("plain text", 1, true) ~= nil
  end, "Medium file did not use plain preview")
  assert(original_calls == 0)
  assert(vim.api.nvim_buf_line_count(p.preview.win.buf) == 4000)
  assert(vim.api.nvim_win_get_cursor(p.preview.win.win)[1] == 3000)
  assert(not vim.treesitter.highlighter.active[p.preview.win.buf])
  p:close()

  local buf = vim.fn.bufadd(medium)
  vim.fn.bufload(buf)
  vim.bo[buf].filetype = "cpp"
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "// UNSAVED SOURCE TEXT" })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
  vim.treesitter.start(buf, "cpp")
  local source_parser = vim.treesitter.highlighter.active[buf]
  p = open({ { file = medium, text = medium } }, nil, { delay_ms = 10 })
  wait_for(function()
    return contents(p):find("UNSAVED SOURCE TEXT", 1, true) ~= nil
  end, "Unsaved text was not previewed")
  assert(p.preview.win.buf ~= buf, "Medium buffer preview must copy to scratch")
  assert(vim.bo[buf].modified and vim.bo[buf].filetype == "cpp")
  assert(vim.treesitter.highlighter.active[buf] == source_parser, "Preview stopped the source parser")
  assert(vim.api.nvim_buf_line_count(p.preview.win.buf) == 4001, "Unsaved trailing empty line was lost")
  p:close()

  p = open({ { file = huge, text = huge } }, nil, { delay_ms = 10 })
  wait_for(function()
    return contents(p):find("preview limit", 1, true) ~= nil
  end, "Huge file did not show bounded message")
  assert(vim.api.nvim_buf_line_count(p.preview.win.buf) == 2)
  p:close()

  p = open({ { file = broken, text = broken } }, function()
    error "simulated reader failure"
  end, { delay_ms = 10 })
  wait_for(function()
    return contents(p):find("simulated reader failure", 1, true) ~= nil
  end, "Async renderer error escaped")
  p:close()

  -- Hold a real asynchronous read callback, then close before releasing it.
  -- It must close the fd and never write into a destroyed preview window.
  local read = vim.uv.fs_read
  local release
  vim.uv.fs_read = function(fd, size, offset, callback)
    if callback then
      return read(fd, size, offset, function(read_err, data)
        release = function()
          callback(read_err, data)
        end
      end)
    end
    return read(fd, size, offset)
  end
  local unloaded = file("pending.cpp", vim.fn["repeat"]({ string.rep("p", 80) }, 4000))
  p = open({ { file = unloaded, text = unloaded } }, nil, { delay_ms = 10 })
  wait_for(function()
    return release ~= nil
  end, "Async read did not start")
  p:close()
  release()
  pause(30)
  vim.uv.fs_read = read
  print "PASS: delayed preview cancellation, reopens, titles, errors and bounded asynchronous I/O"
  print "PASS: medium/huge previews preserve source text, match positions, unsaved buffers and Treesitter"
end, debug.traceback)
for _, picker in ipairs(Snacks.picker.get()) do
  picker:close()
end
vim.fn.delete(temporary, "rf")
if not ok then
  error(err)
end
