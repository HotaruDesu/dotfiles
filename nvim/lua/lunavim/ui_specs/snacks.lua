local ui_config = require "lunavim.config.ui"
local ui = ui_config.get()
local picker_frame = { winhighlight = "FloatTitle:SnacksPickerBoxTitle" }

local function style_terminal(win)
  if win.opts.position == "float" then
    if win.opts.border == nil then
      win.opts.border = "rounded"
    end
    win.opts.wo.winhighlight = Snacks.util.winhl(win.opts.wo.winhighlight, {
      Normal = "LunaVimTerminalFloat",
      NormalNC = "LunaVimTerminalFloat",
      NormalFloat = "LunaVimTerminalFloat",
      FloatBorder = "LunaVimPanelBorder",
    })
  end
end

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
        scope = { only_current = true },
        animate = { enabled = false },
      },
      notifier = { enabled = true, timeout = 5000 },
      input = { enabled = true },
      picker = {
        jump = {
          reuse_win = false,
        },
        enabled = true,
        show_delay = 0,
        on_show = function(picker)
          require("lunavim.search.motion").attach(picker)
        end,
        on_close = function(picker)
          require("lunavim.search.motion").close(picker)
        end,
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
              title_pos = "left",
              wo = picker_frame,
              { win = "input", height = 1, border = "bottom", title_pos = "left" },
              { win = "list", border = "none" },
              { win = "preview", title = "{preview}", title_pos = "left", border = "top", height = 0.48 },
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
              title_pos = "left",
              wo = picker_frame,
              {
                box = "vertical",
                border = "right",
                wo = { winhighlight = "FloatBorder:SnacksPickerListBorder" },
                { win = "input", height = 1, border = "bottom", title_pos = "left" },
                { win = "list", border = "none" },
              },
              { win = "preview", title = "{preview}", title_pos = "left", border = "top", width = 0.55 },
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
      terminal = {
        enabled = true,
        win = {
          on_buf = style_terminal,
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
      scroll = {
        enabled = not ui.neovide and not ui.reduced_motion,
        animate = { duration = { step = 10, total = ui.scroll_ms } },
        filter = function(buf)
          return vim.bo[buf].buftype == "" and vim.g.snacks_scroll ~= false and vim.b[buf].snacks_scroll ~= false
        end,
      },
      scope = { enabled = true },
      styles = {
        terminal = { backdrop = false },
        notification = { border = "rounded", wo = { winblend = ui.float_blend, wrap = true } },
        picker = { border = "rounded", wo = { winblend = ui.float_blend } },
      },
    },
    keys = LunaVim.plugin_lazy "snacks.nvim",
    config = function(_, opts)
      require("snacks").setup(opts)
      if opts.scroll.enabled then
        require("lunavim.config.scroll").setup()
      end
      require("lunavim.search").setup()
    end,
  },
}
