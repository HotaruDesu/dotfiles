local M = {}

function M.get()
  local neovide = vim.g.neovide == true
  local glass = vim.g.lunavim_ui_style == "glass"
  local reduced_motion = vim.g.lunavim_reduced_motion == true
  return {
    neovide = neovide,
    glass = glass,
    reduced_motion = reduced_motion,
    transparent = glass and not neovide,
    -- Composite glass once at the native window. Nested translucent floats
    -- otherwise tint each picker pane against a different underlying grid.
    float_blend = 0,
    opacity = glass and 0.96 or 1,
    window_animation_ms = reduced_motion and 0 or 120,
    cursor_animation_ms = reduced_motion and 0 or 140,
    scroll_ms = reduced_motion and 0 or 140,
  }
end

function M.palette(colors)
  local blend = require("tokyonight.util").blend
  local background = colors.bg
  local sidebar = colors.bg_dark
  local floating = blend(colors.fg_dark, 0.05, background)
  return {
    background = background,
    sidebar = sidebar,
    inactive = blend(sidebar, 0.55, background),
    floating = floating,
    border = blend(colors.fg_dark, 0.23, floating),
    panel_border = "#4c5368",
    picker_input = blend(colors.fg_dark, 0.05, floating),
    picker_preview = blend(floating, 0.5, background),
    cmdline_border = "#606a84",
    tab_separator = "#393d4f",
    tab_selected = "#2c3448",
    tab_selected_fg = "#bacbf2",
    tab_indicator = "#82aaff",
    selected = blend(colors.blue, 0.15, background),
    cursorline = blend(colors.blue, 0.05, background),
    accent = colors.blue,
  }
end

function M.picker_preset()
  if vim.o.columns >= 140 then
    return "luna_horizontal"
  end
  return "luna_vertical"
end

return M
