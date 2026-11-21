-- Run: nvim --headless -u NONE -i NONE -n -l tests/dashboard.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local init = [[
  vim.opt.rtp:prepend(vim.fn.getcwd())
  for _, plugin in ipairs { "snacks.nvim", "lazy.nvim" } do
    vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
  end
  _G.LunaVim = require "lunavim"
  local options = require("lunavim.ui_specs.snacks")[1].opts
  require("snacks").setup { dashboard = options.dashboard }
]]
local function launch(neovide, file)
  local argv = { vim.v.progpath, "--embed", "-u", "NONE", "-i", "NONE", "-n", "--cmd", "lua vim.g.neovide = " .. tostring(neovide), "--cmd", "lua " .. init }
  if file then
    table.insert(argv, file)
  end
  local child = vim.fn.jobstart(argv, { rpc = true, cwd = root })
  local ok, result = pcall(function()
    vim.rpcrequest(child, "nvim_ui_attach", 100, 40, { rgb = true })
    return vim.rpcrequest(
      child,
      "nvim_exec_lua",
      [[
      assert(vim.wait(2000, function() return Snacks.dashboard.status.did_setup end))
      return { ft = vim.bo.filetype, name = vim.api.nvim_buf_get_name(0), opened = Snacks.dashboard.status.opened,
        content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") }
    ]],
      {}
    )
  end)
  vim.rpcnotify(child, "nvim_command", "qa!")
  local status = vim.fn.jobwait({ child }, 3000)[1]
  assert(ok, vim.inspect(result))
  assert(status == 0, "Test editor did not exit cleanly")
  return result
end
for _, neovide in ipairs { false, true } do
  local empty = launch(neovide)
  assert(empty.opened and empty.ft == "snacks_dashboard", "Empty launch should show the dashboard")
  assert(
    empty.content:find("██", 1, true) and empty.content:find("Find File", 1, true) and empty.content:find("Neovim loaded", 1, true),
    "Dashboard should render its header, shortcuts and startup information"
  )
  local file = root .. "/init.lua"
  local opened = launch(neovide, file)
  assert(not opened.opened and opened.name == file and opened.content:find('require("lunavim").setup()', 1, true), "Opening a file should show its contents")
end
print "PASS: complete dashboard on empty UI startup and direct file startup"
