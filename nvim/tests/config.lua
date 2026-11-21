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

local api = vim.api
local function keys(sequence)
  api.nvim_feedkeys(vim.keycode(sequence), "xt", false)
end

require("lunavim.config.keymaps").load_defaults()
local file = vim.fn.tempname()
vim.cmd.edit(vim.fn.fnameescape(file))
api.nvim_buf_set_lines(0, 0, -1, false, { "written by :W" })
local writes = 0
api.nvim_create_autocmd("BufWritePost", {
  buffer = 0,
  callback = function()
    writes = writes + 1
  end,
})
keys ":W<CR>"
assert(writes == 1 and not vim.bo.modified and vim.deep_equal(vim.fn.readfile(file), { "written by :W" }))
assert(not pcall(vim.cmd, "W!"), ":W must not force a write")
assert(not pcall(vim.cmd, "W another-file"), ":W must accept only the current buffer")
api.nvim_buf_set_lines(0, 0, -1, false, { "ordinary write" })
keys ":w<CR>"
assert(writes == 2 and vim.deep_equal(vim.fn.readfile(file), { "ordinary write" }))
vim.cmd.enew()
vim.fn.delete(file)
print "PASS: :W and :w save through the native write hooks"

vim.opt.cursorline = true
local editor = api.nvim_get_current_win()
vim.cmd.vsplit()
local other = api.nvim_get_current_win()
assert(vim.wo[other].cursorline and not vim.wo[editor].cursorline)
api.nvim_set_current_win(editor)
assert(vim.wo[editor].cursorline and not vim.wo[other].cursorline)
local insert_line
vim.keymap.set("i", "<F5>", function()
  insert_line = vim.wo.cursorline
end, { buffer = true })
for _, sequence in ipairs { "i<F5><Esc>", "i<F5><C-C>", "R<F5><Esc>" } do
  insert_line = nil
  keys(sequence)
  assert(insert_line == false and vim.wo.cursorline, "Cursor line must return after " .. sequence)
end
vim.keymap.set("i", "<F6>", function()
  api.nvim_set_current_win(other)
  insert_line = vim.wo.cursorline
end, { buffer = true })
keys "i<F6><Esc>"
assert(insert_line == false and vim.wo[other].cursorline and not vim.wo[editor].cursorline, "Insert-mode focus handoff restored the wrong line")
api.nvim_win_call(editor, function()
  vim.cmd "set nocursorline"
end)
api.nvim_set_current_win(editor)
assert(not vim.wo.cursorline, "A manual change while the cursor line is hidden must take precedence")
vim.keymap.del("i", "<F6>", { buffer = true })
vim.wo.cursorline = false
api.nvim_set_current_win(other)
api.nvim_set_current_win(editor)
keys "i<F5><Esc>"
assert(not vim.wo.cursorline, "Explicit nocursorline must survive mode and focus changes")
vim.keymap.del("i", "<F5>", { buffer = true })
vim.wo.cursorline = true
local function overlay(enter, focusable)
  return api.nvim_open_win(api.nvim_create_buf(false, true), enter, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 10,
    height = 1,
    focusable = focusable,
    style = "minimal",
  })
end
local floating = overlay(true, true)
vim.wo.cursorline = true
api.nvim_set_current_win(editor)
assert(vim.wo[floating].cursorline and vim.wo[editor].cursorline, "Floats own their cursor-line settings")
api.nvim_win_close(floating, false)
api.nvim_win_close(other, false)
for _, command in ipairs { "tabnew", "tab split" } do
  vim.cmd(command)
  local new_win = api.nvim_get_current_win()
  assert(vim.wo[new_win].cursorline and not vim.wo[editor].cursorline, command .. " must hand off the active line")
  vim.cmd.tabprevious()
  assert(vim.wo[editor].cursorline and not vim.wo[new_win].cursorline)
  vim.cmd.tabnext()
  assert(vim.wo[new_win].cursorline and not vim.wo[editor].cursorline)
  vim.cmd.tabclose()
