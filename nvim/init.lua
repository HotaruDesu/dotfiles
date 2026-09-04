require "lunavim.util"
require "lunavim.config"
-- require "lunavim.lazy"

local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  vim.fn.system {
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup {
  spec = {
    { import = "lunavim.plugins" },
    { import = "lunavim.plugins.custom" },
  },
  defaults = {
    lazy = true,
  },
  ui = {
    border = "rounded",
    icons = {
      loaded = "●",
      not_loaded = "○",
    },
  },
  checker = {
    enabled = true, -- check the plugin updates
    notify = false, -- notify on update
  },
  rocks = {
    enabled = false,
  },
  performance = {
    rtp = {
      disabled_plugins = { "gzip", "matchit", "zipPlugin", "netrwPlugin", "tarPlugin", "tohtml", "tutor" },
    },
  },
}
