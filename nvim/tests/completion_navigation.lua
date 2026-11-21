-- Exercise Blink's real list, preview edits and Accept using deterministic provider replies.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/blink.cmp")
require("blink.cmp.config").merge_with {
  completion = { list = { selection = { preselect = false, auto_insert = true } }, accept = { dot_repeat = false } },
}
local contexts = require "blink.cmp.completion.trigger.context"
local list = require "blink.cmp.completion.list"
local navigation = require "lunavim.completion.navigation"
local sources = require "blink.cmp.sources.lib"
sources.get_provider_by_id "buffer"
navigation.setup()
navigation.setup()

local history, calls = {}, {}
require("blink.cmp.fuzzy").access = function(item)
  table.insert(history, item.label)
end
list.fuzzy = function(_, by_source)
  return by_source.buffer
end
local function item(label, signature)
  return {
    label = label,
    kind = vim.lsp.protocol.CompletionItemKind.Text,
    source_id = "buffer",
    cursor_column = 2,
    labelDetails = { detail = signature },
    textEdit = { newText = label, range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 2 } } },
  }
end
local items = {}
for i = 1, 10 do
  items[i] = item("word" .. i)
end
items[11] = item("word", "(int)")
items[12] = item("word", "(double)")
local function imported(header)
  local symbol = item("word", "(double)")
  symbol.additionalTextEdits = { { range = vim.deepcopy(symbol.textEdit.range), newText = "#include <" .. header .. ">" } }
  return symbol
end
local symbol = imported "first.h"
assert(navigation.same_item(symbol, vim.deepcopy(symbol)))
assert(not navigation.same_item(symbol, imported "second.h"), "Two different auto-imports must keep distinct identities")
local shifted = vim.deepcopy(symbol)
shifted.textEdit.range.start.character = 1
assert(not navigation.same_item(symbol, shifted), "A candidate with a different edit range must not inherit the selection")
vim.keymap.set("i", "<F5>", function()
  calls.ctx = contexts.new { id = 1, trigger_kind = "keyword", providers = { "buffer" } }
  list.show(calls.ctx, { buffer = items })
  list.select(12)
end)
vim.keymap.set("i", "<F6>", function()
  -- A new object for the same overload arrives below Blink's native top-ten cutoff.
  local fresh = vim.deepcopy(items)
  list.show(calls.ctx, { buffer = fresh })
  calls.selected = list.get_selected_item()
  calls.position = list.selected_item_idx
  calls.original_initial = calls.ctx.initial_selected_item_idx
end)
vim.keymap.set("i", "<F7>", function()
  list.show(calls.ctx, { buffer = { items[11] } })
  calls.disappeared = list.get_selected_item() == nil
end)
local menu = {
  is_menu_visible = function()
    return list.context ~= nil
  end,
}
for key, select_item in pairs { ["<C-j>"] = navigation.select_next, ["<C-k>"] = navigation.select_prev } do
  vim.keymap.set("i", key, function()
    return select_item(menu)
  end, { expr = true, replace_keycodes = false })
end
vim.keymap.set("i", "<C-e>", function()
  list.undo_preview()
  list.hide()
end)
vim.keymap.set("i", "<CR>", function()
  assert(list.accept())
end)

local function type_keys(keys, line, col)
  list.hide()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line or "wo(5)" })
  vim.api.nvim_win_set_cursor(0, { 1, col or 2 })
  vim.api.nvim_feedkeys(vim.keycode("i" .. keys .. "<Esc>"), "xt", false)
  local flushed = false
  vim.schedule(function()
    flushed = true
  end)
  assert(vim.wait(250, function()
    return flushed
  end))
  return vim.api.nvim_get_current_line()
end
assert(type_keys "<F5><F6>xy" == "wordxy(5)")
assert(calls.selected.labelDetails.detail == "(double)" and calls.position == 12 and calls.original_initial == nil, "Late results changed the selected overload")
assert(vim.deep_equal(history, { "word" }), "Continuing a preview must record it once")
assert(type_keys "<F5><F7>x" == "wox(5)" and calls.disappeared and #history == 1, "Do not silently switch to a different overload if a selected item disappears")
assert(type_keys "<F5><C-k><C-k>x" == "word10x(5)")
assert(vim.deep_equal(history, { "word", "word10" }), "Skipped items entered the history")
assert(type_keys "<F5><C-k><C-j>xy" == "wordxy(5)" and #history == 3, "Queued navigation must run before the following text")
assert(type_keys "<F5><C-e>x" == "wox(5)" and #history == 3)
assert(type_keys "<F5>" == "word(5)" and #history == 3, "Leaving insert mode is not a continuation")
assert(type_keys "<F5><CR>" == "word(5)" and #history == 4, "Explicit acceptance should use Blink's single native history update")

-- A hidden preview's undo edit belongs to the previous buffer.
assert(type_keys "<F5>" == "word(5)")
list.hide()
assert(list.preview_undo ~= nil)
vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
vim.api.nvim_set_current_line "another document"
local request
assert(navigation.show_full {
  is_menu_visible = function()
    return false
  end,
  show = function(opts)
    request = opts
    return true
  end,
})
assert(navigation.is_full { mode = "default", providers = request.providers })
assert(not navigation.is_full { mode = "cmdline", providers = request.providers })
assert(not navigation.is_full { mode = "default", providers = vim.deepcopy(request.providers) })
assert(vim.api.nvim_get_current_line() == "another document")

-- Select the fallback while clangd is pending, then deliver an auto-import
-- before Enter. Blink must still accept the original buffer word.
vim.bo.filetype = "cpp"
require("lunavim.completion.menu").setup()
list.fuzzy = function(ctx, replies)
  return sources.apply_max_items_for_completions(ctx, replies.buffer)
end
local prefix = "using T = std::uint32"
local fallback = { source_id = "buffer", label = "uint32_t", kind = vim.lsp.protocol.CompletionItemKind.Text, cursor_column = #prefix }
local late = {
  source_id = "lsp",
  label = "•uint32_t",
  filterText = "uint32_t",
  kind = vim.lsp.protocol.CompletionItemKind.Reference,
  cursor_column = #prefix,
  textEdit = { newText = "uint32_t", range = { start = { line = 0, character = #"using T = std::" }, ["end"] = { line = 0, character = #prefix } } },
  additionalTextEdits = { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }, newText = "#include <cstdint>\n" } },
}
vim.keymap.set("i", "<F8>", function()
  calls.ctx = contexts.new { id = 2, trigger_kind = "keyword", providers = { "lsp", "buffer" } }
  list.show(calls.ctx, { buffer = { fallback } })
end)
vim.keymap.set("i", "<F9>", function()
  list.show(calls.ctx, { buffer = { late, fallback } })
  calls.after_refresh = { #list.items, list.get_selected_item() }
end)
assert(type_keys("<F8><C-j><F9><CR>", prefix .. ";", #prefix) == "using T = std::uint32_t;")
assert(calls.after_refresh[1] == 1 and calls.after_refresh[2] == fallback)
assert(vim.api.nvim_buf_line_count(0) == 1, "Enter unexpectedly applied the late clangd import")
print "PASS: preview continuation, native history, late overloads, cancellation, acceptance and manual scope"
