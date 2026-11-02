-- Run: NVIM_LOG_FILE=/tmp/lunavim-ui.log nvim --headless -u NONE -i NONE -n -l tests/ui.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs { "tokyonight.nvim", "snacks.nvim" } do
  vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/" .. plugin)
end
vim.o.swapfile = false
vim.o.termguicolors = true
_G.LunaVim = {
  icons = require "lunavim.config.icons",
  plugin_lazy = function()
    return {}
  end,
}

local profile = require "lunavim.config.ui"
vim.g.neovide = true
vim.g.lunavim_ui_style = "glass"
vim.g.lunavim_reduced_motion = false
local glass = profile.get()
assert(glass.opacity == 0.96 and glass.float_blend == 0 and not glass.transparent)
require("lunavim.config.neovide").setup()
assert(vim.g.neovide_window_blurred and not vim.g.neovide_floating_shadow)
assert(vim.g.neovide_normal_opacity == 1)
assert(vim.g.neovide_floating_blur_amount_x == 0 and vim.g.neovide_floating_blur_amount_y == 0)
assert(vim.g.neovide_floating_corner_radius == 0, "Internal float grids must not clip their shared surface")
assert(vim.o.guifont == "Maple Mono NF CN:h12")
for _, mode in ipairs { "n", "i", "v" } do
  for _, key in ipairs { "<D-->", "<D-=>", "<D-+>", "<D-0>", "<D-s>" } do
    assert(next(vim.fn.maparg(key, mode, false, true)), "Missing native shortcut " .. key)
  end
end
vim.fn.maparg("<D-+>", "n", false, true).callback()
assert(vim.g.neovide_scale_factor > 1, "Zoom shortcut changed behavior")
vim.fn.maparg("<D-0>", "n", false, true).callback()
assert(vim.g.neovide_scale_factor == 1)
local fullscreen = vim.g.neovide_fullscreen
vim.fn.maparg("<F11>", "n", false, true).callback()
assert(vim.g.neovide_fullscreen == not fullscreen)

local function load_theme()
  local theme = dofile(root .. "/lua/lunavim/ui_specs/theme.lua")[1]
  theme.opts.cache = false
  theme.config(nil, theme.opts)
end
load_theme()
local function highlight(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end
for _, name in ipairs { "NormalFloat", "SnacksPickerInput", "SnacksPickerList", "SnacksPickerPreview", "SnacksPickerBox", "SnacksTerminal", "LunaVimTab" } do
  assert(highlight("Normal").bg == highlight(name).bg, name .. " must share the same background")
end
assert(highlight("LunaVimTabSelected").bg ~= highlight("LunaVimTab").bg, "Active tab needs a distinct surface")
assert(highlight("@keyword.type.cpp").fg ~= highlight("@type.cpp").fg, "UI must preserve syntax categories")

local notifications = dofile(root .. "/lua/lunavim/ui_specs/notifications.lua")[1].opts
assert(notifications.lsp.signature.enabled == false, "Blink must be the only automatic signature popup")
assert(notifications.views.cmdline_popup.win_options.winblend == 0)
local chrome = dofile(root .. "/lua/lunavim/ui_specs/chrome.lua")
assert(chrome[1].opts.options.component_separators and not chrome[1].opts.options.component_separator)
assert(chrome[2].opts.options.mode == "tabs", "Tab workflow changed")
assert(chrome[2].opts.highlights.tab_selected.bold)
assert(chrome[2].opts.options.diagnostics_indicator(1, "hint"):find(LunaVim.icons.diagnostics.Hint, 1, true))

local snacks = dofile(root .. "/lua/lunavim/ui_specs/snacks.lua")[1].opts
vim.o.columns = 160
assert(snacks.picker.layout.preset() == "luna_horizontal")
vim.o.columns = 100
assert(snacks.picker.layout.preset() == "luna_vertical")
assert(snacks.picker.layouts.luna_vertical.layout[3].height < 0.5, "Preview leaves too little room for results")
assert(snacks.picker.win.input.keys["<C-j>"][1] == "list_down")
assert(snacks.picker.win.input.keys["<C-k>"][1] == "list_up")

-- Use real Snacks layouts as well as inspecting their options. This catches
-- unsupported layout/window settings without depending on an interactive GUI.
require("snacks").setup(snacks)
vim.o.lines = 50
for _, columns in ipairs { 100, 160 } do
  vim.o.columns = columns
  local picker = Snacks.picker { items = { { text = "sample.cpp" } }, format = "text" }
  vim.wait(100, function()
    return false
  end)
  assert(picker.layout, "Picker layout was not created")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      assert(vim.wo[win].winblend == 0, "Nested picker floats must not composite their own transparency")
    end
  end
  picker:close()
end

vim.g.lunavim_ui_style = "solid"
vim.g.lunavim_reduced_motion = true
require("lunavim.config.neovide").setup()
assert(vim.g.neovide_opacity == 1 and vim.g.neovide_normal_opacity == 1)
assert(not vim.g.neovide_window_blurred and not vim.g.neovide_floating_shadow)
assert(vim.g.neovide_cursor_animation_length == 0 and vim.g.neovide_scroll_animation_length == 0)
assert(vim.g.neovide_cursor_vfx_mode == "")
local solid = dofile(root .. "/lua/lunavim/ui_specs/snacks.lua")[1].opts
assert(solid.styles.picker.wo.winblend == 0 and not solid.indent.animate.enabled)

vim.g.neovide = false
vim.g.lunavim_ui_style = "glass"
local terminal = profile.get()
assert(terminal.transparent and terminal.float_blend == 0, "Terminal fallback must keep float text clear")
load_theme()
assert(not highlight("Normal").bg and highlight("NormalFloat").bg, "Terminal should inherit host background with opaque panels")
print "PASS: UI profiles, syntax contrast, uniform surfaces, native shortcuts and responsive picker"
