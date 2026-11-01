local M = {}

function M.setup()
  if not vim.g.neovide then
    return
  end

  local ui = require("lunavim.config.ui").get()
  vim.g.neovide_theme = "dark"
  vim.g.neovide_opacity = ui.opacity
  -- Use the native window opacity consistently for every background color.
  vim.g.neovide_normal_opacity = 1.0
  vim.g.neovide_window_blurred = ui.glass
  for _, edge in ipairs { "top", "bottom", "left", "right" } do
    vim.g["neovide_padding_" .. edge] = 6
  end

  vim.g.neovide_position_animation_length = ui.animation_ms / 1000
  vim.g.neovide_scroll_animation_length = ui.scroll_ms / 1000
  vim.g.neovide_scroll_animation_far_lines = 1
  vim.g.neovide_cursor_animation_length = ui.animation_ms / 1000
  vim.g.neovide_cursor_short_animation_length = ui.reduced_motion and 0 or 0.05
  vim.g.neovide_cursor_trail_size = ui.reduced_motion and 0 or 0.6
  vim.g.neovide_cursor_animate_in_insert_mode = not ui.reduced_motion
  vim.g.neovide_cursor_animate_command_line = not ui.reduced_motion
  vim.g.neovide_cursor_antialiasing = true
  vim.g.neovide_cursor_smooth_blink = not ui.reduced_motion
  vim.g.neovide_cursor_vfx_mode = ui.reduced_motion and "" or "pixiedust"
  vim.g.neovide_cursor_vfx_particle_lifetime = 0.2
  vim.g.neovide_cursor_vfx_particle_density = 0.15
  vim.g.neovide_cursor_vfx_particle_speed = 5.0
  vim.g.neovide_cursor_vfx_particle_phase = 1.2
  vim.g.neovide_cursor_vfx_particle_curl = 0.8

  -- A picker is several adjacent floats; per-grid blur/shadows draw seams
  -- through its interior. Native window blur still provides the glass effect.
  vim.g.neovide_floating_blur_amount_x = 0
  vim.g.neovide_floating_blur_amount_y = 0
  vim.g.neovide_floating_shadow = false
  vim.g.neovide_floating_z_height = 3
  vim.g.neovide_light_angle_degrees = 45
  vim.g.neovide_light_radius = 4
  vim.g.neovide_floating_corner_radius = 0
  vim.g.neovide_progress_bar_enabled = false
  vim.g.neovide_hide_mouse_when_typing = true
  vim.g.neovide_remember_window_size = true
  vim.g.neovide_refresh_rate_idle = 5
  vim.g.neovide_confirm_quit = true
  vim.g.neovide_input_macos_option_is_meta = true
  vim.g.neovide_input_macos_option_key_is_meta = "both"
  vim.o.guifont = "Maple Mono NF CN:h12"
  vim.opt.linespace = 1
  vim.g.neovide_scale_factor = 1.0

  -- Preserve the existing native-app shortcuts while keeping rendering options
  -- separate from the editor's general options.
  local function change_scale_factor(factor)
    vim.g.neovide_scale_factor = math.max(0.5, math.min(2.0, vim.g.neovide_scale_factor * factor))
  end
  vim.keymap.set({ "n", "i", "v" }, "<D-->", function()
    change_scale_factor(1 / 1.05)
  end, { desc = "Decrease Neovide scale" })
  for _, lhs in ipairs { "<D-=>", "<D-+>" } do
    vim.keymap.set({ "n", "i", "v" }, lhs, function()
      change_scale_factor(1.05)
    end, { desc = "Increase Neovide scale" })
  end
  vim.keymap.set({ "n", "i", "v" }, "<D-0>", function()
    vim.g.neovide_scale_factor = 1.0
  end, { desc = "Reset Neovide scale" })
  vim.keymap.set({ "n", "i", "v" }, "<D-s>", "<Cmd>silent update<CR>", { desc = "Save file" })
  vim.keymap.set("n", "<F11>", function()
    vim.g.neovide_fullscreen = not vim.g.neovide_fullscreen
  end, { desc = "Toggle Neovide fullscreen" })
end

return M
