-- Run: NVIM_LOG_FILE=/tmp/lunavim-ui.log nvim --headless -u NONE -i NONE -n -l tests/ui.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs { "tokyonight.nvim", "snacks.nvim", "bufferline.nvim", "nvim-web-devicons" } do
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
vim.g.lunavim_ui_style = nil
vim.g.lunavim_reduced_motion = false
require("lunavim.config.neovide").setup()
assert(vim.g.neovide_opacity == 1 and not vim.g.neovide_window_blurred, "Neovide should start fully opaque")
assert(not vim.g.neovide_floating_shadow)
assert(vim.g.neovide_normal_opacity == 1)
assert(vim.g.neovide_floating_blur_amount_x == 0 and vim.g.neovide_floating_blur_amount_y == 0)
assert(vim.g.neovide_floating_corner_radius == 0, "Internal float grids must not clip their shared surface")
assert(vim.g.neovide_cursor_animate_command_line and vim.g.neovide_cursor_animate_in_insert_mode)
assert(vim.g.neovide_position_animation_length == 0.12 and vim.g.neovide_cursor_animation_length == 0.14)
assert(vim.g.neovide_scroll_animation_length == 0.14 and vim.g.neovide_scroll_animation_far_lines == 9999)
assert(vim.g.neovide_cursor_short_animation_length == 0.05 and vim.g.neovide_cursor_vfx_mode == "pixiedust")
assert(vim.o.guifont == "Maple Mono NF CN:h14")
for _, mode in ipairs { "n", "i", "v" } do
  for _, key in ipairs { "<D-->", "<D-=>", "<D-+>", "<D-0>" } do
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
for _, name in ipairs { "NoiceCmdlinePopup", "NoiceCmdlineIconCmdline", "NoiceCmdlinePopupBorder", "LunaVimCmdlineMenu", "LunaVimCmdlineBorder" } do
  assert(highlight(name).bg == highlight("Normal").bg, name .. " should have the editor background")
end
assert(highlight("NoiceCmdlinePopupBorder").fg == 0x606a84)
assert(highlight("BlinkCmpMenu").bg == highlight("NormalFloat").bg, "Insert completion keeps its floating surface")
local input, list, preview = highlight "SnacksPickerInput", highlight "SnacksPickerList", highlight "SnacksPickerPreview"
assert(input.bg > list.bg and list.bg > preview.bg, "Picker input, results and preview should have distinct surfaces")
assert(highlight("SnacksPickerPreviewTitle").bg == preview.bg and highlight("SnacksPickerInputBorder").bg == input.bg)
assert(highlight("SnacksPickerBoxBorder").fg ~= highlight("SnacksPickerListBorder").fg)
assert(highlight("LunaVimTerminalFloat").bg == highlight("NormalFloat").bg and highlight("SnacksTerminal").bg == highlight("Normal").bg)
assert(highlight("Normal").bg == 0x1a1b26 and highlight("NormalFloat").bg == 0x21232f)
assert(highlight("LunaVimTab").bg == 0x16161e and highlight("StatusLine").bg == highlight("LunaVimTab").bg)
assert(highlight("NormalNC").bg ~= highlight("Normal").bg, "Inactive splits need a distinct background")
assert(highlight("LunaVimTabSelected").bg ~= highlight("LunaVimTab").bg, "Active tab needs a distinct surface")
assert(highlight("@keyword.type.cpp").fg ~= highlight("@type.cpp").fg, "UI must preserve syntax categories")
local shared = {}
for _, group in ipairs {
  "Normal",
  "NormalNC",
  "NormalFloat",
  "StatusLine",
  "CursorLine",
  "CursorLineNr",
  "WinSeparator",
  "SnacksPickerInput",
  "SnacksPickerList",
  "SnacksPickerPreview",
  "NoiceCmdlinePopup",
  "NoiceCmdlinePopupBorder",
  "BlinkCmpMenu",
  "LunaVimTab",
  "LunaVimTabSelected",
  "LunaVimTabSeparator",
  "LunaVimTabIndicator",
  "LunaVimInclineFile",
  "LunaVimInclineFileInactive",
  "LunaVimInclineFileModified",
  "LunaVimInclineModifiedInactive",
} do
  shared[group] = highlight(group)
