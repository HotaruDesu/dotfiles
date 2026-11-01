local ui_config = require "lunavim.config.ui"
local ui = ui_config.get()

return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      dashboard = { enabled = true },
      indent = {
        enabled = true,
        animate = { enabled = not ui.reduced_motion, duration = { step = 10, total = ui.animation_ms } },
      },
      notifier = { enabled = true, timeout = 5000 },
      input = { enabled = true },
      picker = {
        jump = {
          reuse_win = false,
        },
        enabled = true,
        show_delay = 0,
        sources = require("lunavim.search").sources(),
        layout = {
          preset = ui_config.picker_preset,
        },
        layouts = {
          luna_vertical = {
            layout = {
              backdrop = false,
              width = 0.92,
              height = 0.88,
              box = "vertical",
              border = "rounded",
              title = "{title} {live} {flags}",
              title_pos = "center",
              { win = "input", height = 1, border = "bottom", title = "{icon} {title}", title_pos = "center" },
              { win = "list", border = "none" },
              { win = "preview", title = "{preview}", border = "top", height = 0.48 },
            },
          },
          luna_horizontal = {
            layout = {
              backdrop = false,
              width = 0.90,
              height = 0.86,
              box = "horizontal",
              border = "rounded",
              title = "{title} {live} {flags}",
              title_pos = "center",
              {
                box = "vertical",
                border = "right",
                { win = "input", height = 1, border = "bottom", title = "{icon} {title}", title_pos = "center" },
                { win = "list", border = "none" },
              },
              { win = "preview", title = "{preview}", width = 0.55 },
            },
          },
        },
        win = {
          input = {
            wo = { winblend = ui.float_blend },
            keys = {
              ["<Esc>"] = { "close", mode = { "n", "i" } },
              ["<C-j>"] = { "list_down", mode = { "i", "n" } },
              ["<C-k>"] = { "list_up", mode = { "i", "n" } },
              ["<C-d>"] = { "preview_scroll_down", mode = { "i", "n" } },
              ["<C-u>"] = { "preview_scroll_up", mode = { "i", "n" } },
              ["<C-p>"] = { "toggle_preview", mode = { "i", "n" } },
            },
          },
          list = { wo = { winblend = ui.float_blend } },
          preview = { wo = { winblend = ui.float_blend } },
        },
      },
      -- explorer = { enabled = true },
      terminal = {
        enabled = true,
        win = {
          bo = {
            filetype = "snacks_terminal",
          },
          wo = {
            winhighlight = table.concat({
              "Normal:SnacksTerminal",
              "NormalNC:SnacksTerminal",
              "WinBar:SnacksWinBar",
              "WinBarNC:SnacksWinBarNC",
              "FloatTitle:SnacksTitle",
              "FloatFooter:SnacksFooter",
              "WinSeparator:SnacksWinSeparator",
            }, ","),
          },
          stack = true,
          keys = {
            q = "hide",
            gf = function(self)
              local f = vim.fn.findfile(vim.fn.expand "<cfile>", "**")
              if f == "" then
                Snacks.notify.warn "No file under cursor"
              else
                self:hide()
                vim.schedule(function()
                  vim.cmd("edit " .. vim.fn.fnameescape(f))
                end)
              end
            end,
            term_normal = {
              "<esc>",
              function(self)
                self.esc_timer = self.esc_timer or vim.uv.new_timer()
                if self.esc_timer:is_active() then
                  self.esc_timer:stop()
                  vim.cmd "stopinsert"
                else
                  self.esc_timer:start(200, 0, function() end)
                  return "<esc>"
                end
              end,
              mode = "t",
              expr = true,
              desc = "Double escape to normal mode",
            },
          },
        },
      },
      words = { enabled = true },
      statuscolumn = { enabled = true },
      scroll = { enabled = false },
      scope = { enabled = true },
      styles = {
        notification = { border = "rounded", wo = { winblend = ui.float_blend, wrap = true } },
        picker = { border = "rounded", wo = { winblend = ui.float_blend } },
      },
    },
    keys = LunaVim.plugin_lazy "snacks.nvim",
    config = function(_, opts)
      require("snacks").setup(opts)
      require("lunavim.search").setup()
    end,
  },
}
