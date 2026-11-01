local M = {}
local PAGE_SIZE = require("lunavim.config.search").page_size
local PAGE_MARGIN = 20
local SOURCE_OPTIONS = { "hidden", "ignored", "follow", "rtp", "buffers", "args", "dirs", "exclude", "ft", "glob", "cmd", "live", "regex", "limit", "limit_live" }
local states = setmetatable({}, { __mode = "k" })

---Invalidate prepared pages after an explicit index refresh.
function M.invalidate(picker)
  local state = states[picker]
  if state then
    state.key, state.pending, state.load_next = nil, false, false
    state.failed_key, state.failed_reason = nil, nil
    state.generation = state.generation + 1
  end
end

function M.status(picker)
  local state = states[picker]
  return state and { backend = state.native and "fff" or "snacks", reason = state.reason, shown = #state.items, total = state.total, more = state.more } or nil
end

local function nonempty(value)
  return value ~= nil and value ~= false and (type(value) ~= "table" or next(value) ~= nil)
end

local function scope_key(opts, cwd)
  local scope = { cwd = cwd }
  for _, name in ipairs(SOURCE_OPTIONS) do
    scope[name] = opts[name]
  end
  local filter = opts.filter or {}
  scope.filter = { cwd = filter.cwd, buf = filter.buf, paths = filter.paths, filter = filter.filter }
  return vim.inspect(scope)
end

local function supported(opts, kind, filter, has_transform)
  if opts.limit or opts.limit_live ~= nil and opts.limit_live ~= 10000 then
    return false, "custom result limit"
  end
  for _, name in ipairs { "hidden", "ignored", "follow", "rtp", "buffers", "args", "dirs", "exclude", "ft", "glob", "cmd" } do
    if nonempty(opts[name]) then
      return false, "custom search options"
    end
  end
  local config = opts.filter or {}
  if has_transform or config.buf or config.paths or config.filter or type(config.cwd) == "string" then
    return false, "custom search filter"
  end
  if kind == "files" then
    if opts.live or filter.search ~= "" then
      return false, "live file glob"
    end
    -- Preserve Snacks' advanced matcher syntax by sending it through the
    -- original matcher, rather than interpreting it as FFF query constraints.
    return filter.pattern == "" or filter.pattern:match "^[%w_%.%-]+$", "advanced file query"
  end
  if opts.regex == false or filter.pattern ~= "" or not filter.search:match "^[%w_]+$" then
    return false, "advanced grep query"
  end
  return true
end

local function hidden(path)
  return path:sub(1, 1) == "." or path:find "/%." ~= nil
end

local function item_from(result, root, kind)
  local path = result.relative_path or result.file or result.name
  if type(path) ~= "string" or path == "" or hidden(path) or result.type == "directory" then
    return nil
  end
  local item = { text = path, file = path, cwd = root }
  if kind == "grep" then
    local row = tonumber(result.line_number)
    local col = tonumber(result.col) or 0
    if not row then
      return nil
    end
    item.line = result.line_content or ""
    item.text = ("%s:%d:%d:%s"):format(path, row, col + 1, item.line)
    item.pos = { row, col }
    local positions = {}
    for _, range in ipairs(result.match_ranges or {}) do
      local first, last = range[1] or range.start, range[2] or range["end"]
      if type(first) == "number" and type(last) == "number" then
        item.end_pos = item.end_pos or { row, last }
        for byte = first + 1, last do
          positions[#positions + 1] = byte
        end
      end
    end
    item.positions = #positions > 0 and positions or nil
  end
  return item
end

local function safe_call(fn, ...)
  local ok, result, reason = pcall(fn, ...)
  if not ok then
    return nil, tostring(result)
  end
  return result, reason
end

local function label(picker, state, kind)
  state.title = state.title or picker.title
  local suffix
  if state.native then
    local count = #state.items
    suffix = kind == "files" and ("FFF %d/%d indexed"):format(count, state.total or count) or ("FFF %d matches"):format(count)
    suffix = suffix .. (state.more and " · more" or "")
  else
    local reason = tostring(state.reason or "fallback"):gsub("[\r\n]+", " "):sub(1, 60)
    suffix = (kind == "files" and "fd" or "rg") .. " · " .. reason
  end
  picker.title = state.title .. " · " .. suffix
end

---Adapt only file/grep sources. Other Snacks pickers keep their original
---finders, ranking, global history and UI behavior.
---@param opts table Resolved Snacks source options.
---@param kind "files"|"grep"
---@param backend table FFF lifecycle/search adapter; functions are dot calls.
---@return table opts
function M.attach(opts, kind, backend)
  assert(kind == "files" or kind == "grep", "Unsupported search kind")
  -- Snacks evaluates config callbacks once before source defaults are merged.
  if not opts.finder then
    return opts
  end
  if opts._lunavim_search_attached then
    return opts
  end
  opts._lunavim_search_attached = true
  local original = assert(Snacks.picker.config.finder(opts.finder), "Search source has no finder")
  local original_spec = opts.finder
  local original_change, original_close = opts.on_change, opts.on_close
  opts.filter = opts.filter or {}
  local original_transform = opts.filter.transform

  local function state_for(picker)
    if not states[picker] then
      states[picker] = {
        items = {},
        generation = 0,
        sort_empty = picker.opts.matcher.sort_empty,
        limit = picker.opts.limit,
        limit_live = picker.opts.limit_live,
      }
    end
    return states[picker]
  end

  local function fallback(picker, state, reason)
    local changed = state.native == true
    state.native, state.reason = false, reason
    state.key, state.more, state.load_next, state.pending = nil, false, false, false
    state.items = {}
    state.generation = state.generation + 1
    picker.opts.matcher.sort_empty = state.sort_empty
    picker.opts.limit, picker.opts.limit_live = state.limit, state.limit_live
    label(picker, state, kind)
    return changed
  end

  opts.filter.transform = function(picker, filter)
    local refresh = original_transform and original_transform(picker, filter) or false
    local state = state_for(picker)
    local query = kind == "files" and filter.pattern or filter.search
    local root = filter.cwd
    local scope = scope_key(picker.opts, root)
    refresh = state.scope ~= scope or refresh
    state.scope = scope
    local eligible, reason = supported(picker.opts, kind, filter, original_transform ~= nil)
    if type(original_spec) ~= "string" or original_spec ~= kind then
      eligible, reason = false, "custom finder"
    end
    if eligible then
      eligible, reason = safe_call(backend.ready, root, kind)
    end
    if not eligible then
      state.failed_key = nil
      return fallback(picker, state, reason) or refresh
    end

    local key = root .. "\0" .. query
    local changed = not state.native or state.key ~= key
    if changed then
      state.items, state.raw_count, state.page, state.offset = {}, 0, 0, 0
      state.key, state.more, state.load_next = key, true, false
      state.generation = state.generation + 1
    end
    if state.failed_key == key then
      return fallback(picker, state, state.failed_reason) or refresh
    end
    if changed or state.load_next then
      state.load_next, state.pending, state.need_fetch = false, false, true
      refresh = true
    end
    state.native, state.reason = true, nil
    picker.opts.matcher.sort_empty = false
    -- Pagination bounds ordinary pages. A grep page may contain all matches in
    -- one file, so Snacks' generic live cap must not silently discard its tail.
    picker.opts.limit, picker.opts.limit_live = nil, nil
    if kind == "files" then
      filter.search, filter.pattern = query, ""
    end
    label(picker, state, kind)
    return refresh or changed
  end

  opts.finder = function(source, ctx)
    local picker = ctx.picker
    local state = states[picker]
    if not (state and state.native) then
      return original(source, ctx)
    end
    if not state.need_fetch then
      return state.items
    end
    local generation, key = state.generation, state.key
    local query, root = ctx.filter.search, ctx.filter.cwd
    return function(cb)
      repeat
        local done, result, reason = false, nil, nil
        local request = { page_size = PAGE_SIZE, page = state.page, file_offset = state.offset, mode = "regex" }
        local ok, returned, err = pcall(backend[kind], root, query, request, function(value, message)
          if picker.closed or states[picker] ~= state or state.generation ~= generation or ctx.async:aborted() then
            return
          end
          result, reason, done = value, message, true
          ctx.async:resume()
        end)
        if not ok then
          reason, done = tostring(returned), true
        elseif type(returned) == "table" then
          result, done = returned, true
        elseif returned == nil and not done then
          reason, done = err or "native search unavailable", true
        end
        if not done then
          ctx.async:suspend()
        end
        if picker.closed or states[picker] ~= state or state.generation ~= generation then
          return
        end
        if type(result) ~= "table" or type(result.items) ~= "table" then
          state.failed_key, state.failed_reason = key, reason or "native search unavailable"
          vim.schedule(function()
            if not picker.closed and states[picker] == state and state.generation == generation then
              picker:find { refresh = true }
            end
          end)
          return
        end
        for _, value in ipairs(result.items) do
          local item = item_from(value, root, kind)
          if item then
            state.items[#state.items + 1] = item
          end
        end
        state.raw_count = state.raw_count + #result.items
        state.total = tonumber(result.total_matched) or state.raw_count
        if kind == "files" then
          state.more = state.raw_count < state.total and #result.items > 0
          state.page = state.page + 1
        else
          local offset = tonumber(result.next_file_offset)
          state.more = offset ~= nil and offset > state.offset
          state.offset = offset or state.offset
        end
      until #state.items > 0 or not state.more
      state.need_fetch = false
      label(picker, state, kind)
      for _, item in ipairs(state.items) do
        -- A refresh has an unchanged matcher tick. Fresh finder items must not
        -- inherit its per-run match cache or previously shown rows disappear.
        local value = vim.tbl_extend("force", {}, item)
        value.match_tick, value.match_topk = nil, nil
        cb(value)
      end
    end
  end

  opts.on_change = function(picker, item)
    if original_change then
      original_change(picker, item)
    end
    local state = states[picker]
    if not state or picker.closed or picker:is_active() or state.need_fetch or not state.native or not state.more or state.pending then
      return
    end
    if picker.list.cursor < math.max(1, #state.items - PAGE_MARGIN) then
      return
    end
    state.pending = true
    local generation = state.generation
    local cursor, top = picker.list.cursor, picker.list.top
    vim.schedule(function()
      if picker.closed or states[picker] ~= state or state.generation ~= generation then
        return
      end
      state.load_next = true
      picker.list:set_target(cursor, top, { force = true })
      picker:find { refresh = true }
    end)
  end
  opts.on_close = function(picker)
    if states[picker] then
      states[picker].generation = states[picker].generation + 1
    end
    states[picker] = nil
    if original_close then
      original_close(picker)
    end
  end
  return opts
end

return M
