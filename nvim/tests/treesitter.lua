-- Run: nvim --headless -u NONE -i NONE -n -l tests/treesitter.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/after")
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/nvim-treesitter")
vim.cmd "runtime plugin/filetypes.lua"
vim.o.swapfile = false
vim.cmd "syntax on"
local function buffer(ft, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft
  return buf
end
local function active(buf)
  return vim.treesitter.highlighter.active[buf] ~= nil
end
local treesitter = require "nvim-treesitter"
local installed = treesitter.get_installed
local install = treesitter.install
local get_parser = vim.treesitter.get_parser
local notify = vim.notify_once
vim.notify_once = function() end
local missing = buffer("cpp", { "class T {};" })
local unavailable = true
vim.treesitter.get_parser = function(buf, ...)
  if buf == missing and unavailable then
    error "simulated missing parser"
  end
  return get_parser(buf, ...)
end
treesitter.get_installed = function()
  return vim.tbl_filter(function(lang)
    return lang ~= "cpp"
  end, installed "parsers")
end
local completed
treesitter.install = function()
  return {
    await = function(_, callback)
      completed = callback
    end,
  }
end
require("lunavim.plugins.treesitter")[1].config()
assert(not active(missing) and vim.bo[missing].syntax == "cpp")
unavailable = false
completed(nil, true)
assert(vim.wait(1000, function()
  return active(missing)
end))
assert(vim.bo[missing].syntax == "")
treesitter.get_installed, treesitter.install = installed, install
vim.treesitter.get_parser = get_parser

local function captured(buf, row, col, expected)
  get_parser(buf):parse()
  for _, capture in ipairs(vim.treesitter.get_captures_at_pos(buf, row, col)) do
    if capture.capture == expected then
      return
    end
  end
  error("Missing " .. expected)
end
captured(missing, 0, 0, "keyword.type")
captured(missing, 0, 6, "type")
for _, text in ipairs { "class", "class T {", "template<typename", "class T {};" } do
  vim.api.nvim_buf_set_lines(missing, 0, -1, false, { text })
  get_parser(missing):parse()
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = missing })
  assert(active(missing) and vim.bo[missing].syntax == "", "Incomplete code disabled highlighting")
end
local modules = buffer("cpp", { "module foo;", "import foo;", "import <vector>;" })
captured(modules, 0, 0, "keyword.type")
captured(modules, 0, 7, "module")
captured(modules, 1, 0, "keyword.import")
captured(modules, 1, 7, "module")
captured(modules, 2, 9, "string")
for _, ft in ipairs { "lua", "markdown", "sh" } do
  assert(active(buffer(ft, { "text" })), "Filetype mapping failed: " .. ft)
end
vim.bo[missing].filetype = "text"
assert(not active(missing))
vim.notify_once = notify
print "PASS: Treesitter fallback/recovery, filetype mapping, incomplete C++ and module captures"
