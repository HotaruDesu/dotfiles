-- Run: nvim --headless -u NONE -i NONE -n -l tests/config.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
vim.o.hidden = true

local autocmds = require "lunavim.config.autocmds"
autocmds.setup()
local count = #vim.api.nvim_get_autocmds { group = "LunaVimBuffers" }
autocmds.setup()
assert(count == #vim.api.nvim_get_autocmds { group = "LunaVimBuffers" }, "Reload duplicated buffer listeners")

local function split(kind, modified)
  vim.cmd "vnew"
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = kind or ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "keep this text" })
  vim.bo[buf].modified = modified or false
  return buf
end
local function close()
  vim.cmd "close"
  vim.wait(20, function()
    return false
  end)
end
local saved = split()
close()
assert(not vim.api.nvim_buf_is_valid(saved), "Saved hidden file must be cleaned up")
local modified = split(nil, true)
close()
assert(vim.api.nvim_buf_is_valid(modified), "Modified buffer must survive closing a split")
local special = split "nofile"
close()
assert(vim.api.nvim_buf_is_valid(special), "Plugin buffer must survive cleanup")
local shared = split()
vim.cmd "vsplit"
close()
assert(vim.api.nvim_buf_is_valid(shared), "Visible buffer must survive closing its other window")
close()
assert(not vim.api.nvim_buf_is_valid(shared))

vim.cmd "vnew"
local terminal = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "sh", "-c", "printf ready" }, { term = true })
assert(job > 0)
vim.fn.jobwait({ job }, 1000)
close()
assert(vim.api.nvim_buf_is_valid(terminal), "Terminal transcript must survive cleanup")

local moving = split()
local source_tab = vim.api.nvim_get_current_tabpage()
require("lunavim.util.window").send_to_next_tab()
assert(vim.wait(1000, function()
  return #vim.api.nvim_tabpage_list_wins(source_tab) == 1
end))
assert(vim.api.nvim_buf_is_valid(moving), "Moving a window must not prune its buffer")
local tabs = vim.api.nvim_list_tabpages()
assert(#tabs == 2 and vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(tabs[2])) == moving)
print "PASS: repeatable setup, saved/modified/shared/plugin/terminal cleanup and window movement"

-- Bootstrap failure must surface git's error before any lazy.setup call.
local system, stat = vim.fn.system, vim.uv.fs_stat
vim.fn.system = function()
  return "fatal: simulated git failure"
end
vim.uv.fs_stat = function(path)
  if path:find("/lazy/lazy.nvim", 1, true) then
    return nil
  end
  return stat(path)
end
local ok, err = pcall(require("lunavim.lazy").setup)
vim.fn.system, vim.uv.fs_stat = system, stat
assert(not ok and err:find("Could not install lazy.nvim", 1, true) and err:find("simulated git failure", 1, true))
print "PASS: bootstrap failure reports its actual cause"
