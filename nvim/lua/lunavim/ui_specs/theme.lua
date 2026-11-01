local theme_style = "night"
local ui = require("lunavim.config.ui").get()

return {
  -- color scheme
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = theme_style,
      transparent = ui.transparent,
      styles = {
        sidebars = ui.transparent and "transparent" or "normal",
        floats = "normal",
      },
      on_colors = function(c)
        local util = require "tokyonight.util"
        c.luna = require("lunavim.config.ui").palette(c)
        local surface = c.luna
        util.bg = surface.background
        c.bg = surface.background
        c.bg_dark = surface.sidebar
        c.bg_dark1 = surface.sidebar
        c.bg_popup = surface.floating
        c.bg_statusline = surface.sidebar
        c.bg_float = surface.floating
        c.bg_sidebar = ui.transparent and c.none or surface.sidebar
        c.black = surface.sidebar
        c.border = surface.border
        c.border_highlight = surface.accent
        c.bg_visual = surface.selected
        c.terminal.black = surface.background
      end,
      on_highlights = function(hl, c)
        local surface = c.luna
        -- Basic UI
        hl.FloatBorder = { fg = surface.border, bg = surface.floating }
        hl.FloatTitle = { fg = c.blue, bg = surface.floating, bold = true }
        hl.NormalFloat = { fg = c.fg, bg = surface.floating }
        hl.WinSeparator = { fg = surface.border, bg = c.bg }
        hl.CursorLine = { bg = c.bg_highlight }
        hl.Pmenu = { fg = c.fg, bg = surface.floating }
        hl.PmenuSel = { fg = c.fg, bg = surface.selected, bold = true }

        -- Snacks window chrome: one surface, one accent, semantic colors stay intact.
        local snacks_surfaces = {
          "SnacksNormal",
          "SnacksInputNormal",
          "SnacksPicker",
          "SnacksPickerBox",
          "SnacksPickerInput",
          "SnacksPickerList",
          "SnacksPickerPreview",
          "SnacksNotifierHistory",
          "SnacksNotifierMinimal",
        }
        for _, group in ipairs(snacks_surfaces) do
          hl[group] = { fg = c.fg, bg = surface.floating }
        end
        hl.SnacksTerminal = { fg = c.fg, bg = c.bg }
        hl.SnacksNormalNC = { fg = c.fg_dark, bg = surface.floating }

        local snacks_borders = {
          "SnacksInputBorder",
          "SnacksPickerBorder",
          "SnacksPickerBoxBorder",
          "SnacksPickerInputBorder",
          "SnacksPickerListBorder",
          "SnacksPickerPreviewBorder",
        }
        for _, group in ipairs(snacks_borders) do
          hl[group] = { fg = surface.border, bg = surface.floating }
        end

        local snacks_titles = {
          "SnacksInputTitle",
          "SnacksPickerTitle",
          "SnacksPickerBoxTitle",
          "SnacksPickerInputTitle",
          "SnacksPickerListTitle",
          "SnacksPickerPreviewTitle",
        }
        for _, group in ipairs(snacks_titles) do
          hl[group] = { fg = c.blue, bg = surface.floating, bold = true }
        end

        local snacks_cursorlines = {
          "SnacksPickerCursorLine",
          "SnacksPickerInputCursorLine",
          "SnacksPickerListCursorLine",
          "SnacksPickerPreviewCursorLine",
        }
        for _, group in ipairs(snacks_cursorlines) do
          hl[group] = { fg = c.fg, bg = surface.selected }
        end

        hl.SnacksInputIcon = { fg = c.blue }
        hl.SnacksPickerFooter = { fg = c.comment, bg = surface.floating }
        hl.SnacksPickerPrompt = { fg = c.blue }
        hl.SnacksPickerInputSearch = { fg = c.blue, bold = true }
        hl.SnacksPickerMatch = { fg = c.blue, bold = true }
        hl.SnacksPickerSelected = { fg = c.blue, bold = true }
        hl.SnacksPickerSearch = { fg = c.fg, bg = c.blue0 }
        hl.SnacksPickerSpinner = { fg = c.blue }
        hl.SnacksPickerTotals = { fg = c.comment }
        hl.SnacksPickerToggle = { fg = c.blue, bg = surface.selected, bold = true }

        -- Dashboard uses the same accent family without flattening semantic colors.
        hl.SnacksDashboardDesc = { fg = c.fg_dark }
        hl.SnacksDashboardFooter = { fg = c.comment }
        hl.SnacksDashboardHeader = { fg = c.blue }
        hl.SnacksDashboardIcon = { fg = c.blue1 }
        hl.SnacksDashboardKey = { fg = c.blue }
        hl.SnacksDashboardSpecial = { fg = c.purple }
        hl.SnacksDashboardDir = { fg = c.comment }
        hl.SnacksIndentScope = { fg = c.blue, nocombine = true }
        hl.SnacksZenIcon = { fg = c.blue }

        -- Theme-aware colors consumed by plugins configured outside this hook.
        hl.LunaVimBufferSelected = { fg = c.blue }
        hl.LunaVimBufferVisible = { fg = c.fg_dark }
        hl.LunaVimTabSelected = { fg = c.blue, bg = surface.selected, bold = true }
        hl.LunaVimTab = { fg = c.fg_dark, bg = surface.sidebar }
        hl.LunaVimInclineFile = { fg = c.fg, bg = surface.floating, bold = true }
        hl.LunaVimInclineFileInactive = { fg = c.comment, bg = surface.sidebar }
        hl.LunaVimInclineFileModified = { fg = c.blue, bg = surface.floating, bold = true, italic = true }

        local notifier_accents = {
          Debug = c.comment,
          Error = c.error,
          Info = c.info,
          Trace = c.purple,
          Warn = c.warning,
        }
        for level, accent in pairs(notifier_accents) do
          hl["SnacksNotifier" .. level] = { fg = c.fg, bg = surface.floating }
          hl["SnacksNotifierBorder" .. level] = { fg = accent, bg = surface.floating }
        end

        -- Completion menu
        hl.BlinkCmpMenu = { fg = c.fg, bg = surface.floating }
        hl.BlinkCmpMenuBorder = { fg = surface.border, bg = surface.floating }
        hl.BlinkCmpMenuSelection = { bg = surface.selected, bold = true }
        hl.BlinkCmpSource = { fg = c.comment }
        hl.BlinkCmpLabelDescription = { fg = c.comment }
        hl.BlinkCmpLabelDetail = { fg = c.dark5 }
        hl.BlinkCmpDoc = { fg = c.fg, bg = surface.floating }
        hl.BlinkCmpDocBorder = { fg = surface.border, bg = surface.floating }
        hl.BlinkCmpDocSeparator = { fg = c.dark5, bg = surface.floating }
        hl.BlinkCmpSignatureHelp = { fg = c.fg, bg = surface.floating }
        hl.BlinkCmpSignatureHelpBorder = { fg = surface.border, bg = surface.floating }
        hl.NoiceCmdlinePopupBorder = { fg = surface.border, bg = surface.floating }
        hl.NoiceCmdlinePopupTitle = { fg = c.blue, bg = surface.floating, bold = true }
        hl.NoiceCmdlinePopup = { fg = c.fg, bg = surface.floating }

        -- Treesitter context
        hl.TreesitterContext = { bg = surface.sidebar }
        hl.TreesitterContextBottom = { underline = true, sp = surface.border }
        hl.TreesitterContextLineNumber = { bg = surface.sidebar, fg = c.comment }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd [[colorscheme tokyonight]]
    end,
  },
}
