local cmdline_layout = require "lunavim.config.cmdline"
local ui = require("lunavim.config.ui").get()

-- Noice's auto-width can shrink to the grid only above its configured minimum.
local function compact_prompt(columns, min_width)
  return {
    filter = {
      event = "cmdline",
      kind = { "cmdline", "lua", "filter", "help", "calculator" },
      cond = function()
        return vim.o.columns < columns
      end,
    },
    view = "cmdline_popup",
    opts = { size = { min_width = min_width } },
  }
end

local function setup_native_completion()
  -- Noice's NUI backend anchors auto-positioned candidates to the first
  -- text row. It has no option for the outside edge of a bordered prompt.
  local backend = require "noice.ui.popupmenu.nui"
  local defaults = backend._lunavim_original_opts or backend.opts
  backend._lunavim_original_opts = defaults
  backend.opts = function(state)
    local opts, padding = defaults(state)
    if state.grid == -1 then
      local prompt, edge, direction, space = cmdline_layout.card_edge()
      if prompt then
        opts.anchor = direction == "s" and "NW" or "SW"
        opts.position.row = direction == "s" and edge + 1 or edge
        opts.position.col = math.max(0, cmdline_layout.word_col(prompt, state.col) - padding.left)
        opts.size.max_height = math.max(1, math.min(opts.size.max_height, space))
        opts.win_options.winhighlight = cmdline_layout.menu_highlight(opts.win_options.winhighlight)
      end
    end
    return opts, padding
  end

  -- Selecting a native candidate can rewrap the prompt after the menu opens.
  local function align_visible_menu()
    local popup = package.loaded["noice.ui.popupmenu"]
    local menu = backend.menu
    if not (menu and menu.winid and popup and popup.state.visible and popup.state.grid == -1 and vim.fn.getcmdtype() == ":") then
      return
    end
    require("noice.message.router").update()
    local opts = backend.opts(popup.state)
    menu:update_layout {
      position = opts.position,
      anchor = opts.anchor,
      size = { width = vim.api.nvim_win_get_width(menu.winid), height = math.min(#popup.state.items, opts.size.max_height) },
    }
    if backend.scroll then
      backend.scroll:update()
    end
  end
  vim.api.nvim_create_autocmd("CmdlineChanged", {
    pattern = ":",
    group = vim.api.nvim_create_augroup("LunaNativeCmdlineCompletion", { clear = true }),
    callback = function()
      if backend.menu then
        vim.schedule(align_visible_menu)
      end
    end,
  })
end

return {
  -- Notice and notify
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
    init = function()
      vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("LunaCmdlineLayout", { clear = true }),
        callback = function()
          -- An unchanged command receives no cmdline_show event on resize.
          local cmdline = package.loaded["noice.ui.cmdline"]
          if cmdline and cmdline.last() then
            cmdline.update()
            local cmp = package.loaded["blink.cmp"]
            if cmp and cmp.is_menu_visible() then
              require("noice.message.router").update()
              cmp.show { providers = cmp.get_context().providers }
            else
              local popup = package.loaded["noice.ui.popupmenu"]
              if popup and popup.state.visible and popup.state.grid == -1 then
                require("noice.message.router").update()
                popup.backend.on_show(popup.state)
              end
            end
          end
        end,
      })
    end,
    opts = {
      lsp = {
        -- Blink owns signature help, so typing a call opens one popup.
        signature = { enabled = false },
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
        },
      },
      cmdline = {
        opts = { border = { text = { top = "" } } },
        format = {
          cmdline = { icon = ":" },
          inc_rename = { icon = "", opts = { skip = true }, pattern = "^:%s*IncRename%s+" },
        },
      },
      presets = {
        bottom_search = true, -- use a classic bottom cmdline for search
        command_palette = false,
        long_message_to_split = true, -- long messages will be sent to a split
        lsp_doc_border = true, -- add a border to hover docs and signature help
      },
      views = {
        cmdline_popup = {
          position = { row = "32%", col = "50%" },
          size = { min_width = 48 },
          border = { style = "rounded", padding = { 0, 1 } },
          win_options = { winblend = ui.float_blend, wrap = true },
        },
        cmdline_popupmenu = { border = { style = "none" } },
        popup = { win_options = { winblend = ui.float_blend } },
      },
      routes = { compact_prompt(36, 14), compact_prompt(52, 32) },
      redirect = {
        view = "notify",
        filter = { event = "msg_show" },
      },
    },
    config = function(_, opts)
      setup_native_completion()
      require("noice").setup(opts)
    end,
  },
}
