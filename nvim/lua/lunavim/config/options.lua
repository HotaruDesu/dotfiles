vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Editing: spaces, persistent undo and case-aware search.
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.inccommand = "split"
vim.opt.confirm = true

-- Keep navigation and display behavior consistent in terminals and Neovide.
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.wrap = true
vim.opt.breakindent = true
vim.opt.mouse = "a"
vim.opt.showmode = false
vim.opt.signcolumn = "yes:2"
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Preserve the existing key-sequence timing and background update frequency.
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 0

vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.opt.winblend = 0
vim.opt.pumblend = 0

-- Defer clipboard-provider initialization until startup has finished.
vim.schedule(function()
  vim.opt.clipboard = "unnamedplus"
end)

require("lunavim.config.neovide").setup()
