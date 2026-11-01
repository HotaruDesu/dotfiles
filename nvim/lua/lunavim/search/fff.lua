local M = {}
local uv = vim.uv
local state = { generation = 0, next_id = 0, reason = "not initialized" }
local pending, queued = {}, {}
local active
local group = vim.api.nvim_create_augroup("LunaVimSearchWorker", { clear = true })

local function plugin_path()
  return require("lunavim.config.search").native_path or vim.fn.stdpath "data" .. "/lazy/fff"
end

local function fail(request, reason)
  if request.timer then
    request.timer:stop()
    request.timer:close()
  end
  if request.callback then
    vim.schedule(function()
      request.callback(nil, reason)
    end)
  end
end

function M.stop(reason)
  state.generation = state.generation + 1
  state.ready, state.reason = false, reason or "stopped"
  if not reason then
    -- Explicitly disabling native search must still allow re-enabling it in
    -- the same project. Failed workers retain their root until manual retry.
    state.root = nil
  end
  for _, request in pairs(pending) do
    fail(request, state.reason)
  end
  for _, request in pairs(queued) do
    fail(request, state.reason)
  end
  pending, queued, active = {}, {}, nil
  local job = state.job
  state.job = nil
  if job then
    pcall(vim.fn.jobstop, job)
  end
end

local function dispatch(request)
  active = request.id
  pending[request.id] = request
  request.timer = assert(uv.new_timer())
  request.timer:start(
    2000,
    0,
    vim.schedule_wrap(function()
      if pending[request.id] then
        M.stop "native search timed out; use LunaSearchRefresh to retry"
      end
    end)
  )
  vim.rpcnotify(state.job, "nvim_exec_lua", "require('lunavim.search.worker').query(...)", {
    request.id,
    request.kind,
    request.query,
    request.options,
  })
end

local function next_request()
  if active then
    return
  end
  for _, kind in ipairs { "files", "grep" } do
    local request = queued[kind]
    if request then
      queued[kind] = nil
      return dispatch(request)
    end
  end
end

function M.deliver(generation, id, result, err)
  if generation ~= state.generation then
    return
  end
  if id == 0 then
    state.ready, state.reason = result and result.ready == true or false, err
    state.files = result and result.files
    state.compatible = result and result.compatible
    state.rss = result and result.rss
    if err then
      M.stop(err)
    end
    return
  end
  local request = pending[id]
  if not request then
    return
  end
  pending[id], active = nil, nil
  request.timer:stop()
  request.timer:close()
  if result and result.rss then
    state.rss = math.max(state.rss or 0, result.rss)
  end
  if request.callback then
    request.callback(result, err)
  end
  next_request()
end

function M.warm(root)
  root = root and (uv.fs_realpath(root) or vim.fs.normalize(root))
  if not root or root == "/" or root == uv.os_homedir() then
    return false, "indexing scope refused"
  end
  if state.root == root and (state.job or state.reason ~= "not initialized") then
    return state.ready == true, state.reason or "index warming"
  end
  M.stop "project changed"
  state.root, state.reason = root, "index warming"
  local plugin = plugin_path()
  if not uv.fs_stat(plugin .. "/lua/fff.lua") then
    state.reason = "FFF is not installed"
    return false, state.reason
  end
  local runtime = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
  local generation = state.generation
  local job = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, {
    rpc = true,
    on_exit = function()
      if state.generation == generation and state.job then
        M.stop "native worker exited"
      end
    end,
  })
  if job <= 0 then
    state.reason = "could not start native worker"
    return false, state.reason
  end
  state.job = job
  vim.rpcnotify(job, "nvim_exec_lua", "local p,opts=...; vim.opt.rtp:prepend(p); require('lunavim.search.worker').start(opts)", {
    runtime,
    { plugin = plugin, root = root, generation = generation, max_threads = require("lunavim.config.search").max_threads },
  })
  return false, state.reason
end

function M.ready(root, kind)
  root = root and (uv.fs_realpath(root) or vim.fs.normalize(root))
  if root ~= state.root then
    return false, "different project"
  end
  if state.ready and kind and state.compatible and state.compatible[kind] == false then
    return false, "index coverage differs from " .. (kind == "files" and "fd" or "rg")
  end
  return state.ready == true, state.reason or "index warming"
end

local function query(kind, root, text, options, callback)
  local ready, reason = M.ready(root, kind)
  if not ready then
    if callback then
      vim.schedule(function()
        callback(nil, reason)
      end)
    end
    return nil, reason
  end
  if not callback then
    return nil, "native search requires an asynchronous callback"
  end
  state.next_id = state.next_id + 1
  local request = { id = state.next_id, kind = kind, query = text, options = options or {}, callback = callback }
  -- Keep at most one running query and the latest queued query per source.
  -- Rapid typing cannot accumulate an unbounded backlog of native calls.
  if active then
    if queued[kind] then
      fail(queued[kind], "superseded")
    end
    queued[kind] = request
  else
    dispatch(request)
  end
  return request.id
end

function M.files(root, text, options, callback)
  return query("files", root, text, options, callback)
end
function M.grep(root, text, options, callback)
  return query("grep", root, text, options, callback)
end
function M.refresh()
  local root = state.root
  M.stop "not initialized"
  state.root = nil
  if root then
    M.warm(root)
  end
end
function M.status()
  return {
    root = state.root,
    ready = state.ready == true,
    reason = state.reason,
    pid = state.job and vim.fn.jobpid(state.job),
    files = state.files,
    compatible = state.compatible,
    rss = state.rss,
  }
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    M.stop()
  end,
})
return M
