-- Run: nvim --headless -u NONE -i NONE -n -l tests/startup.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local bootstrap = [[
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
local lazy = require("lazy")
local setup = lazy.setup
lazy.setup = function(opts)
  opts.checker.enabled = false
  opts.install = { missing = false }
  setup(opts)
end
]]
local smoke = [[
assert(LunaVim == require("lunavim"))
require("lunavim.config").setup()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "class T {};" })
vim.bo.filetype = "cpp"
assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()])
assert(vim.bo.syntax == "")
require("lazy").load({ plugins = { "nvim-lspconfig", "noice.nvim", "aerial.nvim", "conform.nvim", "persistence.nvim" } })
assert(vim.fn.exists(":LunaSpellFix") == 2)
assert(vim.fn.exists(":CppChangeSignature") == 2)
assert(vim.fn.exists(":LunaIncomingCalls") == 2)
assert(vim.fn.maparg("<leader>,,", "n", false, true).desc == "Format Buffer")
local config = require("lazy.core.config")
for name, plugin in pairs(config.plugins) do
  assert(not plugin._.has_errors, "Plugin failed: " .. name)
end
assert(not vim.fn.execute("messages"):match("Error"), vim.fn.execute("messages"))
print("STARTUP_OK")
]]
for _, gui in ipairs { false, true } do
  local result = vim
    .system({
      vim.v.progpath,
      "--headless",
      "-u",
      root .. "/init.lua",
      "-i",
      "NONE",
      "-n",
      "--cmd",
      "lua " .. (gui and "vim.g.neovide = true; " or "") .. bootstrap,
      "+lua " .. smoke,
      "+qa!",
    }, { text = true, cwd = root })
    :wait(20000)
  local output = (result.stdout or "") .. (result.stderr or "")
  assert(result.code == 0 and output:find("STARTUP_OK", 1, true) and not output:match "Error", output)
end
print "PASS: full plugin startup, reload and existing shortcuts in terminal/Neovide profiles"
