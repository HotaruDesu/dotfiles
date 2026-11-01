-- Runs only in a disposable embedded Nvim. Native index locks and synchronous
-- searches stay off the editor's main loop; this process owns one project.
local M = {}
local engine, root, generation, max_threads

local function send(id, result, err)
  vim.rpcnotify(1, "nvim_exec_lua", "require('lunavim.search.fff').deliver(...)", { generation, id, result, err })
end

local function inventory(command, indexed)
  local result = vim.system(command, { cwd = root }):wait(30000)
  if result.code ~= 0 then
    return false
  end
  local found = {}
  for path in (result.stdout or ""):gmatch "([^%z]+)%z" do
    path = path:gsub("^%./", "")
    found[path] = true
    if not indexed[path] then
      return false
    end
  end
  for path in pairs(indexed) do
    if not found[path] then
      return false
    end
  end
  return true
end

function M.start(options)
  generation, root, max_threads = options.generation, options.root, options.max_threads
  vim.opt.rtp:prepend(options.plugin)
  local ok, err = pcall(function()
    engine = require "fff"
    engine.setup {
      base_path = root,
      lazy_sync = true,
      enable_home_dir_scanning = false,
      enable_fs_root_scanning = false,
      follow_symlinks = false,
      max_threads = max_threads,
      logging = { enabled = false },
      git = { recency = { enabled = false } },
      grep = { enable_filename_constraint = false, classify_definitions = false },
    }
    local native = require("fff.core").ensure_initialized()
    assert(native.wait_for_initial_scan(30000), "FFF initial scan timed out")
    local progress = native.get_scan_progress()
    local indexed = {}
    for _, item in ipairs(engine.file_search("", { max_results = 2147483647, wait_for_index_ms = 0 }).items) do
      local path = item.relative_path
      if path:sub(1, 1) ~= "." and not path:find "/%." then
        indexed[path] = true
      end
    end
    -- Audit once off the UI thread: fd and rg have different ignore semantics.
    local files = inventory({ "fd", "--type", "f", "--type", "l", "--color", "never", "-E", ".git", "--print0", "." }, indexed)
    local grep = inventory({ "rg", "--files", "--null", "--glob=!.git", "--glob=!.bare" }, indexed)
    send(0, { root = root, files = progress.scanned_files_count, ready = true, compatible = { files = files, grep = grep }, rss = vim.uv.resident_set_memory() })
  end)
  if not ok then
    send(0, nil, tostring(err))
  end
end

function M.query(id, kind, query, options)
  local ok, result = pcall(function()
    local found
    if kind == "files" then
      found = engine.file_search(query, {
        max_results = options.page_size or 200,
        page = options.page or 0,
        max_threads = max_threads,
        wait_for_index_ms = 0,
      })
    else
      found = engine.content_search(query, {
        mode = "regex",
        page_size = options.page_size or 200,
        file_offset = options.file_offset or 0,
        max_matches_per_file = 0,
        max_file_size = 1024 * 1024 * 1024,
        smart_case = true,
        classify_definitions = false,
        time_budget_ms = 100,
        enforce_time_budget = true,
        wait_for_index_ms = 0,
      })
      assert(not found.regex_fallback_error, found.regex_fallback_error)
    end
    -- Explicit plain tables keep the RPC boundary independent of mlua userdata.
    local items = {}
    for _, item in ipairs(found.items or {}) do
      items[#items + 1] = {
        relative_path = item.relative_path,
        name = item.name,
        type = item.type,
        line_number = item.line_number,
        col = item.col,
        line_content = item.line_content,
        match_ranges = item.match_ranges,
      }
    end
    return {
      items = items,
      total_matched = found.total_matched,
      total_files = found.total_files,
      next_file_offset = found.next_file_offset,
      rss = vim.uv.resident_set_memory(),
    }
  end)
  send(id, ok and result or nil, not ok and tostring(result) or nil)
end

return M
