local M = {}

function M.setup()
  local path = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
  if not vim.uv.fs_stat(path) then
    local output = vim.fn.system {
      "git",
      "clone",
      "--filter=blob:none",
      "--branch=stable",
      "https://github.com/folke/lazy.nvim.git",
      path,
    }
    if vim.v.shell_error ~= 0 or not vim.uv.fs_stat(path .. "/lua/lazy/init.lua") then
      error("Could not install lazy.nvim:\n" .. output, 0)
    end
  end
  vim.opt.rtp:prepend(path)

  require("lazy").setup {
    spec = { { import = "lunavim.plugins" }, { import = "lunavim.plugins.custom" } },
    defaults = { lazy = true },
    ui = { border = "rounded", icons = { loaded = "●", not_loaded = "○" } },
    checker = { enabled = true, notify = false },
    rocks = { enabled = false },
    performance = {
      rtp = { disabled_plugins = { "gzip", "matchit", "zipPlugin", "netrwPlugin", "tarPlugin", "tohtml", "tutor" } },
    },
  }
end

return M
