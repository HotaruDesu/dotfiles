local M = {}
local kinds = vim.lsp.protocol.CompletionItemKind
local empty = {}
local hints = setmetatable({}, { __mode = "k" })

local function string_field(value)
  return type(value) == "string" and value or ""
end

local function table_field(value)
  return type(value) == "table" and value or empty
end

local function insertion(item)
  -- Blink has already materialized textEditText from LSP itemDefaults.
  local edited = table_field(item.textEdit).newText
  if type(edited) == "string" then
    return edited
  end
  return type(item.insertText) == "string" and item.insertText or item.label
end

function M.same_edit(a, b, ctx)
  if insertion(a) ~= insertion(b) then
    return false
  end
  local implicit = not a.textEdit and not b.textEdit
  if implicit and a.kind == b.kind and a.label == b.label and a.filterText == b.filterText and a.insertText == b.insertText then
    return true
  end
  if not implicit and type(a.cursor_column) == "number" and a.cursor_column == b.cursor_column and a.client_id == b.client_id and vim.deep_equal(a.textEdit, b.textEdit) then
    return true
  end

  -- Blink chooses insert/replace policy, compensates for typing since the
  -- request, and converts the LSP client's offsets to current UTF-8 bytes.
  ctx = ctx or (package.loaded["blink.cmp.completion.list"] or {}).context
  if
    not ctx
    or ctx.mode ~= "default"
    or not ctx.get_cursor
    or not ctx.get_line
    or ctx.bufnr ~= vim.api.nvim_get_current_buf()
    or not vim.deep_equal(ctx.get_cursor(), vim.api.nvim_win_get_cursor(0))
    or ctx.get_line() ~= vim.api.nvim_get_current_line()
  then
    return implicit
  end
  if (a.textEdit and type(a.cursor_column) ~= "number") or (b.textEdit and type(b.cursor_column) ~= "number") then
    return false
  end
  local get = require("blink.cmp.lib.text_edits").get_from_item
  local ok_a, edit_a = pcall(get, a)
  local ok_b, edit_b = pcall(get, b)
  return ok_a and ok_b and edit_a.newText == edit_b.newText and vim.deep_equal(edit_a.range, edit_b.range)
end

-- A server may identify the declaring header or module only in documentation.
-- Ordinary documentation wording is not part of a completion's identity.
local function documented_origin(item)
  local doc = item.documentation
  local text = type(doc) == "table" and doc.value or doc
  if type(text) ~= "string" or not text:find("From ", 1, true) then
    return
  end
  for line in text:gmatch "[^\r\n]+" do
    local origin = line:match "^From `([^`]+)`%s*$" or line:match "^From (<[^>]+>)%s*$" or line:match '^From ("[^"]+")%s*$'
    if origin then
      return origin
    end
  end
end

-- Compare only colliding LSP items. Rank, match scores and incidental prose
-- may change, while resolve data, edits and commands affect what Enter does.
function M.same(a, b, ctx)
  if a.source_id ~= "lsp" or b.source_id ~= "lsp" or a.client_id ~= b.client_id then
    return false
  end
  if a == b then
    return true
  end
  local ad, bd = table_field(a.labelDetails), table_field(b.labelDetails)
  return vim.trim(a.label) == vim.trim(b.label)
    and a.kind == b.kind
    and string_field(a.detail) == string_field(b.detail)
    and string_field(ad.detail) == string_field(bd.detail)
    and string_field(ad.description) == string_field(bd.description)
    and (a.insertTextFormat or 1) == (b.insertTextFormat or 1)
    and a.insertTextMode == b.insertTextMode
    and vim.deep_equal(table_field(a.additionalTextEdits), table_field(b.additionalTextEdits))
    and vim.deep_equal(a.commitCharacters, b.commitCharacters)
    and vim.deep_equal(a.command, b.command)
    and vim.deep_equal(a.data, b.data)
    and M.same_edit(a, b, ctx)
    and documented_origin(a) == documented_origin(b)
end

local function header(item)
  for _, edit in ipairs(table_field(item.additionalTextEdits)) do
    local text = string_field(edit.newText)
    local include = text:match "^%s*#%s*include%s*(<[^>]+>)" or text:match '^%s*#%s*include%s*("[^"]+")'
    if include then
      return include
    end
  end
  return documented_origin(item)
end

local function scope(item)
  local token = insertion(item):match "^[%w_.$:]+"
  return token and (token:match "^(.*)::[%w_]+$" or token:match "^(.*)%.[%w_]+$")
end

local function detail(item)
  local text = vim.trim(string_field(item.detail))
  if text ~= "" then
    return (text:gsub("%s+", " "))
  end
end

local descriptions = {
  detail,
  scope,
  header,
  function(item)
    return kinds[item.kind]
  end,
}

local function annotate_group(group, start)
  if #group < 2 then
    return
  end
  -- A second distinguishing property is needed only if some rows still tie.
  for i = start, #descriptions do
    local by_value, count = {}, 0
    for _, item in ipairs(group) do
      local value = descriptions[i](item) or ""
      if not by_value[value] then
        by_value[value], count = {}, count + 1
      end
      table.insert(by_value[value], item)
    end
    if count > 1 then
      for value, tied in pairs(by_value) do
        if value ~= "" then
          for _, item in ipairs(tied) do
            hints[item] = hints[item] and value .. " · " .. hints[item] or value
          end
        end
        annotate_group(tied, i + 1)
      end
      return
    end
  end
end

function M.annotate(items, limit)
  hints = setmetatable({}, { __mode = "k" })
  local icons = require("lunavim.config.icons").kinds
  local groups = {}
  for i = 1, math.min(limit or #items, #items) do
    local item = items[i]
    if item.source_id == "lsp" then
      -- Blink's label component already displays labelDetails.detail; the
      -- description and kind icon in the normal menu disambiguate many rows.
      local d = table_field(item.labelDetails)
      local kind = item.kind_name or kinds[item.kind] or ""
      local key = table.concat({ vim.trim(item.label), string_field(d.detail), string_field(d.description), item.kind_icon or icons[kind] or kind }, "\0")
      if not groups[key] then
        groups[key] = {}
      end
      table.insert(groups[key], item)
    end
  end
  for _, group in pairs(groups) do
    annotate_group(group, 1)
  end
  return items
end

function M.description(ctx)
  local hint = hints[ctx.item]
  local original = ctx.label_description or ""
  if not hint or hint == original then
    return original
  end
  return original ~= "" and hint .. " · " .. original or hint
end

return M
