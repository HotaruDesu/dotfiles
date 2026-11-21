-- Run: nvim --headless -u NONE -i NONE -n -l tests/statusline.lua
local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
if not arg[1] then
  for _, frontend in ipairs { "terminal", "neovide" } do
    local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", script, frontend }, { text = true }):wait(10000)
    assert(result.code == 0, frontend .. ": " .. result.stdout .. result.stderr)
  end
  print "PASS: both frontends render the same tab, split titles and responsive mode statusline"
  return
end
local root = vim.fn.fnamemodify(script, ":h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs { "tokyonight.nvim", "bufferline.nvim", "lualine.nvim", "nvim-web-devicons", "incline.nvim" } do
  vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/" .. plugin)
end
vim.o.swapfile = false
vim.o.termguicolors = true
vim.g.neovide = arg[1] == "neovide" or nil
_G.LunaVim = { icons = require "lunavim.config.icons" }

local theme = dofile(root .. "/lua/lunavim/ui_specs/theme.lua")[1]
theme.opts.cache = false
theme.config(nil, theme.opts)
local chrome = dofile(root .. "/lua/lunavim/ui_specs/chrome.lua")
chrome[2].init()
require("bufferline").setup(chrome[2].opts)
vim.cmd "file alpha.lua"
vim.cmd "tabnew beta.lua"
local tabline = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, highlights = true, maxwidth = 100 })

local function rendered_color(line, token)
  local offset = assert(line.str:find(token, 1, true), token .. " missing from " .. line.str) - 1
  local group
  for _, span in ipairs(line.highlights) do
    if span.start > offset then
      break
    end
    group = span.group
  end
  return vim.api.nvim_get_hl(0, { name = assert(group), link = false })
end

-- Compare the styles of the rendered glyphs, including lualine's generated mode highlights.
local lualine = require "lualine"
local function statusline()
  return vim.api.nvim_eval_statusline(lualine.statusline(true), { highlights = true, maxwidth = vim.o.columns })
end
vim.bo.filetype = "lua"
lualine.setup(chrome[1].opts)
vim.o.columns = 120
vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "content" }, 20))
vim.bo.fileencoding = "utf-8"
vim.bo.modified = false
vim.api.nvim_win_set_cursor(0, { 10, 2 })

local normal = statusline()
local file_column = assert(normal.str:find("beta.lua", 1, true))
local tab_marker = rendered_color(tabline, "▎")
local tab_selected = rendered_color(tabline, "beta.lua")
local tab_divider = rendered_color(tabline, "│")
local backgrounds = {}
local function check_mode(line, mode)
  assert(line.str:match("^▎%s*" .. mode .. "%s*│%s*beta%.lua"), "Misaligned mode or filename: " .. line.str)
  assert(line.str:find("beta.lua", 1, true) == file_column, "Changing mode should keep the filename in place")
  assert(select(2, line.str:gsub("▎", "")) == 1 and not line.str:find("╱", 1, true))
  assert(line.str:match "lua%s*│%s*50%%%s*10:3$", "Right group or cursor position changed: " .. line.str)
  local block, marker, divider = rendered_color(line, mode), rendered_color(line, "▎"), rendered_color(line, "│")
  assert(marker.bg == block.bg and block.bg and not backgrounds[block.bg], mode .. " needs its own continuous mode background")
  local divider_offset = line.str:find("│", 1, true) - 1
  for _, span in ipairs(line.highlights) do
    if span.start >= divider_offset then
      break
    end
    assert(vim.api.nvim_get_hl(0, { name = span.group, link = false }).bg == block.bg, "Gap in the " .. mode .. " block")
  end
  backgrounds[block.bg] = mode
  assert(divider.fg == tab_divider.fg and divider.bg == tab_divider.bg)
  assert(rendered_color(line, "10:3").bg == tab_divider.bg, mode .. " color should stay on the left")
  if mode == "NORMAL" then
    assert(block.fg == tab_selected.fg and block.bg == tab_selected.bg)
    assert(marker.fg == tab_marker.fg and marker.bg == tab_marker.bg)
  else
    assert(marker.fg ~= tab_marker.fg and block.fg ~= tab_selected.fg, mode .. " marker and label should reflect the mode")
  end
