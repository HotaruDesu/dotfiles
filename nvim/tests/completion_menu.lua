-- Run: nvim --headless -u NONE -i NONE -n -l tests/completion_menu.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/blink.cmp")

local menu = require "lunavim.completion.menu"
local navigation = require "lunavim.completion.navigation"
local sources = require "blink.cmp.sources.lib"
local kinds = vim.lsp.protocol.CompletionItemKind
menu.setup()
local filter = sources.apply_max_items_for_completions
menu.setup()
assert(sources.apply_max_items_for_completions == filter)

local function context(ft, before, after)
  vim.bo.filetype = ft
  local lines = vim.split(before, "\n", { plain = true })
  before = lines[#lines]
  local line = before .. (after or "")
  lines[#lines] = line
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  local cursor = { #lines, #before }
  return {
    id = 1,
    mode = "default",
    bufnr = vim.api.nvim_get_current_buf(),
    line = line,
    cursor = cursor,
    bounds = { start_col = #before - #(before:match "([%w_]*)$") + 1 },
    get_line = function()
      return line
    end,
    get_cursor = function()
      return cursor
    end,
  }
end

local function item(source, label, kind, extra)
  return vim.tbl_extend("force", { source_id = source, label = label, kind = kind or kinds.Text }, extra or {})
end

local function expect(actual, expected)
  assert(#actual == #expected, vim.inspect { actual = actual, expected = expected })
  for idx, native in ipairs(expected) do
    assert(actual[idx] == native, vim.inspect { idx = idx, actual = actual[idx], expected = native })
  end
end

local raw = item("buffer", "push_back")
local unrelated = item("buffer", "pushCart")
local snippet = item("snippets", "print")
local a = item("lsp", " push_back", kinds.Method, { filterText = "push_back", labelDetails = { detail = "(const_reference x)" } })
local b = item("lsp", " push_back", kinds.Method, { filterText = "push_back", labelDetails = { detail = "(value_type &&x)" } })
local member = context("cpp", "  items.pu", ";")
expect(filter(member, { raw, unrelated, snippet, a, b }), { a, b })
expect(filter(member, { unrelated, snippet }), { unrelated })
local camel = item("lsp", "pushBack", kinds.Method)
expect(filter(context("cpp", "  items.pb"), { unrelated, camel, a, b }), { camel, a, b })
local pb = item("lsp", "pbValue", kinds.Field)
expect(filter(context("cpp", "  items.pb"), { camel, a, pb, b }), { pb })
local api_method = item("lsp", "nvim_get_current_line()", kinds.Function)
expect(filter(context("lua", "vim.api.ngcl"), { unrelated, api_method }), { api_method })
local unicode_field = item("lsp", "缓存大小", kinds.Field)
expect(filter(context("cpp", "obj.缓存"), { unrelated, unicode_field }), { unicode_field })
navigation.is_full = function()
  return true
end
expect(filter(member, { raw, unrelated, snippet, a, b }), { a, b, unrelated, snippet })
navigation.is_full = function()
  return false
end
navigation.selected = function()
  return unrelated, 2
end
expect(filter(member, { unrelated, a, b }), { a, unrelated, b })
navigation.selected = function() end

local stat = item("lsp", " stat", kinds.Function, { filterText = "stat" })
local struct = item("lsp", " stat", kinds.Struct, { filterText = "stat" })
local cast = item("lsp", " static_cast", kinds.Snippet, { filterText = "static_cast" })
local fallback = item("cpp_syntax", "static_cast", kinds.Keyword)
local local_var = item("lsp", " state", kinds.Variable, { filterText = "state" })
local imported = item("lsp", "•std::filesystem::status", kinds.Function, { filterText = "status", additionalTextEdits = { { newText = "#include <filesystem>\n" } } })
local typed = item("buffer", "state")
local other = item("buffer", "station")
expect(filter(context("cpp", "  return stat", ";"), { imported, fallback, cast, typed, other, local_var }), { local_var, cast, other, imported })
expect(filter(context("cpp", "  return stat", ";"), { imported, typed, other, fallback, local_var }), { local_var, fallback, other, imported })
expect(filter(context("cpp", "  return ::stat", ";"), { stat, struct, imported, unrelated, snippet }), { stat, struct, imported })
expect(filter(context("cpp", "struct stat", " result;"), { stat, struct }), { struct, stat })
local storage = item("lsp", " static", kinds.Keyword, { filterText = "static" })
expect(filter(context("cpp", "#include <sys/stat.h>\nstat"), { struct, stat, storage }), { storage, struct, stat })
expect(filter(context("cpp", "#include <sys/stat.h>\nint f() { return stat", "; }"), { stat, struct, cast, local_var }), { local_var, cast, stat, struct })
expect(filter(context("cpp", "#include <sys/stat.h>\nint f() { return stat", "(nullptr, nullptr); }"), { stat, struct, cast }), { stat, struct, cast })
local plain_status = item("buffer", "status")
expect(filter(context("cpp", "  return stat", ";"), { imported, plain_status }), { plain_status, imported })

-- Keep the real cursor and line available to Blink's edit conversion. The
-- server replied one keystroke ago and counted its offsets in UTF-16.
local prefix = "/*宽*/ std::"
local token = "uint32"
context("cpp", prefix .. token, ";")
vim.api.nvim_win_set_cursor(0, { 1, #prefix + #token })
local qualified = require("blink.cmp.completion.trigger.context").new { id = 2, trigger_kind = "keyword", providers = { "lsp", "buffer" } }
local cursor = qualified.cursor[2]
local first = vim.str_utfindex(prefix, "utf-16")
local function edit(start_col, end_col, text)
  return { range = { start = { line = 0, character = start_col }, ["end"] = { line = 0, character = end_col } }, newText = text }
end
local project_word = item("buffer", "uint32_t")
local symbol = item("lsp", "•uint32_t", kinds.Class, {
  filterText = "uint32_t",
  client_id = 42,
  cursor_column = cursor - 1,
  textEdit = edit(first, first + #token - 1, "uint32_t"),
  additionalTextEdits = { edit(0, 0, "#include <cstdint>\n") },
})
local get_client = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function(id)
  if id == symbol.client_id then
    return { offset_encoding = "utf-16" }
  end
  return get_client(id)
end
local copy = vim.tbl_extend("force", vim.deepcopy(symbol), { sortText = "later", documentation = "Another wording" })
expect(filter(qualified, { project_word, symbol, copy }), { symbol })
navigation.is_full = function()
  return true
end
expect(filter(qualified, { project_word, symbol, copy }), { symbol })
local wrong_range = vim.deepcopy(symbol)
wrong_range.textEdit.range.start.character = first - 1
expect(filter(qualified, { project_word, wrong_range }), { wrong_range, project_word })
navigation.is_full = function()
  return false
end

navigation.selected = function()
  return symbol, 1
end
expect(filter(qualified, { copy, project_word, symbol }), { symbol })
navigation.selected = function()
  return project_word, 1
end
expect(filter(qualified, { copy, symbol, project_word }), { project_word })
navigation.selected = function() end

-- Distinct qualified names have the same clangd filterText.
local other_namespace = vim.tbl_extend("force", symbol, { textEdit = edit(first, first + #token - 1, "other::uint32_t") })
expect(filter(qualified, { symbol, copy, other_namespace }), { symbol, other_namespace })
local semantic = require "lunavim.completion.semantic"
local alternative_header = vim.deepcopy(symbol)
alternative_header.additionalTextEdits[1].newText = "#include <stdint.h>\n"
expect(filter(qualified, { symbol, alternative_header }), { symbol, alternative_header })
assert(semantic.description { item = symbol } == "<cstdint>" and semantic.description { item = alternative_header } == "<stdint.h>")
expect(filter(qualified, { symbol }), { symbol })
assert(semantic.description { item = symbol } == "" and semantic.description { item = alternative_header } == "")
local list_config = require("blink.cmp.config").completion.list
local limit = list_config.max_items
list_config.max_items = 1
expect(filter(qualified, { symbol, alternative_header }), { symbol, alternative_header })
assert(semantic.description { item = symbol } == "", "A collision below the visible limit should not add a hint")
list_config.max_items = limit
vim.lsp.get_client_by_id = get_client

local vector = item("lsp", " vector>", kinds.File, { filterText = "vector>" })
local folder = item("lsp", " vecLib/", kinds.Folder, { filterText = "vecLib/" })
local intrinsic = item("lsp", " vecintrin.h>", kinds.File, { filterText = "vecintrin.h>" })
local private = item("lsp", " __vector/", kinds.Folder, { filterText = "__vector/" })
expect(filter(context("cpp", "#include <vec", ">"), { intrinsic, folder, private, raw, vector }), { vector, intrinsic, folder })
local header = item("lsp", 'renderer.hpp"', kinds.File)
expect(filter(context("cpp", '#include "engine/ren', '"'), { raw, header, snippet }), { header })
local module = item("lsp", "orchard_utils", kinds.File)
local wrong_module = item("lsp", "vim._core.shared", kinds.File)
expect(filter(context("lua", 'require("orchard_', '")'), { wrong_module, raw, module }), { module })
local module_leaf = item("lsp", "parser", kinds.File)
expect(filter(context("lua", 'require "app.par', '"'), { wrong_module, raw, module_leaf }), { module_leaf })

local func = item("lsp", "function ()", kinds.Snippet)
local fuzzy = item("lsp", "unfortunate", kinds.Variable)
local longer_function = item("buffer", "functionallyUnrelated")
expect(filter(context("lua", "funct"), { fuzzy, item("buffer", "function"), longer_function, func }), { func, longer_function, fuzzy })
-- A used project word and an ordinary function retain Blink's adaptive order.
local render_fn = item("lsp", "render_scene", kinds.Function)
local render_word = item("buffer", "renderSceneConfig")
expect(filter(context("lua", "ren"), { render_word, render_fn }), { render_word, render_fn })
expect(filter(context("lua", "ren"), { render_fn, render_word }), { render_fn, render_word })
local class = item("snippets", "class", kinds.Snippet)
local clamp = item("lsp", "•std::clamp", kinds.Function, { filterText = "clamp", additionalTextEdits = { { newText = "#include <algorithm>\n" } } })
expect(filter(context("cpp", "  return clam", ";"), { class, clamp }), { clamp, class })
local dict = item("dictionary", "reason")
local longer = item("buffer", "reasonAbout")
local project_term = item("buffer", "releaseAssets")
expect(filter(context("markdown", "reas"), { dict, snippet, project_term, longer }), { longer, project_term, dict })
local identical = item("buffer", "reason")
expect(filter(context("markdown", "reas"), { dict, identical }), { identical })
expect(filter(context("cpp", "// reasons"), { snippet, longer }), { longer })
expect(filter(context("cpp", 'const char* title = "reas', '";'), { snippet, longer }), { longer })
local md_table = item("snippets", "table", kinds.Snippet)
expect(filter(context("markdown", "table"), { snippet, md_table }), { md_table })
local link = item("path", "logo.png", kinds.File)
expect(filter(context("markdown", "![logo](assets/lo", ")"), { longer, link }), { link })

-- The original per-provider hook must still apply. Setting a small global
-- limit on Blink's actual list catches accidental deduplication after slicing.
local config = require "blink.cmp.config"
local list = require "blink.cmp.completion.list"
config.fuzzy.frecency.enabled = false
list.config.max_items = 2
for _, id in ipairs { "lsp", "buffer" } do
  sources.providers[id] = { config = {
    max_items = function()
      return id == "buffer" and 1 or nil
    end,
  } }
end
expect(filter(context("lua", "pri"), { unrelated, raw, a }), { unrelated, a })
local print_fn = item("lsp", "print", kinds.Function, { score_offset = 0 })
local printf = item("lsp", "printf", kinds.Function, { score_offset = -9 })
local plain = item("buffer", "print", nil, { score_offset = 20 })
expect(list.fuzzy(context("lua", "pri"), { lsp = { print_fn, printf }, buffer = { plain } }), { print_fn, printf })
local duplicate = vim.deepcopy(print_fn)
duplicate.score_offset = -1
expect(list.fuzzy(context("lua", "pri"), { lsp = { print_fn, duplicate, printf } }), { print_fn, printf })
print "PASS: completion contexts, ranking, selection, cross-source duplicates and Blink limits"
