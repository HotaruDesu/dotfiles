local M = {}

local function get_clangd_path()
  local cmd = "which clangd"
  local handle = io.popen(cmd)
  if handle then
    local result = handle:read "*a"
    handle:close()
    if result and result ~= "" then
      local path = result:gsub("%s+", "")
      if vim.fn.executable(path) == 1 then
        return path
      end
    end
  end
  return "clangd"
end

M.clangd = {
  root_dir = function(bufnr, on_dir)
    local root = vim.fs.root(bufnr, {
      "Makefile",
      "configure.ac",
      "configure.in",
      "config.h.in",
      "meson.build",
      "opt/build/compile_commands.json",
      "compile_flags.txt",
      ".git",
    })
    on_dir(root)
  end,
  capabilities = require('blink.cmp').get_lsp_capabilities(),
  cmd = {
    get_clangd_path(),
    "--background-index", -- create index in background
    "--clang-tidy", -- activate clang-tidy
    "--header-insertion=iwyu", -- include header automatically
    "--completion-style=detailed", -- completion style when you typing
    "--function-arg-placeholders", -- function placeholders for <Tab>
    "--fallback-style=llvm",
    "--experimental-modules-support",
    "--pch-storage=disk",
  },
  init_options = {
    usePlaceholders = true,
    completeUnimported = true,
    clangdFileStatus = true,
  },
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
