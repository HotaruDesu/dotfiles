local M = {}

-- Set these globals before loading LunaVim to choose an opaque UI or to turn
-- off decorative movement. Terminal blur belongs to the terminal emulator.
function M.get()
  local glass = vim.g.lunavim_ui_style ~= "solid"
  local neovide = vim.g.neovide == true
  local reduced_motion = vim.g.lunavim_reduced_motion == true
  return {
    glass = glass,
    reduced_motion = reduced_motion,
    transparent = glass and not neovide,
    -- Composite glass once at the native window. Nested translucent floats
    -- otherwise tint each picker pane against a different underlying grid.
    float_blend = 0,
    opacity = glass and 0.96 or 1,
    animation_ms = reduced_motion and 0 or 100,
    scroll_ms = reduced_motion and 0 or 140,
  }
end

function M.palette(colors)
  local blend = require("tokyonight.util").blend
  local background = blend(colors.bg, 0.94, "#080b12")
  return {
    background = background,
    sidebar = background,
    floating = background,
    border = blend(colors.blue, 0.14, background),
    selected = blend(colors.blue, 0.16, background),
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
