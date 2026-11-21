-- Run: nvim --headless -u NONE -i NONE -n -l tests/completion_semantic.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/blink.cmp")
_G.LunaVim = require "lunavim"
local config = require "blink.cmp.config"
config.merge_with(require("lunavim.plugins.coding")[1].opts)

local api = vim.api
local semantic = require "lunavim.completion.semantic"
api.nvim_buf_set_lines(0, 0, -1, false, { "const idx;" })
api.nvim_win_set_cursor(0, { 1, 9 })
local ctx = {
  mode = "default",
  bufnr = api.nvim_get_current_buf(),
  get_line = api.nvim_get_current_line,
  get_cursor = function()
    return api.nvim_win_get_cursor(0)
  end,
}
local range = { start = { line = 0, character = 6 }, ["end"] = { line = 0, character = 9 } }
local symbol = {
  source_id = "lsp",
  source_name = "LSP",
  client_id = 1,
  kind = vim.lsp.protocol.CompletionItemKind.Variable,
  label = "idx_value",
  filterText = "idx_value",
  cursor_column = 9,
  insertText = "idx_value",
  textEdit = { range = range, newText = "idx_value" },
}
local function variant(fields)
  return vim.tbl_extend("force", vim.deepcopy(symbol), fields)
end

assert(semantic.same(symbol, variant { score = 10, sortText = "a", documentation = "Other wording" }, ctx))
for field, value in pairs {
  client_id = 2,
  data = { id = "other-origin" },
  command = { command = "finish" },
  commitCharacters = { ";" },
  insertTextMode = 2,
  labelDetails = { detail = "(const Buffer&)" },
} do
  assert(not semantic.same(symbol, variant { [field] = value }, ctx), "Distinct " .. field .. " must survive")
end
assert(not semantic.same(variant { documentation = "From `<one>`" }, variant { documentation = "From <two>" }, ctx))

local cached = variant { cursor_column = 8 }
assert(not semantic.same(symbol, cached, ctx), "The same raw range can replace different text after typing")
cached.textEdit.range["end"].character = 8
assert(semantic.same(symbol, cached, ctx), "Different raw ranges can describe the same current edit")
local replace = variant { textEdit = { insert = range, replace = range, newText = symbol.label } }
assert(semantic.same(symbol, replace, ctx), "InsertReplaceEdit should match the effective TextEdit")
local implicit = variant {}
implicit.textEdit = nil
assert(semantic.same(symbol, implicit, ctx), "Blink's inferred edit should match the explicit word replacement")

local renderer = require("blink.cmp.completion.windows.render").new(config.completion.menu.draw)
local buffer = api.nvim_create_buf(false, true)
local function render(items, limit)
  semantic.annotate(items, limit)
  renderer:draw(ctx, buffer, items)
  return api.nvim_buf_get_lines(buffer, 0, -1, false)
end
local function imported(header)
  local start = { line = 0, character = 0 }
  return variant { additionalTextEdits = { { range = { start = start, ["end"] = start }, newText = "#include <" .. header .. ">\n" } } }
end
local left, right = imported "left.hpp", imported "right.hpp"
local originals = vim.deepcopy { left, right }
assert(not semantic.same(left, right, ctx))
local rows = render { left, right }
assert(rows[1]:find("<left.hpp>", 1, true) and rows[2]:find("<right.hpp>", 1, true), vim.inspect(rows))
assert(vim.deep_equal(originals, { left, right }), "Rendering must preserve the upstream items")
assert(not render({ left, right }, 1)[1]:find("<left.hpp>", 1, true), "A hidden row should not annotate the visible row")
render { left, right }
assert(not render({ left })[1]:find("<left.hpp>", 1, true), "A singleton must lose its previous annotation")
left.labelDetails, right.labelDetails = { detail = "(int)" }, { detail = "(double)" }
rows = render { left, right }
assert(rows[1]:find("(int)", 1, true) and rows[2]:find("(double)", 1, true) and not rows[1]:find("<left.hpp>", 1, true), "Visible overload signatures already distinguish the rows")
print "PASS: effective Blink edits, distinct LSP actions and completion row rendering"
