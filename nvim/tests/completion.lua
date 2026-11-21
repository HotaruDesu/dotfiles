-- Run: nvim --headless -u NONE -i NONE -n -l tests/completion.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/blink.cmp")
_G.LunaVim = require "lunavim"
require("blink.cmp.config").merge_with(require("lunavim.plugins.coding")[1].opts)

local api = vim.api
local current = api.nvim_get_current_buf()
vim.bo.filetype = "cpp"
api.nvim_buf_set_lines(current, 0, -1, false, { "", "CurrentBufferWord" })
local sources = require "blink.cmp.sources.lib"
local tree = require("blink.cmp.sources.lib.tree").new { providers = sources.get_enabled_provider_ids "default" }
local independent = {}
for _, node in ipairs(tree:get_top_level_nodes()) do
  independent[node.id] = true
end
assert(independent.lsp and independent.path and independent.buffer, "LSP, path and buffer should all contribute independently")

local function hidden_word(word, listed)
  local buf = api.nvim_create_buf(listed, false)
  api.nvim_buf_set_lines(buf, 0, -1, false, { word })
  return buf
end
-- Exceed Blink's 20 KB synchronous parsing limit to exercise the asynchronous result.
local hidden = hidden_word(("HiddenBufferWord "):rep(1500), true)
local special = hidden_word("SpecialBufferWord", true)
vim.bo[special].buftype = "nofile"
hidden_word("UnlistedBufferWord", false)
local excluded = hidden_word("DisabledBufferWord", true)
vim.b[excluded].completion = false
local unloaded = vim.fn.bufadd(vim.fn.tempname() .. ".cpp")
vim.bo[unloaded].buflisted = true
assert(not api.nvim_buf_is_loaded(unloaded) and #vim.fn.win_findbuf(hidden) == 0)

local buffer = sources.get_provider_by_id("buffer").module
assert(not vim.tbl_contains(buffer.opts.get_bufnrs(), unloaded), "Unloaded files must not be sent to the buffer parser")
local function words()
  local labels
  buffer:get_completions({}, function(response)
    labels = vim.tbl_map(function(item)
      return item.label
    end, response.items)
    table.sort(labels)
  end)
  assert(
    vim.wait(2000, function()
      return labels ~= nil
    end),
    "Blink did not return buffer candidates"
  )
  return labels
end
assert(vim.deep_equal(words(), { "CurrentBufferWord", "HiddenBufferWord" }), "Unexpected editing candidates")

local search_providers, search_words
vim.keymap.set("c", "<F5>", function()
  search_providers = sources.get_enabled_provider_ids "cmdline"
  search_words = words()
end, { buffer = true })
api.nvim_feedkeys(vim.keycode "/<F5><Esc>", "xt", false)
assert(vim.deep_equal(search_providers, { "buffer" }) and vim.deep_equal(search_words, { "CurrentBufferWord" }), "A / search must use only the current buffer")
print "PASS: independent Blink providers, hidden editing buffers and current-buffer search"

local cpp = sources.get_provider_by_id("cpp_syntax").module
local function keyword(lines, row)
  api.nvim_buf_set_lines(current, 0, -1, false, lines)
  row = row or #lines
  local start, finish = assert(lines[row]:find("stat", 1, true))
  local items
  cpp:get_completions({ bufnr = current, line = lines[row], cursor = { row, finish }, bounds = { start_col = start } }, function(response)
    items = response.items
  end)
  return items[1] and items[1].label
end
assert(keyword { "stat" } == "static")
assert(keyword({ "int f() {", "  stat", "}" }, 2) == "static")
assert(keyword { "int f() { return stat; }" } == "static_cast")
assert(keyword { "int values[] = {stat};" } == "static_cast")
assert(keyword { "int x =", "stat;" } == "static_cast")
assert(keyword { "struct stat value;" } == nil)
assert(keyword { "void f() { ptr->stat; }" } == nil)
assert(keyword { "void f() { ptr->", "stat; }" } == nil)
assert(keyword { "void f() { ::stat(); }" } == nil)
assert(keyword { 'const char *s = R"(', 'stat)";' } == nil)
assert(keyword { "/* comment", "stat */" } == nil)
print "PASS: C++ syntax fallback for declarations and expressions"

for _, cmdtype in ipairs { ":", "/", "?" } do
  local providers
  api.nvim_create_autocmd("CmdwinEnter", {
    once = true,
    callback = function()
      providers = sources.get_enabled_provider_ids "cmdwin"
    end,
  })
  api.nvim_feedkeys(vim.keycode("q" .. cmdtype .. "<C-c><Esc>"), "xt", false)
  assert(vim.deep_equal(providers, cmdtype == ":" and { "cmdline", "buffer" } or { "buffer" }), "Incorrect completion sources in q" .. cmdtype)
end
print "PASS: Ex and search history window completion"
