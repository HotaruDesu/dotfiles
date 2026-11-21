-- Compare saved and current configurations with the same production picker.
-- LUNAVIM_BENCH_CONFIG=/path/to/config LUNAVIM_BENCH_OUTPUT=/tmp/result.json
-- nvim --headless -u NONE -i NONE -n -l scripts/benchmark_motion.lua [project]
local root = vim.env.LUNAVIM_BENCH_CONFIG or vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs { "snacks.nvim", "nvim-treesitter" } do
  vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/" .. plugin)
end
vim.o.swapfile = false
vim.o.showmode = false
vim.o.columns, vim.o.lines = 160, 50
vim.g.neovide = true -- Include the GUI indicator's editor-side overhead.
_G.LunaVim = require "lunavim"
require("snacks").setup(require("lunavim.ui_specs.snacks")[1].opts)
local directory = assert(vim.uv.fs_realpath(arg[1] or vim.fn.stdpath "data" .. "/lazy"))
local function now()
  return vim.uv.hrtime() / 1e6
end
local function wait(fn, diagnostic)
  if not vim.wait(10000, fn, 1) then
    error("Benchmark timed out: " .. (diagnostic and vim.inspect(diagnostic()) or "condition"))
  end
end
local function pause(ms)
  vim.wait(ms, function()
    return false
  end, 1)
end
local function settled(p)
  wait(function()
    return p.shown and not p:is_active() and p:count() > 0
  end)
end
local report =
  { config = root, directory = directory, runs = tonumber(vim.env.LUNAVIM_BENCH_RUNS) or 10, sources = {}, selection_ms = {}, hold_updates = {}, final_preview_ms = {} }
report.warmups = tonumber(vim.env.LUNAVIM_BENCH_WARMUPS) or 10
local queries = { files = { "config", "init", "util", "lua", "picker" }, grep = { "TODO", "FIXME", "LspAttach", "on_attach", "BufEnter" } }
for _, kind in ipairs { "files", "grep" } do
  local samples = { first_ms = {}, update_ms = {}, typing_ms = {} }
  report.sources[kind] = samples
  for run = 1 - report.warmups, report.runs do
    local query = queries[kind][run % 5 + 1]
    local started = now()
    local p = Snacks.picker(kind, {
      cwd = directory,
      pattern = kind == "files" and query or nil,
      search = kind == "grep" and query or nil,
    })
    wait(function()
      return p.shown and p.list:count() > 0 and vim.api.nvim_buf_get_lines(p.list.win.buf, 0, 1, false)[1] ~= ""
    end, function()
      return { kind = kind, run = run, query = query, shown = p.shown, closed = p.closed, active = p:is_active(), count = p:count(), list = p.list:count() }
    end)
    if run > 0 then
      samples.first_ms[#samples.first_ms + 1] = now() - started
    end
    settled(p)
    p:close()
    pause(10)
  end
  local p = Snacks.picker(kind, { cwd = directory, pattern = kind == "files" and "config" or nil, search = kind == "grep" and "BufEnter" or nil })
  for run = 1 - report.warmups, report.runs do
    settled(p)
    local query = queries[kind][run % 5 + 1]
    local task, tick = p.finder.task, p.matcher.tick
    local started = now()
    vim.api.nvim_buf_set_lines(p.input.win.buf, 0, -1, false, { query })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = p.input.win.buf })
    wait(function()
      local item = p.list:get(1)
      local text = item and (kind == "files" and item.file or item.line)
      return (p.finder.task ~= task or p.matcher.tick ~= tick) and not p:is_active() and text and text:lower():find(query:lower(), 1, true) ~= nil
    end)
    if run > 0 then
      samples.update_ms[#samples.update_ms + 1] = now() - started
    end
  end
  p:close()

  -- Type prefixes every 20ms; measure the final key to the settled final list.
  -- Record separately from replacing a complete query above.
  p = Snacks.picker(kind, { cwd = directory, pattern = kind == "files" and "config" or nil, search = kind == "grep" and "BufEnter" or nil })
  for run = 1 - report.warmups, tonumber(vim.env.LUNAVIM_BENCH_TYPING_RUNS) or report.runs do
    settled(p)
    local query = queries[kind][run % 5 + 1]
    local started, task, tick
    for length = 1, #query do
      task, tick = p.finder.task, p.matcher.tick
      started = now()
      vim.api.nvim_buf_set_lines(p.input.win.buf, 0, -1, false, { query:sub(1, length) })
      vim.api.nvim_exec_autocmds("TextChangedI", { buffer = p.input.win.buf })
      if length < #query then
        pause(math.max(0, 20 - (now() - started)))
      end
    end
    wait(function()
      local item = p.list:get(1)
      local text = item and (kind == "files" and item.file or item.line)
      return (p.finder.task ~= task or p.matcher.tick ~= tick) and not p:is_active() and text and text:lower():find(query:lower(), 1, true) ~= nil
    end)
    if run > 0 then
      samples.typing_ms[#samples.typing_ms + 1] = now() - started
    end
  end
  p:close()
end

for run = 1, tonumber(vim.env.LUNAVIM_BENCH_HOLD_RUNS) or report.runs do
  local p = Snacks.picker.files { cwd = directory, pattern = "lua" }
  settled(p)
  local action = assert(vim.fn.maparg("<C-j>", "i", false, true).callback)
  local final_file = assert(io.open(Snacks.picker.util.path(p.list:get(51)), "r"))
  local expected_line = final_file:read "*l" or ""
  final_file:close()
  local line_limit = p.opts.previewers.file.max_line_length
  if #expected_line > line_limit then
    expected_line = expected_line:sub(1, line_limit) .. "..."
  end
  local rendered, updates = nil, 0
  local function revision()
    local b = p.preview.win.buf
    return p.preview.win:valid() and (b .. ":" .. vim.api.nvim_buf_get_changedtick(b) .. ":" .. tostring(p.preview.title)) or ""
  end
  for key = 1, 50 do
    local started = now()
    action()
    assert(p.list.cursor == key + 1, "Mapped selection did not advance")
    report.selection_ms[#report.selection_ms + 1] = now() - started
    pause(math.max(0, 20 - (now() - started)))
    local current = revision()
    if rendered and current ~= rendered then
      updates = updates + 1
    end
    rendered = current
  end
  report.hold_updates[#report.hold_updates + 1] = updates
  local start = now()
  local item = p:current()
  local expected = vim.fn.fnamemodify(item.file, ":t")
  local rendered_final = vim.wait(10000, function()
    return p.preview.title == expected and p.preview.win:valid() and vim.api.nvim_buf_get_lines(p.preview.win.buf, 0, 1, false)[1] == expected_line
  end, 1)
  assert(rendered_final, vim.inspect { expected = expected, title = p.preview.title, file = item.file, content = vim.api.nvim_buf_get_lines(p.preview.win.buf, 0, 3, false) })
  report.final_preview_ms[#report.final_preview_ms + 1] = now() - start
  p:close()
  pause(10)
end
local output = vim.json.encode(report)
if vim.env.LUNAVIM_BENCH_OUTPUT then
  vim.fn.writefile({ output }, vim.env.LUNAVIM_BENCH_OUTPUT)
end
print(output)
