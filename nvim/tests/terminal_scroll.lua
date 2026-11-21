-- Exercise a real Snacks scroll between two successive TUI inputs.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local setup = [[
  vim.opt.rtp:prepend(vim.fn.getcwd())
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
  _G.LunaVim = require "lunavim"
  vim.o.scrolloff = 8
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({"line"}, 500))
  local spec = require("lunavim.ui_specs.snacks")[1]
  local scroll = spec.opts.scroll
  assert(scroll.enabled and scroll.animate.duration.total == 140)
  -- Give the test driver time to send the edit during an intermediate frame.
  scroll.animate.duration.total = 600
  spec.config(nil, { scroll = scroll })
]]
local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "-n", "-i", "NONE", "-u", "NONE" }, { rpc = true, cwd = root })
local function evaluate(expr)
  return vim.rpcrequest(child, "nvim_exec_lua", "return " .. expr, {})
end
local ok, err = pcall(function()
  vim.rpcrequest(child, "nvim_ui_attach", 120, 36, { rgb = true })
  vim.rpcrequest(child, "nvim_exec_lua", setup, {})
  vim.rpcrequest(child, "nvim_input", "G")
  assert(
    vim.wait(1500, function()
      local row = evaluate 'vim.fn.line(".")'
      return row > 1 and row < 500
    end, 5),
    "No intermediate scroll frame"
  )
  vim.rpcrequest(child, "nvim_input", "A at destination<Esc>")
  assert(
    vim.wait(1000, function()
      return evaluate 'vim.fn.getline(500) == "line at destination" and vim.wo.scrolloff == 8'
    end),
    "Editing during a scroll must use the destination"
  )
end)
pcall(vim.rpcnotify, child, "nvim_command", "qa!")
vim.fn.jobwait({ child }, 2000)
assert(ok, err)
print "PASS: editing during a terminal scroll uses the destination line"