end

local notifications = dofile(root .. "/lua/lunavim/ui_specs/notifications.lua")[1].opts
assert(notifications.lsp.signature.enabled == false, "Blink must be the only automatic signature popup")
assert(notifications.views.cmdline_popup.win_options.winblend == 0)
assert(notifications.views.cmdline_popup.size.min_width == 48)
assert(notifications.views.cmdline_popup.border.style == "rounded" and notifications.cmdline.opts.border.text.top == "")
assert(notifications.presets.bottom_search and not notifications.presets.command_palette)
assert(vim.deep_equal(notifications.views.cmdline_popup.position, { row = "32%", col = "50%" }))
local chrome = dofile(root .. "/lua/lunavim/ui_specs/chrome.lua")
assert(chrome[1].opts.options.component_separators and not chrome[1].opts.options.component_separator)
assert(chrome[2].opts.options.mode == "tabs", "Tab workflow changed")
assert(chrome[2].opts.options.show_buffer_close_icons == false)
assert(chrome[2].opts.options.diagnostics_indicator(1, "hint"):find(LunaVim.icons.diagnostics.Hint, 1, true))

-- In tabs mode bufferline still renders filenames with its buffer highlight groups.
chrome[2].init()
require("bufferline").setup(chrome[2].opts)
vim.cmd "file alpha.lua"
local source = vim.api.nvim_get_current_tabpage()
local first_win = vim.api.nvim_get_current_win()
local function first_row()
  return vim.fn.win_screenpos(vim.fn.win_id2win(first_win))[1]
end
assert(first_row() == 1, "A single tab should leave the first screen row to the editor")
vim.cmd.vsplit()
require("lunavim.util.window").send_to_next_tab()
assert(vim.api.nvim_get_current_tabpage() == source and first_row() == 2, "A second background tab must reveal the strip on the source page")
vim.cmd "tabclose 2"
assert(first_row() == 1, "Closing the second tab must release its row immediately")
vim.cmd "tabnew beta.lua"
local tabline = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, highlights = true, maxwidth = 140 })
assert(tabline.str:find("│", 1, true) and tabline.str:find("▎", 1, true), "Tabs should have dividers and an active marker")
for filename, group in pairs { ["alpha.lua"] = "BufferLineBackground", ["beta.lua"] = "BufferLineBufferSelected" } do
  local start = assert(tabline.str:find(filename, 1, true))
  local rendered_group
  for _, item in ipairs(tabline.highlights) do
    if item.start >= start then
      break
    end
    rendered_group = item.group
  end
  assert(rendered_group == group, filename .. " rendered with " .. tostring(rendered_group))
end
assert(highlight("BufferLineBufferSelected").bg == highlight("LunaVimTabSelected").bg)
assert(not tabline.str:find(require("bufferline.config").options.buffer_close_icon, 1, true), "Unexpected close icon")

vim.cmd "tabnew gamma.lua"
for _, tabnr in ipairs { 1, 2, 3 } do
  vim.cmd.tabnext(tabnr)
  local labels = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 140 }).str
  assert(select(2, labels:gsub("│", "")) == 2 and select(2, labels:gsub("▎", "")) == 1, "Expected two dividers and one active marker")
end
vim.cmd "tabclose"
vim.cmd "tabclose"

local snacks = dofile(root .. "/lua/lunavim/ui_specs/snacks.lua")[1].opts
assert(not snacks.indent.animate.enabled and snacks.indent.scope.only_current)
assert(snacks.styles.terminal.backdrop == false)
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
vim.cmd.tabnew()
vim.cmd "tabnew first-split.py"
vim.cmd "rightbelow vnew picker-source.lua"
local function rendered_tabs()
  return vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 150 }).str
