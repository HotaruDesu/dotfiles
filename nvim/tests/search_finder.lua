-- Run: nvim --headless -u NONE -i NONE -n -l tests/search_finder.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/snacks.nvim")
vim.o.swapfile = false
vim.o.lines = 50
vim.o.columns = 150
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.fn.writefile({ "Needle here", "Other" }, temporary .. "/foo.txt")
vim.fn.writefile({ "Needle too" }, temporary .. "/.foo-hidden")
require("snacks").setup { picker = { enabled = true, show_delay = 0 } }
local adapter = require "lunavim.search.finder"

local ready, fail = true, false
local large = false
local calls, changes, closes = {}, 0, 0
local backend = {
  ready = function()
    return ready, "index warming"
  end,
  files = function(cwd, query, opts)
    assert(cwd == temporary)
    calls[#calls + 1] = { kind = "files", query = query, page = opts.page }
    if fail then
      error "simulated native failure"
    end
    local total = query == "" and 450 or 1
    local items = {}
    for index = opts.page * opts.page_size + 1, math.min(total, (opts.page + 1) * opts.page_size) do
      items[#items + 1] = { relative_path = ("native-%03d.cpp"):format(index), type = "file" }
    end
    return { items = items, total_matched = total }
  end,
  grep = function(cwd, query, opts)
    assert(cwd == temporary and query == "Needle" and opts.mode == "regex")
    calls[#calls + 1] = { kind = "grep", query = query }
    local items = {}
    for index = 1, large and 10025 or 1 do
      items[index] = { relative_path = "foo.txt", line_number = index, col = 0, line_content = "Needle here", match_ranges = { { 0, 6 } } }
    end
    return { items = items, total_matched = #items }
  end,
}

local function wait_for(condition, message)
  assert(vim.wait(2000, condition, 10), message)
end
local function idle(picker)
  wait_for(function()
    return not picker:is_active() and picker.list:count() == picker:count() and picker.shown
  end, "Finder did not finish")
  picker:update { force = true }
end
local function picker(kind, overrides)
  local options = vim.tbl_extend("force", {
    source = kind,
    cwd = temporary,
    layout = { preset = "select", preview = false },
    matcher = { sort_empty = true },
    on_change = function()
      changes = changes + 1
    end,
    on_close = function()
      closes = closes + 1
    end,
    config = function(opts)
      return adapter.attach(opts, kind, backend)
    end,
  }, overrides or {})
  local value = Snacks.picker(options)
  idle(value)
  return value
end
local function query(picker, pattern, search)
  picker.input:set(pattern, search)
  picker:find { refresh = false }
  idle(picker)
end
local function close(picker)
  picker:close()
  vim.wait(20, function()
    return false
  end)
end

local active = {}
local ok, err = xpcall(function()
  local files = picker "files"
  active[#active + 1] = files
  assert(files:count() == 200 and files.title:find("200/450", 1, true))
  assert(files.finder.items[1].file == "native-001.cpp" and files.finder.items[200].file == "native-200.cpp")
  assert(files.matcher:empty() and not files.opts.matcher.sort_empty, "Native ranking must not be re-sorted by Lua")
  files.list:move(190, true, true)
  wait_for(function()
    return files:count() == 400
  end, "Next file page was not loaded")
  idle(files)
  assert(files.list.cursor == 190, "Pagination moved the selected row")
  files.list:move(390, true, true)
  wait_for(function()
    return files:count() == 450
  end, "Last file page was not loaded")
  idle(files)
  assert(files.list.cursor == 390 and not files.title:find("more", 1, true))
  query(files, "foo", "")
  assert(
    files:count() == 1 and calls[#calls].query == "foo" and calls[#calls].page == 0,
    vim.inspect { count = files:count(), call = calls[#calls], status = adapter.status(files) }
  )
  assert(files.input.filter.pattern == "foo", "Visible input must keep the user's query")
  assert(files.finder.filter.pattern == "" and files.finder.filter.search == "foo")

  query(files, "^foo", "")
  wait_for(function()
    return files.list:count() == 1
  end, "Original fd/matcher fallback failed")
  assert(files.list:get(1).file == "foo.txt" and files.opts.matcher.sort_empty)
  assert(files.finder.filter.pattern == "^foo" and files.finder.filter.search == "")
  files.opts.hidden = true
  query(files, "foo", "")
  wait_for(function()
    return files.list:count() == 2
  end, "Hidden toggle must use the original fd options")
  files.opts.hidden = false
  fail = true
  query(files, "foo", "")
  wait_for(function()
    return files.list:count() == 1 and files.list:get(1).file == "foo.txt"
  end, "Native failure did not restore fd/matcher")
  assert(files.title:find("simulated native failure", 1, true))
  assert(files.finder.filter.pattern == "foo" and files.finder.filter.search == "")
  fail = false
  adapter.invalidate(files)
  query(files, "foo", "")
  assert(files.list:get(1).file == "native-001.cpp", "Explicit refresh must retry a failed query")
  ready = false
  query(files, "foo", "")
  assert(files.title:find("index warming", 1, true))
  ready = true
  query(files, "foo", "")
  assert(files.list:get(1).file == "native-001.cpp", "Ready native index did not replace fallback on the next query")
  close(files)

  local grep = picker("grep", { search = "Needle" })
  active[#active + 1] = grep
  local found = grep.list:get(1)
  assert(found.file == "foo.txt" and vim.deep_equal(found.pos, { 1, 0 }))
  assert(found.line == "Needle here" and vim.deep_equal(found.positions, { 1, 2, 3, 4, 5, 6 }))
  large = true
  adapter.invalidate(grep)
  query(grep, "", "Needle")
  assert(grep:count() == 10025 and grep.opts.limit_live == nil, "Generic live-search caps must not truncate a native file page")
  query(grep, "", "Needle|Other")
  wait_for(function()
    return grep.list:count() == 2
  end, "Advanced regex must keep rg semantics")
  assert(grep.title:find("rg", 1, true))
  assert(grep.opts.limit_live == 10000, "Fallback must restore the source's original limit")
  close(grep)

  local custom = picker("files", {
    filter = {
      transform = function(_, filter)
        filter.pattern = "^foo"
        return true
      end,
    },
  })
  active[#active + 1] = custom
  wait_for(function()
    return custom.list:count() == 1
  end, "Original filter transform was not chained")
  assert(custom.list:get(1).file == "foo.txt")
  close(custom)
  assert(changes > 0 and closes == 3, "Original picker callbacks must run")

  -- Production native calls return asynchronously. Switching queries or closing
  -- a picker must never resume its obsolete finder after matcher destruction.
  local synchronous = backend.files
  backend.files = function(cwd, text, options, callback)
    local result = synchronous(cwd, text, options)
    vim.defer_fn(function()
      callback(result)
    end, 30)
    return 1
  end
  local async = picker "files"
  active[#active + 1] = async
  async.input:set("first", "")
  async:find { refresh = false }
  async.input:set("second", "")
  async:find { refresh = false }
  idle(async)
  assert(async.finder.filter.search == "second" and async:count() == 1)
  async.input:set("last", "")
  async:find { refresh = false }
  close(async)
  vim.wait(100, function()
    return false
  end)
  backend.files = synchronous
end, debug.traceback)
for _, value in ipairs(active) do
  if not value.closed then
    value:close()
  end
end
vim.fn.delete(temporary, "rf")
if not ok then
  error(err)
end
print "PASS: native paging/order, preserved selection, query/options fallback, errors and original callbacks"
