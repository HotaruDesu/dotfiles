local M = {}

function M.setup()
  require "lunavim.config.options"
  require("lunavim.config.autocmds").setup()
  require("lunavim.config.keymaps").load_defaults()
  vim.keymap.set("n", "<leader>wn", require("lunavim.util.window").send_to_next_tab, { desc = "Move Window to Next Tab" })
end

return M
