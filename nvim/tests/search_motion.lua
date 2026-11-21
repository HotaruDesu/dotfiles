-- Exercise continuous navigation, bounded reads, deferred highlighting and the
-- shared selection marker through real Snacks windows.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/snacks.nvim")
vim.o.swapfile = false
vim.o.columns, vim.o.lines = 160, 45
vim.o.showmode = false
require("snacks").setup { picker = { enabled = true } }
local motion = require "lunavim.search.motion"
local preview = require "lunavim.search.preview"
local uv = vim.uv
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
local paths = {}
for _, name in ipairs { "a", "b", "c" } do
  paths[#paths + 1] = temp .. "/" .. name .. ".cpp"
  vim.fn.writefile({ "int " .. name .. " = 1;", "int next_line = 2;" }, paths[#paths])
end
local function pause(ms)
  vim.wait(ms, function()
    return false
  end, 1)
end
local function wait(fn, message)
  assert(vim.wait(1500, fn, 1), message)
end
local function text(p)
  return table.concat(vim.api.nvim_buf_get_lines(p.preview.win.buf, 0, -1, false), "\n")
end
local function open()
  local items = {}
  for _, path in ipairs(paths) do
    items[#items + 1] = { file = path, text = path }
  end
  local render, close = preview.wrap(require("snacks.picker.preview").file)
  local p = Snacks.picker {
    items = items,
    sort = { fields = { "idx" } },
    format = "file",
    show_delay = 0,
    preview = render,
    on_show = motion.attach,
    on_close = function(picker)
      close(picker)
      motion.close(picker)
    end,
  }
  wait(function()
    return p.shown and p.list:count() == 3 and p.preview.win:valid()
  end, "Picker did not open")
  return p
end
local function select(p, idx)
  p.list:move(idx, true)
  p.preview:show(p, { force = true })
end
local function markers()
  return vim.tbl_filter(function(w)
    return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "lunavim_picker_marker"
  end, vim.api.nvim_list_wins())
end
local read, fsopen, stat, io_open = uv.fs_read, uv.fs_open, uv.fs_stat, io.open
local ok, err = xpcall(function()
  -- Ordinary disk previews must never fall back to synchronous file I/O.
  io.open = function(path, ...)
    assert(not path:find(temp, 1, true), "Synchronous preview read")
    return io_open(path, ...)
  end
  uv.fs_stat = function(path, callback)
    if vim.tbl_contains(paths, path) then
      assert(callback, "Synchronous preview stat")
    end
    return stat(path, callback)
  end
  local p = open()
  local highlights = 0
  local highlight = p.preview.highlight
  p.preview.highlight = function(self, ...)
    highlights = highlights + 1
    return highlight(self, ...)
  end
  local changes, last = 0, ""
  for i = 1, 50 do
    p.list:move(i % 3 + 1, true)
    pause(20)
    local content = text(p)
    if content ~= "" and content ~= last then
      changes = changes + 1
    end
    last = content
  end
  assert(changes >= 5, "Continuous selection starved previews: " .. changes)
  assert(highlights == 0, "Highlight work ran while selection was moving")
  local started = uv.hrtime()
  wait(function()
    return text(p):find("int c =", 1, true)
  end, "Final selection did not render")
  assert((uv.hrtime() - started) / 1e6 < 120, "Final small preview missed 120ms budget")
  wait(function()
    return highlights > 0
  end, "Settled preview never gained highlighting")
  local buf, tick = p.preview.win.buf, vim.api.nvim_buf_get_changedtick(p.preview.win.buf)
  p:current().pos = { 2, 0 }
  p.preview:show(p, { force = true })
  wait(function()
    return vim.api.nvim_win_get_cursor(p.preview.win.win)[1] == 2
  end, "Same-file match did not move")
  assert(p.preview.win.buf == buf and vim.api.nvim_buf_get_changedtick(buf) == tick, "Same-file match rewrote content")
  p:close()
  uv.fs_stat, io.open = stat, io_open

  -- A live-query throttle may be waiting even when no finder is running.
  -- Keep the old content until the new query has reached the search filter.
  p = open()
  wait(function()
    return text(p):find("int a =", 1, true)
  end, "Initial preview did not render")
  vim.api.nvim_buf_set_lines(p.input.win.buf, 0, -1, false, { "'b.cpp" })
  select(p, 2)
  pause(120)
  assert(text(p):find("int a =", 1, true), "Preview ran ahead of the throttled query")
  p.input:set("'b.cpp", "")
  p:find()
  local resumed = vim.wait(1500, function()
    return text(p):find("int b =", 1, true)
  end, 1)
  assert(resumed, "Applied query did not resume its preview: " .. vim.inspect { text = text(p), filter = p.input.filter, active = p:is_active(), current = p:current() })
  p:close()

  -- Recognized source files may contain literal control-key strings.
  vim.fn.writefile({ 'local keys = "' .. string.char(19, 22) .. '"' }, paths[1])
  p = open()
  wait(function()
    return text(p):find("local keys", 1, true)
  end, "Source containing control-key strings was misclassified as binary")
  p:close()
  vim.fn.writefile({ "int a = 1;", "int next_line = 2;" }, paths[1])

  -- Hold one read while replacing pending requests; only the newest can start.
  local release, held_fd, opened = nil, nil, {}
  uv.fs_open = function(path, flags, mode, callback)
    if path:find(temp, 1, true) then
      opened[#opened + 1] = path
    end
    return fsopen(path, flags, mode, callback)
  end
  uv.fs_read = function(fd, size, offset, callback)
    return read(fd, size, offset, function(read_err, data)
      if not held_fd then
        held_fd = fd
        release = function()
          callback(read_err, data)
        end
      else
        callback(read_err, data)
      end
    end)
  end
  p = open()
  wait(function()
    return release
  end, "Read did not start")
  select(p, 2)
  select(p, 3)
  pause(25)
  assert(#opened == 1, "Concurrent reads started")
  release()
  wait(function()
    return text(p):find("int c =", 1, true)
  end, "Latest queued request was lost")
  assert(#opened == 2 and opened[2] == paths[3], "Intermediate request was not discarded")
  p:close()
  uv.fs_read, uv.fs_open = read, fsopen

  -- A source opened and edited during an in-flight read supersedes disk text.
  release = nil
  uv.fs_read = function(fd, size, offset, callback)
    return read(fd, size, offset, function(read_err, data)
      release = function()
        callback(read_err, data)
      end
    end)
  end
  p = open()
  wait(function()
    return release
  end, "Pending source read did not start")
  local source = vim.fn.bufadd(paths[1])
  vim.fn.bufload(source)
  vim.api.nvim_buf_set_lines(source, 0, 1, false, { "int UNSAVED = 3;" })
  release()
  wait(function()
    return text(p):find("UNSAVED", 1, true)
  end, "Read overwrote unsaved source content")
  assert(p.preview.win.buf == source and vim.bo[source].modified)
  p:close()
  uv.fs_read = read
  vim.api.nvim_buf_delete(source, { force = true })

  for _, columns in ipairs { 100, 160 } do
    vim.o.columns = columns
    vim.g.neovide = columns == 160
    p = open()
    wait(function()
      return #markers() == 1
    end, "Picker selection marker missing")
    local marker = markers()[1]
    local input = vim.api.nvim_get_current_win()
    local config = vim.api.nvim_win_get_config(marker)
    assert(not config.focusable and not config.mouse)
    p.list:move(3, true)
    assert(markers()[1] == marker, "Marker recreated on each move")
    assert(vim.api.nvim_win_get_config(marker).row == 2)
    p.list:move(1, true)
    assert(vim.api.nvim_win_get_config(marker).row == 0, "Reverse selection lost position")
    assert(vim.api.nvim_get_current_win() == input, "Marker stole input focus")
    vim.o.columns = columns + 12
    vim.o.lines = 38
    p.layout:update()
    p.list:update { force = true }
    wait(function()
      return #markers() == 1 and vim.api.nvim_win_get_config(markers()[1]).win == p.list.win.win
    end, "Resize lost the marker's parent")
    p.list:move(2, true)
    assert(vim.api.nvim_win_get_config(markers()[1]).row == 1, "Resized marker no longer follows selection")
    p:toggle("preview", { enable = false })
    pause(100)
    assert(#markers() == 1, "Hiding the preview broke the list marker")
    p:toggle("preview", { enable = true })
    wait(function()
      return text(p):find("int b =", 1, true)
    end, "Hidden preview did not recover the latest selection")
    p.list:select()
    assert(vim.wo[p.list.win.win].signcolumn == "yes:1", "Marker covers the multi-select prefix")
    p.input:set("NoMatchHere", "")
    p:find()
    wait(function()
      return p.list:count() == 0 and #markers() == 0
    end, "Empty results retained marker")
    p.input:set("", "")
    p:find()
    wait(function()
      return p.list:count() == 3 and #markers() == 1
    end, "Marker did not recover")
    p:close()
    assert(#markers() == 0, "Marker leaked after close")
    assert(#vim.tbl_filter(function(buf)
      return vim.bo[buf].filetype == "lunavim_picker_marker"
    end, vim.api.nvim_list_bufs()) == 0, "Marker buffer leaked after close")
  end
  vim.g.lunavim_reduced_motion = true
  for _, gui in ipairs { false, true } do
    vim.g.neovide = gui
    p = open()
    assert(#markers() == 0, "Reduced motion should disable the marker")
    p:close()
  end
  print "PASS: continuous previews, idle highlighting, one-read/latest-request queue, unsaved content and shared marker lifecycle"
end, debug.traceback)
uv.fs_read, uv.fs_open, uv.fs_stat, io.open = read, fsopen, stat, io_open
for _, p in ipairs(Snacks.picker.get()) do
  p:close()
end
vim.fn.delete(temp, "rf")
if not ok then
  error(err)
end
