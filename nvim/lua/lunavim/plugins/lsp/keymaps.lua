local M = {}

local server_keymaps = {
  clangd = {
    { "n", "gh", "<Cmd>LspClangdSwitchSourceHeader<CR>", { desc = "Switch Source/Header" } },
    { "n", "<leader>ci", "<Cmd>LspClangdShowSymbolInfo<CR>", { desc = "Clangd Symbol Info" } },
  },
}

local function set_keymaps(keymaps, bufnr)
  for _, keymap in ipairs(keymaps) do
    local mode, lhs, rhs, opts = unpack(keymap)
    opts = vim.tbl_deep_extend("force", {}, opts or {}, {
      buffer = bufnr,
      silent = true,
    })
    vim.keymap.set(mode, lhs, rhs, opts)
  end
end

function M.on_attach(client, bufnr)
  set_keymaps(LunaVim.plugin_nvim "lsp" or {}, bufnr)
  set_keymaps(server_keymaps[client.name] or {}, bufnr)
end

return M
