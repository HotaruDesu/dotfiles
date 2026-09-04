local M = {}

local function get_clangd_path()
  local path = vim.fn.exepath "clangd"
  return path ~= "" and path or "clangd"
end

M.clangd = {
  root_markers = {
    { ".clangd", "compile_commands.json", "compile_flags.txt" },
    { "CMakeLists.txt", "Makefile", "meson.build", "configure.ac", "configure.in" },
    ".git",
  },
  cmd = {
    get_clangd_path(),
    "--log=error", -- keep routine protocol traffic out of Neovim's LSP log
    "--background-index", -- create index in background
    "--clang-tidy", -- activate clang-tidy
    "--header-insertion=iwyu", -- include header automatically
    "--completion-style=detailed", -- completion style when you typing
    "--function-arg-placeholders=1", -- function placeholders for <Tab>
    "--fallback-style=llvm",
  },
  on_new_config = function(new_config, new_root_dir)
    local cmake_project = vim.fs.find("CMakeLists.txt", {
      path = new_root_dir,
      upward = true,
    })[1]
    if not cmake_project then
      return
    end

    local ok, cmake = pcall(require, "cmake-tools")
    if ok then
      cmake.clangd_on_new_config(new_config)
    end
  end,
}

M.gopls = {
  root_dir = function(bufnr, on_dir)
    local root = vim.fs.root(bufnr, {
      "go.work",
      "go.mod",
      ".git",
    })
    on_dir(root)
  end,
  settings = {
    gopls = {
      gofumpt = true,
      codelenses = {
        gc_details = false,
        generate = true,
        regenerate_cgo = true,
        run_govulncheck = true,
        test = true,
        tidy = true,
        upgrade_dependency = true,
        vendor = true,
      },
      hints = {
        assignVariableTypes = true,
        compositeLiteralFields = true,
        compositeLiteralTypes = true,
        constantValues = true,
        functionTypeParameters = true,
        parameterNames = true,
        rangeVariableTypes = true,
      },
      analyses = {
        unusedparams = true,
      },
      staticcheck = true,
      directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
      semanticTokens = true,
    },
  },
}

M.lua_ls = {
  root_dir = function(bufnr, on_dir)
    local root = vim.fs.root(bufnr, {
      ".luarc.json",
      ".luarc.jsonc",
      ".git",
    })
    on_dir(root)
  end,
  settings = {
    Lua = {
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
    codeLens = {
      enable = true,
    },
    completion = {
      callSnippet = "Replace",
    },
    doc = {
      privateName = { "^_" },
    },
    hint = {
      enable = true,
      setType = true,
    },
    diagnostics = {
      unusedLocalExclude = { "_*" },
    },
  },
}

M.markdown_oxide = {
  root_dir = require("lspconfig.util").root_pattern(".obsidian", "obsidian.vimrc", ".git"),
}

M.ts_ls = {}

M.neocmake = {}

return M
