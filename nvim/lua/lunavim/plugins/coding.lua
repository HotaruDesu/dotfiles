return {
  -- CMP
  {
    "saghen/blink.cmp",
    dependencies = {
      -- snippets
      "rafamadriz/friendly-snippets",
      -- ripgrep
      "mikavilpas/blink-ripgrep.nvim",
      -- dictionary
      "Kaiser-Yang/blink-cmp-dictionary",
      -- git
      "Kaiser-Yang/blink-cmp-git",
    },
    version = "1.*",
    opts = {
      enabled = function()
        return vim.bo.filetype ~= "oil" and vim.bo.buftype ~= "prompt" and vim.b.completion ~= false
      end,
      keymap = {
        preset = "default",
        ["<C-\\>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-k>"] = { "select_prev", "fallback" },
        ["<C-j>"] = { "select_next", "fallback" },
        ["<C-b>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },
        ["<C-u>"] = { "scroll_signature_up", "fallback" },
        ["<C-d>"] = { "scroll_signature_down", "fallback" },
        ["<C-e>"] = { "hide" },
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
      },
      appearance = {
        nerd_font_variant = "mono",
      },
      completion = {
        menu = {
          auto_show = true,
          border = "rounded",
          draw = {
            padding = 1,
            treesitter = { "lsp" },
            columns = {
              { "item_idx" },
              { "kind_icon" },
              { "label", "label_description", gap = 1 },
              { "source_name" },
            },
            components = {
              item_idx = {
                text = function(ctx)
                  return tostring(ctx.idx)
                end,
                highlight = "BlinkCmpItemIdx", -- optional, only if you want to change its color
              },
              source_name = {
                width = { max = 15 },
                text = function(ctx)
                  return "[" .. ctx.source_name .. "]"
                end,
                highlight = function(ctx)
                  return ctx.kind_hl
                end,
              },
            },
          },
        },
        accept = {
          auto_brackets = { enabled = true },
        },
        documentation = {
          window = { border = "rounded" },
        },
        list = {
          selection = { preselect = false, auto_insert = true },
        },
        ghost_text = { enabled = true },
      },
      fuzzy = {
        sorts = {
          "exact",
          "score",
          "sort_text",
          "label",
        },
      },
      signature = {
        enabled = true,
        trigger = {
          show_on_insert = true,
        },
        window = { border = "rounded" },
      },
      sources = {
        default = {
          "lsp",
          "path",
          "snippets",
          "lazydev",
          "buffer",
        },
        per_filetype = {
          gitcommit = { "lsp", "snippets", "path", "buffer" },
          NeogitCommitMessage = { "lsp", "snippets", "path", "buffer" },
          markdown = { "lsp", "snippets", "path", "buffer", "dictionary" },
        },
        providers = {
          lsp = {
            name = "LSP",
            module = "blink.cmp.sources.lsp",
            fallbacks = {
              "ripgrep",
            },
            score_offset = 100,
            transform_items = function(_, items)
              return vim.tbl_filter(function(item)
                local kind = require("blink.cmp.types").CompletionItemKind
                -- return item.kind ~= kind.Keyword
                return item.kind ~= kind.Text
              end, items)
            end,
          },
          buffer = {
            name = "Buffer",
            module = "blink.cmp.sources.buffer",
            min_keyword_length = 1,
          },
          ripgrep = {
            name = "Ripgrep",
            module = "blink-ripgrep",
            min_keyword_length = 2,
            score_offset = -1,
            transform_items = function(_, items)
              for _, item in ipairs(items) do
                item.labelDetails = { description = "(rg)" }
              end
              return items
            end,
          },

          snippets = {
            score_offset = -100,
            min_keyword_length = 3,
            opts = {
              friendly_snippets = true, -- default
              extended_filetypes = {
                markdown = { "jekyll" },
                sh = { "shelldoc" },
                php = { "phpdoc" },
                cpp = { "unreal" },
              },
            },
          },
          dictionary = {
            module = "blink-cmp-dictionary",
            name = "Dict",
            min_keyword_length = 1,
            opts = {},
            score_offset = 10,
          },
          git = {
            module = "blink-cmp-git",
            name = "Git",
            opts = {},
            score_offset = 0,
          },
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
          local type = vim.fn.getcmdtype()
          -- Search forward and backward
          if type == "/" or type == "?" then
            return { "buffer" }
          end
          -- Commands
          if type == ":" or type == "@" then
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
    "nvim-mini/mini.pairs",
    event = "InsertEnter",
    lazy = true,
    opts = {},
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
