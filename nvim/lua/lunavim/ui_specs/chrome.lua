local active_marker, divider = "▎", "│"

local function statusline_theme()
  local c = require("tokyonight.colors").setup()
  local blend = require("tokyonight.util").blend
  local theme = { normal = { a = "LunaVimTabSelected", b = "LunaVimTab", c = "LunaVimTab", z = "LunaVimTab" } }
  for mode, accent in pairs { insert = c.green, visual = c.magenta, command = c.yellow, replace = c.red, terminal = c.cyan } do
    theme[mode] = {
      a = { fg = accent, bg = blend(accent, 0.24, c.bg_statusline), gui = "bold" },
      z = "LunaVimTab", -- lualine otherwise mirrors section A onto the right edge
    }
  end
  return theme
end

local function mode_marker_color()
  local suffix = require("lualine.highlight").get_mode_suffix()
  return suffix == "_normal" and "LunaVimTabIndicator" or "lualine_a" .. suffix
end

local function statusline_sections()
  local filename = {
    "filename",
    path = 1,
    shorting_target = 60,
    icon = { divider, color = "LunaVimTabSeparator" },
    padding = { right = 1 },
  }
  local diagnostics = { "diagnostics", symbols = LunaVim.icons.diagnostics }
  local branch = { "branch", icon = LunaVim.icons.git.Branch }
  local diff = { "diff", symbols = LunaVim.icons.git }
  local function show_file_format()
    return vim.o.columns >= 100 and vim.bo.buftype == ""
  end
  return {
    lualine_a = {
      {
        "mode",
        icon = { active_marker, color = mode_marker_color },
        padding = { right = 1 },
        fmt = function(mode)
          -- Leave room for O-PENDING so the divider stays put on mode changes.
          return ("%-9s"):format(mode)
        end,
      },
    },
    lualine_b = { filename },
    lualine_c = { branch, diff, diagnostics },
    lualine_x = {
      {
        "lsp_status",
        cond = function()
          return vim.o.columns >= 76
        end,
        symbols = { done = "" },
      },
      {
        "encoding",
        cond = show_file_format,
        fmt = function(encoding)
          return (encoding ~= "" and encoding or vim.o.encoding):upper()
        end,
      },
      { "fileformat", cond = show_file_format, symbols = { unix = "LF", dos = "CRLF", mac = "CR" } },
      "filetype",
    },
    lualine_y = {
      {
        function()
          return vim.bo.filetype ~= "" and divider or ""
        end,
        color = "LunaVimTabSeparator",
        padding = 0,
      },
      {
        "progress",
        fmt = vim.trim,
        padding = { left = 1, right = 0 },
        cond = function()
          return vim.o.columns >= 50
        end,
      },
    },
    lualine_z = { { "location", fmt = vim.trim, padding = { left = 1, right = 0 } } },
  }
end

local function tab_highlights()
  local highlights = {}
  local background = { highlight = "LunaVimTab", attribute = "bg" }
  local selected = { highlight = "LunaVimTabSelected", attribute = "bg" }
  for _, group in ipairs {
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
    "tab_close",
    "tab_separator",
    "tab_separator_selected",
    "trunc_marker",
    "warning",
    "warning_selected",
    "warning_visible",
  } do
    highlights[group] = { bg = group:match "_selected$" and selected or background }
  end
  highlights.tab = {
    fg = { highlight = "LunaVimTab", attribute = "fg" },
    bg = background,
  }
  highlights.tab_selected = {
    fg = { highlight = "LunaVimTabSelected", attribute = "fg" },
    bg = selected,
    bold = true,
  }
  -- In tabs mode the plugin still draws filenames with its buffer groups.
  highlights.background = highlights.tab
  highlights.buffer_visible = highlights.tab
  highlights.buffer_selected = vim.tbl_extend("force", highlights.tab_selected, { italic = false })
  highlights.separator.fg = { highlight = "LunaVimTabSeparator", attribute = "fg" }
  highlights.indicator_selected = {
    fg = { highlight = "LunaVimTabIndicator", attribute = "fg" },
    bg = selected,
    default = false, -- override TokyoNight's default BufferLineIndicatorSelected
  }
  for _, group in ipairs { "diagnostic", "error_diagnostic", "hint_diagnostic", "info_diagnostic", "warning_diagnostic" } do
    highlights[group] = { bg = background }
    highlights[group .. "_visible"] = { bg = background }
    highlights[group .. "_selected"] = { bg = selected }
  end
  return highlights
end

local function floating_tab_source(tab)
  local win = vim.api.nvim_tabpage_get_win(tab)
  if vim.api.nvim_win_get_config(win).relative == "" then
    return
  end
  local editor = vim.t[tab].lunavim_tab_editor
  if editor and vim.api.nvim_win_is_valid(editor) and vim.api.nvim_win_get_tabpage(editor) == tab then
    local path = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor))
    return path ~= "" and vim.fn.fnamemodify(path, ":t") or "[No Name]", vim.api.nvim_win_get_buf(win)
  end
end

local function tab_icon(item)
  -- Bufferline supplies no tab ID here. Keep the default for plain unnamed files.
  if item.path == "[No Name]" and item.filetype == "" and item.type == "" then
    return
  end
  local filename, popup = floating_tab_source(vim.api.nvim_get_current_tabpage())
  if popup and item.type == vim.bo[popup].buftype and item.filetype == vim.bo[popup].filetype then
    local path = vim.api.nvim_buf_get_name(popup)
    if item.path == (path ~= "" and path or "[No Name]") then
      return require("nvim-web-devicons").get_icon(filename, nil, { default = true })
    end
  end
end

return {
  -- Status line
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        theme = statusline_theme,
        globalstatus = true,
        ignore_focus = { "snacks_picker_input", "snacks_picker_list", "snacks_picker_preview" },
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        disabled_filetypes = { statusline = { "dashboard", "alpha", "starter", "snacks_dashboard" } },
      },
      sections = statusline_sections(),
    },
  },
  -- tab line
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    init = function()
      vim.api.nvim_create_autocmd("WinLeave", {
        group = vim.api.nvim_create_augroup("LunaVimTabline", { clear = true }),
        callback = function()
          if vim.api.nvim_win_get_config(0).relative == "" then
            vim.t.lunavim_tab_editor = vim.api.nvim_get_current_win()
          end
        end,
      })
    end,
    opts = {
      options = {
        mode = "tabs",
        name_formatter = function(tab)
          return floating_tab_source(tab.tabnr) or tab.name
        end,
        get_element_icon = tab_icon,
        always_show_bufferline = false,
        -- With native showtabline=1, background tab creation also reveals the strip.
        auto_toggle_bufferline = false,
        separator_style = { divider, divider },
        indicator = { icon = active_marker, style = "icon" },
        diagnostics = "nvim_lsp",
        show_buffer_close_icons = false,
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
        hide = { only_win = true },
        window = {
          padding = 0,
          margin = { horizontal = 1, vertical = 0 },
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
          local group = props.focused and "LunaVimInclineFile" or "LunaVimInclineFileInactive"

          return {
            {
              { ft_icon and (" " .. ft_icon .. " ") or " ", guifg = props.focused and ft_color or nil },
              filename .. " ",
              modified and { "● ", group = props.focused and "LunaVimInclineFileModified" or "LunaVimInclineModifiedInactive" } or "",
              group = group,
            },
          }
        end,
      }
    end,
  },
}
