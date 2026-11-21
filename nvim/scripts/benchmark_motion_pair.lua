-- nvim --headless -u NONE -i NONE -n -l scripts/benchmark_motion_pair.lua BASELINE [PROJECT]
-- Both workers stay alive; adjacent A/B queries share nearly the same host load.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local baseline = assert(arg[1], "Pass the saved baseline configuration directory")
local project = vim.uv.fs_realpath(arg[2] or vim.fn.stdpath "data" .. "/lazy")
local queries = { files = { "init", "util", "lua", "picker", "config" }, grep = { "FIXME", "LspAttach", "on_attach", "BufEnter", "TODO" } }
local jobs, report = {}, { project = project, warmups = 10, protocol = "paired persistent workers; alternate order for every query", rounds = {} }
local function call(variant, method, ...)
  return vim.rpcrequest(jobs[variant], "nvim_exec_lua", "return MotionBench[...](select(2, ...))", { method, ... })
end
local function pair(round, sample, fn)
  local order = (round + sample) % 2 == 0 and { "before", "after" } or { "after", "before" }
  for _, variant in ipairs(order) do
    fn(variant)
  end
end
local ok, err = xpcall(function()
  for variant, config in pairs { before = baseline, after = root } do
    jobs[variant] = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
    assert(jobs[variant] > 0)
    vim.rpcrequest(
      jobs[variant],
      "nvim_exec_lua",
      "local script, config, project = ...; dofile(script)(config, project)",
      { root .. "/scripts/benchmark_motion_worker.lua", config, project }
    )
    report.rounds[variant] = {}
    for round = 1, 3 do
      report.rounds[variant][round] = { sources = { files = {}, grep = {} }, selection_ms = {}, hold_updates = {}, final_preview_ms = {} }
    end
  end
  for _, kind in ipairs { "files", "grep" } do
    for _, metric in ipairs { "first_ms", "update_ms", "typing_ms" } do
      local method = metric == "first_ms" and "first" or "input"
      if method == "input" then
        for _, variant in ipairs { "before", "after" } do
          call(variant, "prepare", kind)
        end
      end
      for warmup = 1, report.warmups do
        pair(0, warmup, function(v)
          call(v, method, kind, queries[kind][(warmup - 1) % 5 + 1], metric == "typing_ms")
        end)
      end
      for round = 1, 3 do
        for sample = 1, metric == "typing_ms" and 10 or 30 do
          pair(round, sample, function(v)
            local samples = report.rounds[v][round].sources[kind][metric] or {}
            samples[#samples + 1] = call(v, method, kind, queries[kind][(sample - 1) % 5 + 1], metric == "typing_ms")
            report.rounds[v][round].sources[kind][metric] = samples
          end)
        end
        print(kind .. " " .. metric .. " round " .. round .. " complete")
      end
      for _, variant in ipairs { "before", "after" } do
        call(variant, "close")
      end
    end
  end
  for round = 1, 3 do
    for sample = 1, 10 do
      pair(round, sample, function(v)
        local result, data = call(v, "hold"), report.rounds[v][round]
        vim.list_extend(data.selection_ms, result.selection_ms)
        data.hold_updates[#data.hold_updates + 1] = result.hold_updates
        data.final_preview_ms[#data.final_preview_ms + 1] = result.final_preview_ms
      end)
    end
    print("hold round " .. round .. " complete")
  end
end, debug.traceback)
for _, job in pairs(jobs) do
  vim.fn.jobstop(job)
end
assert(ok, err)
vim.fn.writefile({ vim.json.encode(report) }, vim.env.LUNAVIM_BENCH_OUTPUT or "/tmp/lunavim-motion-paired.json")
print "Paired benchmark complete"
