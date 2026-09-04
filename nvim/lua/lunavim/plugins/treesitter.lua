return {
  -- Syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local install_languages = {
        "cpp",
        "go",
        "lua",
        "vim",
        "bash",
        "cmake",
        "markdown",
        "markdown_inline",
        "regex",
        "javascript",
        "typescript",
      }
      local treesitter = require "nvim-treesitter"
      local installed = {}
      for _, language in ipairs(treesitter.get_installed "parsers") do
        installed[language] = true
      end

      local missing = vim.tbl_filter(function(language)
        return not installed[language]
      end, install_languages)
      if #missing > 0 then
        treesitter.install(missing, { summary = true })
      end

      vim.api.nvim_create_autocmd("FileType", {
        pattern = install_languages,
        callback = function()
          -- syntax highlighting, provided by Neovim
          vim.treesitter.start()
          -- folds, provided by Neovim
          -- vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
          -- vim.wo.foldmethod = 'expr'
          -- indentation, provided by nvim-treesitter
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
  -- Show sematic context
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "BufReadPost",
    opts = {
      max_lines = 1,
      multiline_threshold = 1,
    },
  },
}
