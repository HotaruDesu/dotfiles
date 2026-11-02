-- Run: nvim --headless -u NONE -i NONE -n -l tests/keymaps.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
_G.LunaVim = require "lunavim"
local maps = require "lunavim.config.keymaps"
local snapshot = dofile(root .. "/tests/helpers/keymaps.lua")
local expected = dofile(root .. "/tests/fixtures/keymaps.lua")
assert(vim.deep_equal(expected, snapshot(maps)), "Effective shortcut definitions changed")

maps.load_defaults()
maps.load_defaults()
for mode, list in pairs(maps.get_defaults()) do
  for lhs in pairs(list) do
    assert(next(vim.fn.maparg(lhs, maps.get_adapter()[mode], false, true)), "Missing default " .. lhs)
  end
end
local called
_G.Snacks = { picker = setmetatable({}, {
  __index = function(_, name)
    return function()
      called = name
    end
  end,
}) }
for _, mapping in ipairs(maps.plugin_nvim "snacks.nvim") do
  vim.keymap.set(unpack(mapping))
end
vim.fn.maparg("ghc", "n", false, true).callback()
assert(called == "lsp_outgoing_calls", "ghc must keep its existing effective action")
vim.cmd "LunaIncomingCalls"
assert(called == "lsp_incoming_calls")
assert(vim.fn.maparg("gr", "n", false, true).nowait == 1, "gr timing changed")

local original = maps.get_defaults().normal_mode["<C-H>"][1]
local copy = maps.get_defaults()
copy.normal_mode["<C-H>"][1] = "changed"
assert(maps.get_defaults().normal_mode["<C-H>"][1] == original, "Exported maps must not mutate private configuration")
assert(maps.get_plguins == maps.get_plugins and maps.nvim_normized == maps.normalize_nvim)

local hover
local old_hover = vim.lsp.buf.hover
vim.lsp.buf.hover = function()
  hover = true
end
local buf = vim.api.nvim_get_current_buf()
require("lunavim.plugins.lsp.keymaps").on_attach({ name = "clangd" }, buf)
assert(vim.fn.maparg("gh", "n", false, true).buffer == 1)
assert(vim.fn.maparg("<leader>cr", "n", false, true).rhs == "<Cmd>CppChangeSignature<CR>")
vim.fn.maparg("K", "n", false, true).callback()
assert(hover)
vim.lsp.buf.hover = old_hover
print "PASS: shortcut baseline, duplicate effective action, compatibility helpers and LSP buffer scope"