end
check_mode(normal, "NORMAL")
-- Supply only the mode input. Feeding keys while resizing a headless 0.12 grid
-- can crash Neovim; lualine still renders and Neovim resolves the real colors.
local get_mode = vim.api.nvim_get_mode
for code, label in pairs { i = "INSERT", c = "COMMAND", v = "VISUAL", R = "REPLACE", t = "TERMINAL" } do
  vim.api.nvim_get_mode = function()
    return { mode = code, blocking = false }
  end
  local ok, line = pcall(statusline)
  vim.api.nvim_get_mode = get_mode
  assert(ok, line)
  check_mode(line, label)
end

-- Model one attached server and keep it running when switching to an unrelated buffer.
local attached = vim.api.nvim_get_current_buf()
local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function(opts)
  if not opts or not opts.bufnr or opts.bufnr == attached then
    return { { id = 1, name = "TestLS" } }
  end
  return {}
end
for _, width in ipairs { 120, 100, 99, 85, 76, 75, 50, 49, 45 } do
  vim.o.columns = width
  local line = statusline().str
  assert(vim.fn.strdisplaywidth(line) == width and line:match "10:3$", "Location must reach the right edge: " .. line)
  assert((line:find("50%", 1, true) ~= nil) == (width >= 50), "Progress threshold at " .. width .. ": " .. line)
  assert((line:find("TestLS", 1, true) ~= nil) == (width >= 76), "LSP threshold at " .. width .. ": " .. line)
  assert((line:lower():find("utf-8", 1, true) ~= nil) == (width >= 100), "Encoding threshold at " .. width .. ": " .. line)
  assert((line:match "%f[%a]LF%f[%A]" ~= nil) == (width >= 100), "File format threshold at " .. width .. ": " .. line)
end
vim.o.columns = 120
for format, label in pairs { unix = "LF", dos = "CRLF", mac = "CR" } do
  vim.bo.fileformat = format
  assert(statusline().str:match("%f[%a]" .. label .. "%f[%A]"), "File format should render as " .. label)
end
vim.bo.filetype = ""
local untyped = statusline().str
assert(select(2, untyped:gsub("│", "")) == 1 and untyped:match "50%%%s*10:3$", "Untyped buffers should have no filetype divider")

vim.bo.modified = false
vim.cmd.enew()
vim.api.nvim_buf_set_name(0, vim.fn.tempname() .. ".txt")
assert(not statusline().str:find("TestLS", 1, true), "An unrelated file must not show another buffer's LSP")
vim.lsp.get_clients = get_clients
vim.bo.buftype = "nofile"
vim.bo.fileencoding = "utf-8"
vim.bo.fileformat = "dos"
local special = statusline().str
assert(not special:lower():find("utf-8", 1, true) and not special:find("CRLF", 1, true), "Special buffers must omit file metadata")
vim.cmd "tabnew saved.lua"
local saved = vim.api.nvim_get_current_win()
vim.cmd "rightbelow vnew edited.lua"
local edited = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "return true" })
chrome[4].config()
local function has_title(parent, expected)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "incline" then
      local content = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      local config = vim.api.nvim_win_get_config(win)
      local right = vim.api.nvim_win_get_position(parent)[2] + vim.api.nvim_win_get_width(parent)
      if config.col + config.width == right - 1 and vim.endswith(content, expected) then
        return true
      end
    end
  end
end
assert(
  vim.wait(1200, function()
    return has_title(saved, "saved.lua ") and has_title(edited, "edited.lua ● ")
  end),
  "Incline titles or margin missing"
)
require("incline").disable()
