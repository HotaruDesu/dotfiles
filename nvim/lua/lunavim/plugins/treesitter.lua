return {
  -- Syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = false,
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
      local enabled = {}
      for _, language in ipairs(install_languages) do
        enabled[language] = true
      end
      local managed = {}
      local indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      local group = vim.api.nvim_create_augroup("LunaVimTreesitter", { clear = true })

      local function warn(message)
        vim.schedule(function()
          vim.notify_once("Treesitter: " .. message, vim.log.levels.WARN)
        end)
      end

      local function restore(buf)
        local previous = managed[buf]
        if previous then
          vim.treesitter.stop(buf)
          if vim.bo[buf].indentexpr == indentexpr then
            vim.bo[buf].indentexpr = previous.indentexpr
          end
          managed[buf] = nil
        end
      end

      local function start_highlighting(buf)
        if not vim.api.nvim_buf_is_loaded(buf) then
          return
        end
        local ft = vim.bo[buf].filetype
        local lang = vim.treesitter.language.get_lang(ft)
        if managed[buf] and managed[buf].lang ~= lang then
          restore(buf)
        end
        if not enabled[lang] or vim.bo[buf].buftype ~= "" then
          return
        end
        if managed[buf] and vim.treesitter.highlighter.active[buf] then
          return
        end

        -- Validate queries before starting; an incomplete syntax tree is normal
        -- while editing and must never switch the buffer back to regex syntax.
        local ok, err = pcall(function()
          assert(vim.treesitter.get_parser(buf, lang), "parser unavailable: " .. lang)
          assert(vim.treesitter.query.get(lang, "highlights"), "highlight query unavailable: " .. lang)
          vim.treesitter.start(buf, lang)
        end)
        if not ok then
          restore(buf)
          vim.treesitter.stop(buf)
          vim.bo[buf].syntax = ft
          warn(("%s highlighting unavailable; using syntax. %s"):format(lang, err))
          return
        end

        managed[buf] = managed[buf] or { lang = lang, indentexpr = vim.bo[buf].indentexpr }
        local indent_ok, query = pcall(vim.treesitter.query.get, lang, "indents")
        if indent_ok and query then
          vim.bo[buf].indentexpr = indentexpr
        elseif not indent_ok then
          warn(("%s indentation unavailable. %s"):format(lang, query))
        end
      end

      vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
        group = group,
        callback = function(args)
          start_highlighting(args.buf)
        end,
      })
      vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function(args)
          managed[args.buf] = nil
        end,
      })

      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        start_highlighting(buf)
      end

      if #missing > 0 then
        treesitter.install(missing, { summary = true }):await(function(err, success)
          vim.schedule(function()
            if err or not success then
              warn("parser installation did not fully succeed; see :TSLog. " .. tostring(err or ""))
            end
            -- Some parsers can succeed even if another installation failed.
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              start_highlighting(buf)
            end
          end)
        end)
      end
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
