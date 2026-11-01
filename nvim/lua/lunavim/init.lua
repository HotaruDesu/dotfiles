local M = {}

M.icons = require "lunavim.config.icons"

M.util = require "lunavim.util"

local keymaps = require "lunavim.config.keymaps"
M.plugin_lazy = keymaps.plugin_lazy
M.plugin_nvim = keymaps.plugin_nvim
M.plugin_raw = keymaps.plugin_raw

function M.setup()
  _G.LunaVim = M
  require("lunavim.config").setup()
  require("lunavim.lazy").setup()
end

return M
