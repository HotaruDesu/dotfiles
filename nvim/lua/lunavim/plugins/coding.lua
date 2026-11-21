local cmdline = require "lunavim.config.cmdline"
local navigation = require "lunavim.completion.navigation"
local text = require "lunavim.completion.text"
local ui = require("lunavim.config.ui").get()
local prose_sources = { "lsp", "snippets", "path", "buffer", "dictionary" }

local function cmdline_position()
  local pos = vim.g.ui_cmdline_pos
  if not pos then
    return { vim.o.lines - math.max(1, vim.o.cmdheight), 0 }
  end
  local row, col = pos[1] - 1, pos[2]
  local prompt, edge = cmdline.card_edge()
  if prompt then
    row = edge
    local ctx = require("blink.cmp").get_context()
    if ctx then
      col = cmdline.word_col(prompt, ctx.bounds.start_col - 1) - ctx.bounds.start_col
    end
  end
  return { row, col }
end

return {
  -- CMP
  {
    "saghen/blink.cmp",
    event = { "InsertEnter", "CmdlineEnter" },
    init = function()
      vim.api.nvim_create_autocmd("User", {
        group = vim.api.nvim_create_augroup("LunaCmdlineCompletion", { clear = true }),
        pattern = "BlinkCmpMenuOpen",
        callback = function()
          if vim.fn.getcmdtype() == ":" then
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "blink-cmp-menu" then
                vim.wo[win].winhighlight = cmdline.menu_highlight(vim.wo[win].winhighlight)
              end
            end
          end
        end,
      })
    end,
    dependencies = {
      -- snippets
      "rafamadriz/friendly-snippets",
      -- dictionary
      "Kaiser-Yang/blink-cmp-dictionary",
    },
    version = "1.*",
    config = function(_, opts)
      require("blink.cmp").setup(opts)
      require("lunavim.completion.menu").setup()
      navigation.setup()
    end,
    opts = {
      enabled = function()
        return vim.bo.filetype ~= "oil" and vim.bo.buftype ~= "prompt" and vim.b.completion ~= false
      end,
      keymap = {
        preset = "default",
        ["<C-\\>"] = { navigation.show_full, "show_documentation", "hide_documentation" },
        ["<C-k>"] = { navigation.select_prev, "fallback" },
        ["<C-j>"] = { navigation.select_next, "fallback" },
        ["<C-b>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },
        ["<C-u>"] = { "scroll_signature_up", "fallback" },
        ["<C-d>"] = { "scroll_signature_down", "fallback" },
        ["<C-e>"] = { "cancel", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
      },
      appearance = {
        nerd_font_variant = "mono",
        kind_icons = LunaVim.icons.kinds,
      },
      completion = {
        menu = {
          auto_show = true,
          auto_show_delay_ms = 0,
          min_width = 14,
          max_height = 10,
          cmdline_position = cmdline_position,
          direction_priority = function()
            local _, _, direction = cmdline.card_edge()
            return direction and { direction } or { "s", "n" }
          end,
          border = "rounded",
          winblend = ui.float_blend,
          draw = {
            padding = 1,
            treesitter = { "lsp" },
            columns = {
              { "kind_icon" },
              { "label", "label_description", gap = 1 },
              { "source_name" },
            },
            components = {
              label = {
                width = {
                  fill = true,
                  max = function(ctx)
                    return ctx.mode == "cmdline" and math.max(1, math.min(45, vim.o.columns - 4)) or 45
                  end,
                },
              },
              label_description = {
                width = { max = 25 },
                text = require("lunavim.completion.semantic").description,
              },
              source_name = {
                width = { max = 8 },
                text = function(ctx)
                  local names = {
                    Buffer = "BUF",
                    LSP = "LSP",
                    Path = "PATH",
                    Snippets = "SNIP",
                  }
                  return "[" .. (names[ctx.source_name] or ctx.source_name) .. "]"
                end,
                highlight = "BlinkCmpSource",
              },
            },
          },
        },
        accept = {
          auto_brackets = { enabled = true },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 300,
          update_delay_ms = 50,
          window = {
            border = "rounded",
            winblend = ui.float_blend,
            max_width = 72,
            max_height = 18,
          },
        },
        list = {
          selection = { preselect = false, auto_insert = true },
        },
        ghost_text = { enabled = false },
      },
      fuzzy = {
        sorts = {
          "exact",
          "score",
          "sort_text",
        },
      },
      signature = {
        enabled = true,
        trigger = {
          show_on_insert = true,
        },
        window = { border = "rounded", winblend = ui.float_blend },
      },
      sources = {
        min_keyword_length = 2,
        default = {
          "lsp",
          "path",
          "snippets",
          "lazydev",
          "buffer",
        },
        per_filetype = {
          cpp = { "lsp", "path", "cpp_syntax", "snippets", "buffer" },
          text = prose_sources,
          gitcommit = prose_sources,
          NeogitCommitMessage = prose_sources,
          markdown = prose_sources,
        },
        providers = {
          lsp = {
            name = "LSP",
            module = "blink.cmp.sources.lsp",
            fallbacks = {},
            score_offset = 2,
          },
          path = { fallbacks = {}, override = { get_completions = text.path_completions } },
          cpp_syntax = { name = "C++", module = "lunavim.completion.cpp", min_keyword_length = 3, score_offset = -3 },
          buffer = {
            name = "Buffer",
            module = "blink.cmp.sources.buffer",
            min_keyword_length = 2,
            score_offset = function(ctx)
              return ctx.mode == "default" and -1 or -5
            end,
            opts = {
              get_bufnrs = function()
                return vim.tbl_filter(function(buf)
                  return vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and vim.b[buf].completion ~= false
                end, vim.api.nvim_list_bufs())
              end,
            },
          },
          snippets = {
            score_offset = -5,
            min_keyword_length = 2,
            opts = {
              get_filetype = text.snippet_filetype,
              friendly_snippets = true, -- default
              extended_filetypes = {
                markdown = { "jekyll" },
                sh = { "shelldoc" },
                php = { "phpdoc" },
              },
            },
          },
          dictionary = text.dictionary_provider(),
          lazydev = {
            name = "LazyDev",
            module = "lazydev.integrations.blink",
            score_offset = 0,
          },
        },
      },
      snippets = {},
      cmdline = {
        enabled = true,
        keymap = { preset = "cmdline" },
        sources = function()
          local cmdtype = vim.fn.getcmdtype()
          if cmdtype == "" then
            cmdtype = vim.fn.getcmdwintype()
          end
          -- Search forward and backward
          if cmdtype == "/" or cmdtype == "?" then
            return { "buffer" }
          end
          -- Commands
          if cmdtype == ":" or cmdtype == "@" then
            return { "cmdline", "buffer" }
          end
          return {}
        end,
        completion = {
          trigger = {},
          list = {
            selection = {
              preselect = true,
              auto_insert = true,
            },
          },
          -- Whether to automatically show the window when new completion items are available
          -- Default is false for cmdline, true for cmdwin (command-line window)
          menu = {
            draw = { columns = { { "label" } } },
            auto_show = function(ctx, _)
              return ctx.mode == "cmdwin"
            end,
          },
          ghost_text = { enabled = true },
        },
      },
    },
  },
  -- Alignment
  {
    "nvim-mini/mini.align",
    event = "BufReadPost",
    opts = {
      mappings = LunaVim.plugin_raw "mini.align",
    },
  },
  -- Simple surround plugin
  {
    "nvim-mini/mini.surround",
    event = "VeryLazy",
    opts = {
      mappings = LunaVim.plugin_raw "mini.surround",
    },
  },
  -- Extend text object
  {
    "nvim-mini/mini.ai",
    event = "VeryLazy",
    opts = function()
      local ai = require "mini.ai"
      return {
        n_lines = 500,
        custom_textobjects = {
          -- code block
          o = ai.gen_spec.treesitter {
            a = { "@block.outer", "@conditional.outer", "@loop.outer" },
            i = { "@block.inner", "@conditional.inner", "@loop.inner" },
          },
          -- function
          f = ai.gen_spec.treesitter { a = "@function.outer", i = "@function.inner" },
          -- class
          c = ai.gen_spec.treesitter { a = "@class.outer", i = "@class.inner" },
        },
      }
    end,
  },
  {
    "Wansmer/treesj",
    keys = LunaVim.plugin_lazy "treesj",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      use_default_keymaps = false,
      max_join_length = 150,
      check_syntax = true,
      cursor_behavior = "hold",
    },
  },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      local npairs = require "nvim-autopairs"
      npairs.setup {
        check_ts = true,
        ts_config = {
          lua = { "string", "source" },
          javascript = { "template_string" },
        },
        fast_wrap = {},
      }

      npairs.add_rules(require "nvim-autopairs.rules.endwise-lua")
    end,
  },
}
