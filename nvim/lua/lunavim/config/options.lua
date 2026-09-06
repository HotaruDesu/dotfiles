-- Set <space> as the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Number of spaes that a <Tab> counts
vim.opt.tabstop = 2
-- Number of spaces to use for each step of indent
vim.opt.shiftwidth = 2
-- Use a approriate number of spaces to insert a <Tab>
vim.opt.expandtab = true
-- Copy indent from current line when starting a new line
vim.opt.autoindent = true

-- Make line numbers default
vim.opt.number = true
-- Make line relative number default
vim.opt.relativenumber = true

-- Wrap line
vim.opt.wrap = true

-- Enable mouse mode
vim.opt.mouse = "a"
-- Enable mouse movement event
-- vim.opt.mousemoveevent = true

-- We don't need to show the current mode, since it's already in the status line
vim.opt.showmode = false

-- Stack layout for tags
-- vim.opt.jumpoptions = "stack"

-- Sync clipboard between OS and Neovim
-- We need invoke vim.schedule, since we don't hope this behavior breaks something else that Nvim is doing
vim.schedule(function()
  vim.opt.clipboard = "unnamedplus"
end)

-- Enable break indent
vim.opt.breakindent = true

-- Enable undo history
vim.opt.undofile = true

-- Case-insensitive earching unless \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Always enable sign column
vim.opt.signcolumn = "yes:2"

-- Decrease time for swap file saving
vim.opt.updatetime = 250

-- Decrease mapped sequence wait time
vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 0

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- show the effects of substitutions
vim.opt.inccommand = "split"

-- Show which line the cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- Raise a dialog asking if we wish to save the current files
vim.opt.confirm = true

-- Turm on termguicolors for tokyonight colorscheme to work. must have to use true color terminal
vim.opt.termguicolors = true
vim.opt.winblend = 0
vim.opt.pumblend = 0
-- Background can be "light" or "dark"
vim.opt.background = "dark"
-- neovide
if vim.g.neovide then
  -- Keep TokyoNight colors exact instead of compositing transparent multigrids
  -- with the native window background.
  vim.g.neovide_theme = "dark"
  vim.g.neovide_opacity = 1.0
  vim.g.neovide_normal_opacity = 1.0

  -- Give the editor a little breathing room without wasting screen space.
  vim.g.neovide_padding_top = 6
  vim.g.neovide_padding_bottom = 6
  vim.g.neovide_padding_left = 6
  vim.g.neovide_padding_right = 6

  -- Keep window and scrolling motion responsive.
  vim.g.neovide_position_animation_length = 0.1
  vim.g.neovide_scroll_animation_length = 0.18
  vim.g.neovide_scroll_animation_far_lines = 1

  -- Preserve Neovide's fluid cursor motion and add a restrained particle trail.
  vim.g.neovide_cursor_animation_length = 0.15
  vim.g.neovide_cursor_short_animation_length = 0.05
  vim.g.neovide_cursor_trail_size = 1.2
  vim.g.neovide_cursor_animate_in_insert_mode = true
  vim.g.neovide_cursor_animate_command_line = true
  vim.g.neovide_cursor_antialiasing = true
  vim.g.neovide_cursor_smooth_blink = true

  vim.g.neovide_cursor_vfx_mode = "pixiedust"
  vim.g.neovide_cursor_vfx_particle_lifetime = 0.35
  vim.g.neovide_cursor_vfx_particle_density = 0.35
  vim.g.neovide_cursor_vfx_particle_speed = 8.0
  vim.g.neovide_cursor_vfx_particle_phase = 1.2
  vim.g.neovide_cursor_vfx_particle_curl = 0.8

  -- vim.g.neovide_cursor_vfx_mode = { "pixiedust", "railgun" }
  -- vim.g.neovide_cursor_vfx_particle_lifetime = 0.5
  -- vim.g.neovide_cursor_vfx_particle_density = 0.6
  -- vim.g.neovide_cursor_vfx_particle_speed = 10.0
  -- vim.g.neovide_cursor_vfx_particle_phase = 1.2
  -- vim.g.neovide_cursor_vfx_particle_curl = 0.8

  vim.g.neovide_progress_bar_enabled = false
  vim.g.neovide_hide_mouse_when_typing = true
  vim.g.neovide_remember_window_size = true
  vim.g.neovide_refresh_rate_idle = 5
  vim.g.neovide_confirm_quit = true

  vim.g.neovide_floating_blur_amount_x = 0.0
  vim.g.neovide_floating_blur_amount_y = 0.0
  vim.g.neovide_floating_shadow = false

  vim.g.neovide_input_macos_option_is_meta = true
  vim.g.neovide_input_macos_option_key_is_meta = "both"
  vim.o.guifont = "Maple Mono NF CN:12"
  vim.opt.linespace = 1
  vim.g.neovide_scale_factor = 1.0

  local default_scale = 1.0
  local change_scale_factor = function(factor)
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
    vim.g.neovide_scale_factor = default_scale
  end, { desc = "Reset Neovide scale" })
  vim.keymap.set({ "n", "i", "v" }, "<D-s>", "<Cmd>silent update<CR>", { desc = "Save file" })
  vim.keymap.set("n", "<F11>", function()
    vim.g.neovide_fullscreen = not vim.g.neovide_fullscreen
  end, { desc = "Toggle Neovide fullscreen" })
end
