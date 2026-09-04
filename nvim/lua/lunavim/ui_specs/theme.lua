local theme_style = "night"

return {
  -- color scheme
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = theme_style,
      -- Terminal Neovim can inherit the terminal emulator background. Neovide
      -- needs an opaque Normal grid so its multigrid surfaces keep exact colors.
      transparent = not vim.g.neovide,
      styles = {
        sidebars = vim.g.neovide and "normal" or "transparent",
        floats = "normal",
      },
      on_colors = function(c)
        local util = require "tokyonight.util"
        local surface = util.blend(c.bg, 0.50, "#000000")

        -- Keep every UI surface on the same, slightly deeper shade. Since the
        -- shade is derived from c.bg, changing theme_style needs no color edits.
        util.bg = surface
        c.bg = surface
        c.bg_dark = surface
        c.bg_dark1 = surface
        c.bg_popup = surface
        c.bg_statusline = surface
        c.bg_float = surface
        c.bg_sidebar = vim.g.neovide and surface or c.none
        c.black = util.blend(surface, 0.8, "#000000")
        c.border = c.black
        c.border_highlight = util.blend(c.blue1, 0.8, surface)
        c.bg_visual = util.blend(c.blue0, 0.4, surface)
        c.terminal.black = surface
      end,
      on_highlights = function(hl, c)
        -- Basic UI
        hl.FloatBorder = { fg = c.blue, bg = "NONE" }
        hl.FloatTitle = { fg = c.blue, bg = c.bg, bold = true }
        hl.NormalFloat = { fg = c.fg, bg = c.bg }
        hl.CursorLine = { bg = c.bg_highlight }
        hl.Pmenu = { fg = c.fg, bg = c.bg }
        hl.PmenuSel = { fg = c.fg, bg = c.bg_highlight, bold = true }

        -- Snacks window chrome: one surface, one accent, semantic colors stay intact.
        local snacks_surfaces = {
          "SnacksNormal",
          "SnacksTerminal",
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
          hl[group] = { fg = c.fg, bg = c.bg }
        end
        hl.SnacksNormalNC = { fg = c.fg_dark, bg = c.bg }

        local snacks_borders = {
          "SnacksInputBorder",
          "SnacksPickerBorder",
          "SnacksPickerBoxBorder",
          "SnacksPickerInputBorder",
          "SnacksPickerListBorder",
          "SnacksPickerPreviewBorder",
        }
        for _, group in ipairs(snacks_borders) do
          hl[group] = { fg = c.blue, bg = "NONE" }
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
          hl[group] = { fg = c.blue, bg = c.bg, bold = true }
        end

        local snacks_cursorlines = {
          "SnacksPickerCursorLine",
          "SnacksPickerInputCursorLine",
          "SnacksPickerListCursorLine",
          "SnacksPickerPreviewCursorLine",
        }
        for _, group in ipairs(snacks_cursorlines) do
          hl[group] = { fg = c.fg, bg = c.bg_highlight }
        end

        hl.SnacksInputIcon = { fg = c.blue }
        hl.SnacksPickerFooter = { fg = c.comment, bg = c.bg }
        hl.SnacksPickerPrompt = { fg = c.blue }
        hl.SnacksPickerInputSearch = { fg = c.blue, bold = true }
        hl.SnacksPickerMatch = { fg = c.blue, bold = true }
        hl.SnacksPickerSelected = { fg = c.blue, bold = true }
        hl.SnacksPickerSearch = { fg = c.fg, bg = c.blue0 }
        hl.SnacksPickerSpinner = { fg = c.blue }
        hl.SnacksPickerTotals = { fg = c.comment }
        hl.SnacksPickerToggle = { fg = c.blue, bg = c.bg_highlight, bold = true }

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
        hl.LunaVimInclineFile = { fg = c.blue, bold = true }
        hl.LunaVimInclineFileModified = { fg = c.blue, bold = true, italic = true }

        local notifier_accents = {
          Debug = c.comment,
          Error = c.error,
          Info = c.info,
          Trace = c.purple,
          Warn = c.warning,
        }
        for level, accent in pairs(notifier_accents) do
          hl["SnacksNotifier" .. level] = { fg = c.fg, bg = c.bg }
          hl["SnacksNotifierBorder" .. level] = { fg = accent, bg = "NONE" }
        end

        -- Completion menu
        hl.BlinkCmpMenu = { fg = c.fg, bg = c.bg }
        hl.BlinkCmpMenuBorder = { fg = c.blue, bg = "NONE" }
        hl.BlinkCmpMenuSelection = { bg = c.bg_highlight, bold = true }
        hl.BlinkCmpSource = { fg = c.comment }
        hl.BlinkCmpLabelDescription = { fg = c.comment }
        hl.BlinkCmpLabelDetail = { fg = c.dark5 }
        hl.BlinkCmpDoc = { fg = c.fg, bg = c.bg }
        hl.BlinkCmpDocBorder = { fg = c.blue, bg = "NONE" }
        hl.BlinkCmpDocSeparator = { fg = c.dark5, bg = c.bg }
        hl.BlinkCmpSignatureHelp = { fg = c.fg, bg = c.bg }
        hl.BlinkCmpSignatureHelpBorder = { fg = c.blue, bg = "NONE" }

        -- Bufferline
        -- hl.BufferLineFill = { bg = "NONE" }
        -- hl.BufferLineBackground = { bg = "NONE" }
        --
        -- hl.BufferLineTabSeparator = { fg = c.bg, bg = "NONE" }
        -- hl.BufferLineTabSeparatorVisible = { fg = c.bg, bg = "NONE" }
        -- hl.BufferLineTabSeparatorSelected = { fg = c.bg, bg = "NONE" }
        --
        -- hl.BufferLineBufferSelected = { bg = "NONE", fg = c.fg, bold = true }
        -- hl.BufferLineTabSelected = { bg = "NONE", fg = c.fg, bold = true }

        -- Treesitter context
        hl.TreesitterContext = { bg = "NONE", fg = c.blue1 }
        hl.TreesitterContextBottom = { underline = true, sp = c.blue5 }
        hl.TreesitterContextLineNumber = { bg = "NONE", fg = c.comment }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd [[colorscheme tokyonight]]
    end,
  },
}
