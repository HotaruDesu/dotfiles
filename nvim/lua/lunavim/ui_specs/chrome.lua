local function tab_highlights()
  local highlights = {}
  for _, group in ipairs {
    "background",
    "fill",
    "close_button",
    "close_button_selected",
    "close_button_visible",
    "duplicate",
    "duplicate_selected",
    "duplicate_visible",
    "error",
    "error_selected",
    "error_visible",
    "hint",
    "hint_selected",
    "hint_visible",
    "indicator_selected",
    "indicator_visible",
    "info",
    "info_selected",
    "info_visible",
    "modified",
    "modified_selected",
    "modified_visible",
    "numbers",
    "numbers_selected",
    "numbers_visible",
    "offset_separator",
    "pick",
    "pick_selected",
    "pick_visible",
    "separator",
    "separator_selected",
    "separator_visible",
    "tab",
    "tab_close",
    "tab_separator",
    "tab_separator_selected",
    "trunc_marker",
    "warning",
    "warning_selected",
    "warning_visible",
  } do
    highlights[group] = { bg = { highlight = "LunaVimTab", attribute = "bg" } }
  end
  highlights.tab = {
    fg = { highlight = "LunaVimTab", attribute = "fg" },
    bg = { highlight = "LunaVimTab", attribute = "bg" },
  }
  highlights.tab_selected = {
    fg = { highlight = "LunaVimTabSelected", attribute = "fg" },
    bg = { highlight = "LunaVimTabSelected", attribute = "bg" },
    bold = true,
  }
  return highlights
end

return {
  -- Status line
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        theme = "tokyonight",
        globalstatus = true,
        component_separators = { left = "│", right = "│" },
        section_separators = { left = "", right = "" },
        disabled_filetypes = { statusline = { "dashboard", "alpha", "starter" } },
      },
      sections = {
        lualine_b = { { "branch", icon = LunaVim.icons.git.Branch }, { "diff", symbols = LunaVim.icons.git } },
        lualine_c = {
          { "filename", path = 1, shorting_target = 60 },
          { "diagnostics", symbols = LunaVim.icons.diagnostics },
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
          local icon = ({ error = icons.Error, warning = icons.Warn, info = icons.Info, hint = icons.Hint })[level] or icons.Info
          return " " .. icon .. count
        end,
      },
      highlights = tab_highlights(),
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
          local group = not props.focused and "LunaVimInclineFileInactive" or modified and "LunaVimInclineFileModified" or "LunaVimInclineFile"

          return {
            {
              { ft_icon and (" " .. ft_icon .. " ") or " ", guifg = props.focused and ft_color or nil },
              filename .. " ",
              group = group,
            },
          }
        end,
      }
    end,
  },
}
