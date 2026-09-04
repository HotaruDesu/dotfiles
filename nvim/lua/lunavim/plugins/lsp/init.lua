return {
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        { path = "luvit-meta/library", words = { "vim%.uv" } },
        { path = "snacks.nvim", words = { "Snacks" } },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "saghen/blink.cmp",
    },
    config = function()
      local lsp_keymaps = require "lunavim.plugins.lsp.keymaps"

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client then
            lsp_keymaps.on_attach(client, args.buf)
          end
        end,
      })

      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = require("blink.cmp").get_lsp_capabilities(capabilities)

      local lsp_servers = require "lunavim.plugins.lsp.servers"
      for lang, opts in pairs(lsp_servers) do
        opts.capabilities = vim.tbl_deep_extend("force", opts.capabilities or {}, capabilities)
        vim.lsp.config(lang, opts)
        vim.lsp.enable(lang)
      end

      require("mason").setup { ui = { border = "rounded" } }

      require("mason-lspconfig").setup {
        ensure_installed = vim.tbl_keys(lsp_servers),
      }

      local icons = LunaVim.icons.diagnostics
      vim.diagnostic.config {
        underline = true,
        update_in_insert = false,
        virtual_text = { spacing = 4, source = "if_many", prefix = "●" },
        -- virtual_lines = true,
        severity_sort = true,
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = icons.Error,
            [vim.diagnostic.severity.WARN] = icons.Warn,
            [vim.diagnostic.severity.HINT] = icons.Hint,
            [vim.diagnostic.severity.INFO] = icons.Info,
          },
        },
      }
    end,
  },
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      formatters_by_ft = {
        cpp = { "clang-format" },
        go = { "gofmt" },
        lua = { "stylua" },
        rust = { "rustfmt", lsp_format = "fallback" },
        python = function(bufnr)
          if require("conform").get_formatter_info("ruff_format", bufnr).available then
            return { "ruff_format" }
          else
            return { "isort", "black" }
          end
        end,
        cmake = { "cmakelang" },
        -- Use the "*" filetype to run formatters on all filetypes.
        ["*"] = { "codespell" },
        -- Use the "_" filetype to run formatters on filetypes that don't
        -- have other formatters configured.
        ["_"] = { "trim_whitespace" },
      },
      -- format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
    },
  },
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = LunaVim.plugin_lazy "trouble.nvim",
    opts = {
      auto_close = true,
      restore_window = false,
      padding = false,
      indent_lines = false,
    },
  },
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
    opts = {},
  },
}
