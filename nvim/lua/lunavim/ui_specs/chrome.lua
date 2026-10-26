return {
  -- statue line
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        theme = "tokyonight",
        globalstatus = true,
        component_separator = "|",
        section_separators = { left = LunaVim.icons.ui.BoldDividerRight, right = LunaVim.icons.ui.BoldDividerLeft },
        disabled_filetypes = { statusline = { "dashboard", "alpha", "starter" } },
      },
      sections = {
        lualine_b = { { "branch", icon = LunaVim.icons.git.Branch }, { "diff", symbols = LunaVim.icons.git } },
        lualine_c = {
          { "filename", path = 1, shorting_target = 60 },
          { "diagnostics", symbols = LunaVim.icons.diagnostics }
        },
        lualine_x = { "encoding", "fileformat", "filetype" },
      },
    },
  },
  -- tab line
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        mode = "tabs",
        separator_style = { "", "" },
        indicator = {
          icon = "",
          style = "none",
        },
        diagnostics = "nvim_lsp",
        show_buffer_close_icon = false,
        show_close_icon = false,
        themable = true,
        offsets = {
          { filetype = "neo-tree", text = "File Explorer", text_align = "left", separator = true },
        },
        diagnostics_indicator = function(count, level)
          local icons = LunaVim.icons.diagnostics
          local icon = level:match "error" and icons.Error or icons.Warn
          return " " .. icon .. count
        end,
      },
      highlights = {
        background = { bg = "none" },
        fill = { bg = "none" },
        buffer_selected = {
          bg = "none",
          fg = { highlight = "LunaVimBufferSelected", attribute = "fg" },
        },
        buffer_visible = {
          bg = "none",
          fg = { highlight = "LunaVimBufferVisible", attribute = "fg" },
        },
        close_button = { bg = "none" },
        close_button_selected = { bg = "none" },
        close_button_visible = { bg = "none" },
        duplicate = { bg = "none" },
        duplicate_selected = { bg = "none" },
        duplicate_visible = { bg = "none" },
        error = { bg = "none" },
        error_selected = { bg = "none" },
        error_visible = { bg = "none" },
        hint = { bg = "none" },
        hint_selected = { bg = "none" },
        hint_visible = { bg = "none" },
        indicator_selected = { bg = "none" },
        indicator_visible = { bg = "none" },
        info = { bg = "none" },
        info_selected = { bg = "none" },
        info_visible = { bg = "none" },
        modified = { bg = "none" },
        modified_selected = { bg = "none" },
        modified_visible = { bg = "none" },
        numbers = { bg = "none" },
        numbers_selected = { bg = "none" },
        numbers_visible = { bg = "none" },
        offset_separator = { bg = "none" },
        pick = { bg = "none" },
        pick_selected = { bg = "none" },
        pick_visible = { bg = "none" },
        separator = { bg = "none" },
        separator_selected = { bg = "none" },
        separator_visible = { bg = "none" },
        tab = { bg = "none" },
        tab_close = { bg = "none" },
        tab_selected = { bg = "none" },
        tab_separator = { bg = "none" },
        tab_separator_selected = { bg = "none" },
        trunc_marker = { bg = "none" },
        warning = { bg = "none" },
        warning_selected = { bg = "none" },
        warning_visible = { bg = "none" },
      },
    },
  },
  -- icons
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
  },
  -- floating statusline
  {
    "b0o/incline.nvim",
    event = "BufReadPre",
    priority = 1200,
    config = function()
      local devicons = require "nvim-web-devicons"
      require("incline").setup {
        window = {
          padding = 0,
          margin = { horizontal = 0, vertical = 0 },
          placement = { vertical = "top", horizontal = "right" },
          zindex = 50,
        },
        render = function(props)
          local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
          if filename == "" then
            filename = "[No Name]"
          end
          local ft_icon, ft_color = devicons.get_icon_color(filename)
          local modified = vim.bo[props.buf].modified

          return {
            { " ", guibg = "NONE" },
            {
              { ft_icon and (" " .. ft_icon .. " ") or "", guifg = ft_color, guibg = "NONE" },
              { filename .. " ", group = modified and "LunaVimInclineFileModified" or "LunaVimInclineFile" },
            },
            { " ", guibg = "NONE" },
          }
        end,
      }
    end,
  },
}
