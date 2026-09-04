return {
  -- CMP
  {
    "saghen/blink.cmp",
    dependencies = {
      -- snippets
      "rafamadriz/friendly-snippets",
      -- dictionary
      "Kaiser-Yang/blink-cmp-dictionary",
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
          min_width = 30,
          max_height = 10,
          border = "rounded",
          winblend = 0,
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
                width = { fill = true, max = 45 },
              },
              label_description = {
                width = { max = 25 },
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
            winblend = 0,
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
        window = { border = "rounded" },
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
          cpp = { "lsp", "path", "snippets", "buffer" },
          gitcommit = { "lsp", "snippets", "path", "buffer" },
          NeogitCommitMessage = { "lsp", "snippets", "path", "buffer" },
          markdown = { "lsp", "snippets", "path", "buffer", "dictionary" },
        },
        providers = {
          lsp = {
            name = "LSP",
            module = "blink.cmp.sources.lsp",
            fallbacks = {
              "buffer",
            },
            score_offset = 5,
          },
          buffer = {
            name = "Buffer",
            module = "blink.cmp.sources.buffer",
            min_keyword_length = 2,
            score_offset = -5,
          },
          snippets = {
            score_offset = -5,
            min_keyword_length = 2,
            opts = {
              friendly_snippets = true, -- default
              extended_filetypes = {
                markdown = { "jekyll" },
                sh = { "shelldoc" },
                php = { "phpdoc" },
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
