-- nvim --headless -u NONE -i NONE -n -l scripts/benchmark_search.lua [directory]
-- Compare complete Snacks picker pipelines; no renderer-free CLI timings.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/snacks.nvim")
_G.LunaVim = require "lunavim"
vim.o.swapfile = false
vim.o.columns, vim.o.lines = 160, 50
local config = require "lunavim.config.search"
config.native_path = vim.env.LUNAVIM_FFF_PATH or config.native_path
local snacks = require("lunavim.ui_specs.snacks")[1]
require("snacks").setup(snacks.opts)
local backend = require "lunavim.search.fff"
local finder = require "lunavim.search.finder"
local directory = vim.uv.fs_realpath(arg[1] or vim.fn.stdpath "data" .. "/lazy")
assert(directory, "Directory not found")
local index_start = vim.uv.hrtime()
backend.warm(directory)
assert(
  vim.wait(35000, function()
    return backend.ready(directory) or backend.status().reason ~= "index warming"
  end, 10),
  vim.inspect(backend.status())
)
assert(backend.ready(directory), vim.inspect(backend.status()))
local index_prepare_ms = (vim.uv.hrtime() - index_start) / 1e6

local function percentile(values, fraction)
  table.sort(values)
  return values[math.max(1, math.ceil(#values * fraction))]
end
local report = {
  directory = directory,
  native = backend.status(),
  index_prepare_ms = index_prepare_ms,
  runs = 20,
  preview_delay_ms = 120,
  environment = { nvim = tostring(vim.version()), machine = vim.uv.os_uname().machine },
  sources = {},
}
local function sample(kind, mode, query)
  config[kind] = mode
  local start = vim.uv.hrtime()
  local picker = Snacks.picker(kind, {
    cwd = directory,
    pattern = kind == "files" and query or nil,
    search = kind == "grep" and query or nil,
  })
  local input_ms, results_ms
  assert(
    vim.wait(10000, function()
      local elapsed = (vim.uv.hrtime() - start) / 1e6
      if picker.shown and not input_ms then
        input_ms = elapsed
      end
      if picker.shown and picker.list:count() > 0 then
        results_ms = elapsed
        return true
      end
      return picker.closed
    end, 1),
    "Timed out: " .. kind .. " " .. query
  )
  assert(not picker.closed and results_ms, "Unexpected empty sample")
  local status = finder.status(picker)
  assert(
    vim.wait(10000, function()
      return not picker:is_active()
    end, 1),
    "Finder did not settle: " .. kind .. "/" .. mode .. "/" .. query
  )
  picker:close()
  vim.wait(5, function()
    return false
  end)
  return input_ms, results_ms, status
end

local queries = { files = { "config", "init", "util", "lua", "picker" }, grep = { "TODO", "FIXME", "LspAttach", "on_attach", "BufEnter" } }
local function updates(kind, mode)
  config[kind] = mode
  local picker = Snacks.picker(kind, { cwd = directory, pattern = kind == "files" and "init" or nil, search = kind == "grep" and "BufEnter" or nil })
  local values = {}
  for run = 1, report.runs + 1 do
    assert(
      vim.wait(10000, function()
        return picker.shown and not picker:is_active() and picker.list:count() > 0
      end, 1),
      "Input sample did not settle"
    )
    local query = queries[kind][(run - 1) % #queries[kind] + 1]
    local previous = picker.finder.task
    local tick = picker.matcher.tick
    local start = vim.uv.hrtime()
    vim.api.nvim_buf_set_lines(picker.input.win.buf, 0, -1, false, { query })
    -- Use the real input listener, including Snacks' 30/200ms throttling.
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = picker.input.win.buf })
    assert(
      vim.wait(10000, function()
        local changed = picker.finder.task ~= previous or picker.matcher.tick ~= tick
        local item = picker.list:get(1)
        local text = item and (kind == "files" and item.file or item.line)
        return changed and not picker:is_active() and text and text:lower():find(query:lower(), 1, true) ~= nil
      end, 1),
      "Input query did not update: " .. kind .. "/" .. mode .. "/" .. query
    )
    if run > 1 then
      values[#values + 1] = (vim.uv.hrtime() - start) / 1e6
    end
  end
  local status = finder.status(picker)
  if mode == "fff" then
    assert(status and status.backend == "fff", vim.inspect(status))
  end
  picker:close()
  return percentile(values, 0.5), percentile(values, 0.95)
end

local ok, err = xpcall(function()
  for _, kind in ipairs { "files", "grep" } do
    local entry = { compatible = backend.ready(directory, kind) }
    report.sources[kind] = entry
    local modes = entry.compatible and { "snacks", "fff" } or { "snacks" }
    for _, mode in ipairs(modes) do
      local input, results = {}, {}
      sample(kind, mode, queries[kind][1]) -- unrecorded first open
      for run = 1, report.runs do
        local shown, first, status = sample(kind, mode, queries[kind][(run - 1) % #queries[kind] + 1])
        if mode == "fff" then
          assert(status and status.backend == "fff", vim.inspect(status))
        end
        input[#input + 1], results[#results + 1] = shown, first
      end
      entry[mode] = {
        input_median_ms = percentile(input, 0.5),
        first_median_ms = percentile(results, 0.5),
        first_p95_ms = percentile(results, 0.95),
      }
      entry[mode].update_median_ms, entry[mode].update_p95_ms = updates(kind, mode)
    end
    if entry.fff then
      entry.passes_latency_gate = entry.fff.first_median_ms <= entry.snacks.first_median_ms * 0.8 and entry.fff.first_p95_ms <= entry.snacks.first_p95_ms
    end
  end
  report.native = backend.status()
end, debug.traceback)
backend.stop()
for _, picker in ipairs(Snacks.picker.get()) do
  picker:close()
end
if not ok then
  error(err)
end
local output = vim.json.encode(report)
if vim.env.LUNAVIM_BENCH_OUTPUT then
  vim.fn.writefile({ output }, vim.env.LUNAVIM_BENCH_OUTPUT)
end
print(output)