end
vim.cmd "setlocal nocursorline"
vim.cmd.tabnew()
assert(vim.wo.cursorline, "A fresh buffer should take the default cursor-line setting")
vim.cmd.tabclose()
assert(not vim.wo.cursorline, "Returning from a fresh tab must respect the original window's opt-out")
vim.cmd "tab split"
assert(not vim.wo.cursorline, "A cloned view must inherit an explicit local opt-out")
vim.cmd.tabclose()
vim.wo.cursorline = true
print "PASS: active split and tab cursor line, insert and replace mode, manual opt-out and floating windows"

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

print "PASS: repeatable setup and saved/modified/shared/plugin/terminal cleanup"

local move = require("lunavim.util.window").send_to_next_tab
local source_tab = api.nvim_get_current_tabpage()
local tooltip = overlay(false, false)
move()
assert(#api.nvim_list_tabpages() == 1 and api.nvim_get_current_win() == editor, "A tooltip is not a second split")
api.nvim_win_close(tooltip, false)

local moving = split()
local moving_win = api.nvim_get_current_win()
local dialog = overlay(true, true)
move()
assert(#api.nvim_list_tabpages() == 1 and api.nvim_get_current_win() == dialog, "Do not send a float to another tab")
api.nvim_win_close(dialog, false)
local lines = {}
for i = 1, 80 do
  lines[i] = "line " .. i
end
api.nvim_buf_set_lines(moving, 0, -1, false, lines)
vim.bo[moving].modified = false
vim.wo.number = true
vim.wo.foldmethod = "manual"
vim.cmd "1,4fold"
api.nvim_win_set_cursor(moving_win, { 40, 2 })
vim.cmd "normal! zt"
local view = vim.fn.winsaveview()
move()
local destination = api.nvim_list_tabpages()[2]
assert(destination and api.nvim_get_current_tabpage() == source_tab and api.nvim_get_current_win() == editor)
assert(vim.deep_equal(api.nvim_tabpage_list_wins(destination), { moving_win }), "New tab must contain only the original window")
assert(api.nvim_win_get_buf(moving_win) == moving and vim.wo[moving_win].number)
api.nvim_set_current_tabpage(destination)
assert(api.nvim_get_current_win() == moving_win and vim.wo.cursorline)
assert(vim.deep_equal(api.nvim_win_get_cursor(moving_win), { 40, 2 }) and vim.fn.foldclosed(2) == 1)
assert(vim.fn.winsaveview().topline == view.topline, "Moving a split must preserve its viewport")

local destination_float = overlay(true, true)
api.nvim_set_current_tabpage(source_tab)
local second_buf = split(nil, true)
local second_win = api.nvim_get_current_win()
move()
assert(#api.nvim_list_tabpages() == 2 and api.nvim_get_current_win() == editor)
assert(api.nvim_win_get_tabpage(second_win) == destination and api.nvim_win_get_buf(second_win) == second_buf)
assert(api.nvim_win_is_valid(destination_float) and vim.bo[second_buf].modified)
api.nvim_set_current_tabpage(destination)
assert(api.nvim_get_current_win() == second_win, "Next visit to the destination should focus the moved split")
vim.cmd "tabclose!"

vim.cmd.new()
local before_failure = api.nvim_get_current_win()
vim.o.winwidth = vim.o.columns
vim.o.winminwidth = vim.o.columns
local moved, reason = pcall(move)
vim.o.winminwidth = 1
vim.o.winwidth = 20
assert(not moved and reason:match "E36", "A target split too narrow to fit must report its native error")
assert(#api.nvim_list_tabpages() == 1 and api.nvim_get_current_win() == before_failure, "Failed move must clean up the new tab")
assert(#api.nvim_tabpage_list_wins(source_tab) == 2)
print "PASS: float guards, native split movement, window state, destination focus and failed-move cleanup"

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
