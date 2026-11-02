local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local config = require "lunavim.config.search"
config.native_path = vim.env.LUNAVIM_FFF_PATH or config.native_path
local plugin = config.native_path or vim.fn.stdpath "data" .. "/lazy/fff"
if not vim.uv.fs_stat(plugin .. "/target/release/libfff_nvim.dylib") and not vim.uv.fs_stat(plugin .. "/target/release/libfff_nvim.so") then
  print "SKIP: FFF native integration (install the pinned plugin and build its native library)"
  return
end

local backend = require "lunavim.search.fff"
local temporary = vim.fn.tempname()
local function file(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
local a, b = temporary .. "/a", temporary .. "/b"
file(a .. "/main.cpp", { "// 中文 Needle", "int Needle = 42;" })
file(a .. "/with spaces/中文.cpp", { "Needle here" })
local lines = {}
for i = 1, 251 do
  lines[i] = "Needle " .. i
end
file(a .. "/many.txt", lines)
file(b .. "/second.cpp", { "SecondProject" })

local function wait_for(fn, message)
  assert(vim.wait(10000, fn, 10), message or vim.inspect(backend.status()))
end
local function warm(path)
  backend.warm(path)
  wait_for(function()
    return backend.ready(path)
  end)
end
local function query(kind, path, text, opts)
  local done, result, reason = false
  backend[kind](path, text, opts or {}, function(value, err)
    result, reason, done = value, err, true
  end)
  wait_for(function()
    return done
  end, "Native request did not return")
  assert(result, reason)
  return result
end
local function eventually(path, text, predicate, message)
  local done, failure = false, nil
  local function probe()
    if done then
      return
    end
    backend.files(path, text, { page_size = 100 }, function(result, err)
      if not result then
        failure, done = err, true
      elseif predicate(result) then
        done = true
      else
        vim.defer_fn(probe, 50)
      end
    end)
  end
  probe()
  wait_for(function()
    return done
  end, message)
  assert(not failure, failure)
end
local ok, err = xpcall(function()
  warm(a)
  assert(backend.ready(a, "files") and backend.ready(a, "grep"))
  local result = query("files", a, "", { page_size = 1000 })
  assert(#result.items == 3, vim.inspect(result))
  local grep = query("grep", a, "Needle", { page_size = 2 })
  local all, seen = {}, {}
  repeat
    for _, item in ipairs(grep.items) do
      local key = item.relative_path .. ":" .. item.line_number
      assert(not seen[key], "Duplicate paginated line: " .. key)
      seen[key], all[#all + 1] = true, item
      if item.relative_path == "main.cpp" and item.line_number == 1 then
        assert(item.col == 10, "FFF columns must remain zero-based UTF-8 byte positions")
      end
    end
    local offset = grep.next_file_offset or 0
    if offset == 0 then
      break
    end
    grep = query("grep", a, "Needle", { page_size = 2, file_offset = offset })
  until false
  assert(#all == 254, "Grep paging lost lines within a file: " .. #all)
  backend.stop()
  warm(a)
  assert(#query("files", a, "", { page_size = 1000 }).items == 3, "Native search must restart after being disabled in the same project")
  print "PASS: real native files/grep, Unicode byte positions and complete per-file pagination"
  if vim.env.LUNAVIM_SKIP_WATCHER_TEST == "1" then
    print "SKIP: native watcher checks disabled for the restricted test environment"
    return
  end

  vim.wait(500, function()
    return false
  end)
  file(a .. "/newly_added.cpp", { "NewFile" })
  eventually(a, "newly_added", function(result)
    return vim.iter(result.items):any(function(item)
      return item.relative_path == "newly_added.cpp"
    end)
  end, "Watcher did not add a new file")
  assert(vim.uv.fs_rename(a .. "/newly_added.cpp", a .. "/renamed.cpp"))
  eventually(a, "renamed", function(result)
    return result.items[1] and result.items[1].relative_path == "renamed.cpp"
  end, "Watcher did not rename a file")
  vim.fn.delete(a .. "/renamed.cpp")
  eventually(a, "renamed", function(result)
    return not vim.iter(result.items):any(function(item)
      return item.relative_path == "renamed.cpp"
    end)
  end, "Watcher did not delete a file")

  local ticks = 0
  local timer = assert(vim.uv.new_timer())
  timer:start(
    0,
    2,
    vim.schedule_wrap(function()
      ticks = ticks + 1
    end)
  )
  backend.warm(b)
  assert(not backend.ready(a), "Switching projects must invalidate the old root immediately")
  wait_for(function()
    return backend.ready(b)
  end)
  timer:stop()
  timer:close()
  assert(ticks > 0, "Index switch blocked the main event loop")
  local second = query("files", b, "", { page_size = 100 })
  assert(#second.items == 1 and second.items[1].relative_path == "second.cpp")

  -- New custom rules must not be silently ignored by the new backend.
  file(b .. "/.fdignore", { "second.cpp" })
  backend.refresh()
  wait_for(function()
    return backend.ready(b)
  end)
  assert(not backend.ready(b, "files"), "Mismatching inventories must force the fd fallback")
  assert(backend.ready(b, "grep"), "fd-only ignores must not disable rg-compatible searches")
  backend.stop()
  assert(not backend.ready(b))
  print "PASS: filesystem watcher, nonblocking project switch, ignore coverage guard and worker shutdown"
end, debug.traceback)
backend.stop()
vim.fn.delete(temporary, "rf")
if not ok then
  error(err)
end