end
local source_icon = require("nvim-web-devicons").get_icon("picker-source.lua", nil, { default = true })
local unnamed_icon = require("nvim-web-devicons").get_icon("[No Name]", nil, { default = true })
local function check_picker_tabs()
  local labels = rendered_tabs()
  assert(labels:find(source_icon .. " picker-source.lua", 1, true), "Picker changed the source split's file icon or filename: " .. labels)
  assert(labels:find(unnamed_icon .. " [No Name]", 1, true), "Picker changed the genuinely unnamed tab: " .. labels)
end
check_picker_tabs()
-- In headless Neovim 0.12, Snacks' partial screen redraw can crash when a
-- tab row is visible. Evaluate the real tabline above and inside the picker.
local showtabline = vim.o.showtabline
if #vim.api.nvim_list_uis() == 0 then
  vim.o.showtabline = 0
end
for _, columns in ipairs { 100, 160 } do
  vim.o.columns = columns
  local editor = vim.api.nvim_get_current_win()
  local picker = Snacks.picker { title = "Files", items = { { text = "init.lua", file = root .. "/init.lua" } }, format = "text", preview = "file" }
  local function preview_has_title()
    if not picker.preview.win:valid() then
      return false
    end
    local config = vim.api.nvim_win_get_config(picker.preview.win.win)
    return config.title and vim.inspect(config.title):find("init.lua", 1, true)
  end
  assert(vim.wait(1000, preview_has_title), "Preview filename missing at width " .. columns)
  check_picker_tabs()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      assert(vim.wo[win].winblend == 0, "Nested picker floats must not composite their own transparency")
    end
  end
  picker:close()
  assert(vim.api.nvim_get_current_win() == editor, "Closing picker must return to its originating split")
end
vim.o.showtabline = showtabline

vim.g.lunavim_ui_style = "glass"
vim.g.lunavim_reduced_motion = true
require("lunavim.config.neovide").setup()
assert(vim.g.neovide_opacity == 0.96 and vim.g.neovide_window_blurred)
assert(not vim.g.neovide_cursor_animate_command_line and vim.g.neovide_position_animation_length == 0)
assert(not vim.g.neovide_cursor_animate_in_insert_mode, "Reduced motion must also disable typing animations")
assert(vim.g.neovide_cursor_animation_length == 0 and vim.g.neovide_scroll_animation_length == 0)
assert(vim.g.neovide_cursor_short_animation_length == 0 and vim.g.neovide_cursor_trail_size == 0 and vim.g.neovide_cursor_vfx_mode == "")
vim.g.lunavim_ui_style = "solid"
require("lunavim.config.neovide").setup()
assert(vim.g.neovide_opacity == 1 and vim.g.neovide_normal_opacity == 1)
assert(not vim.g.neovide_window_blurred and not vim.g.neovide_floating_shadow)
local solid = dofile(root .. "/lua/lunavim/ui_specs/snacks.lua")[1].opts
assert(solid.styles.picker.wo.winblend == 0 and not solid.indent.animate.enabled)

vim.g.neovide = false
vim.g.lunavim_ui_style = nil
vim.g.lunavim_reduced_motion = false
local terminal = profile.get()
assert(not terminal.glass and not terminal.transparent and terminal.float_blend == 0, "Both frontends should default to solid surfaces")
load_theme()
for group, expected in pairs(shared) do
  assert(vim.deep_equal(highlight(group), expected), group .. " differs between the two frontends")
end
local tui_noice = dofile(root .. "/lua/lunavim/ui_specs/notifications.lua")[1].opts
assert(vim.deep_equal(tui_noice.views, notifications.views) and vim.deep_equal(tui_noice.presets, notifications.presets))
local tui_snacks = dofile(root .. "/lua/lunavim/ui_specs/snacks.lua")[1].opts
assert(vim.deep_equal(tui_snacks.indent, snacks.indent))
vim.g.lunavim_ui_style = "glass"
assert(profile.get().transparent)
load_theme()
assert(
  not highlight("Normal").bg and not highlight("NormalNC").bg and highlight("NormalFloat").bg == shared.NormalFloat.bg,
  "Glass should expose the terminal behind editing windows"
)
print "PASS: shared UI palette, glass opt-in, native shortcuts and responsive picker"
