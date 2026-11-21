local M = {}
local kinds = vim.lsp.protocol.CompletionItemKind

-- Use Blink's acceptance range, including cursor movement since the request,
-- insert/replace selection and the client's offset encoding.
local function project(item, line, row, start)
  if item.kind ~= kinds.File and item.kind ~= kinds.Folder then
    return
  end
  if
    type(item.textEdit) ~= "table"
    or type(item.textEdit.newText) ~= "string"
    or not (item.textEdit.range or item.textEdit.insert or item.textEdit.replace)
    or type(item.cursor_column) ~= "number"
    or item.insertTextFormat == 2
    or item.command
    or (item.additionalTextEdits and not vim.deep_equal(item.additionalTextEdits, {}))
  then
    return
  end
  local edit = require("blink.cmp.lib.text_edits").get_from_item(item)
  local first, last = edit.range.start, edit.range["end"]
  if first.line ~= row or last.line ~= row or first.character < start - 1 or edit.newText:find "[\r\n]" then
    return
  end
  local left = line:sub(1, first.character) .. edit.newText
  local right = line:sub(last.character + 1)
  return left .. right, left, right
end

local function key(kind, line, caret, stop)
  -- The cursor may finish on either side of the closing delimiter.
  if caret == stop then
    caret = caret - 1
  end
  return kind .. ":" .. caret .. ":" .. line
end

local function add(index, key, item)
  index[key] = index[key] or {}
  table.insert(index[key], item)
end

function M.shadowed(ctx, items, ranks, selected, full)
  local hidden = {}
  local line, cursor = ctx.get_line(), ctx.get_cursor()
  local opening, start = line:sub(1, cursor[2]):match '^%s*#%s*include%s*([<"])()[^>"]*$'
  if not start or ctx.bufnr ~= vim.api.nvim_get_current_buf() then
    return hidden
  end
  if opening == "<" and line:sub(start, start) ~= "/" then
    return hidden
  end
  local closing = opening == "<" and ">" or '"'
  local buffer_name = vim.api.nvim_buf_get_name(ctx.bufnr)
  local dir = buffer_name ~= "" and vim.fs.dirname(buffer_name)
  local exact, completed = {}, {}
  for i, item in ipairs(items) do
    if ranks[i] and item.source_id == "path" and type(item.data) == "table" and type(item.data.full_path) == "string" then
      local result, left, right = project(item, line, cursor[1] - 1, start)
      if result then
        local stop = result:find(closing, start, true)
        local name = stop and result:sub(start, stop - 1) or left:sub(start)
        -- Relative quoted includes search the editing file's directory first.
        -- A relative angle include may resolve to a different include root.
        local path = name:sub(1, 1) == "/" and name or opening == '"' and dir and vim.fs.joinpath(dir, name)
        if path and vim.fs.normalize(path, { expand_env = false }) == vim.fs.normalize(item.data.full_path, { expand_env = false }) then
          add(exact, key(item.kind, result, #left, stop), item)
          if not full and not stop and item.kind == kinds.File and right:match "^%s*$" then
            add(completed, key(item.kind, left .. closing, #left), item)
          end
        end
      end
    end
  end
  if not next(exact) then
    return hidden
  end
  local alternatives = {}
  local unresolved = {}
  for i, item in ipairs(items) do
    if item.source_id == "lsp" and item.client_id and unresolved[item.client_id] == nil then
      local client = vim.lsp.get_client_by_id(item.client_id)
      unresolved[item.client_id] = client and client:supports_method("completionItem/resolve", ctx.bufnr) or false
    end
    if ranks[i] and item.source_id == "lsp" and not item.data and not unresolved[item.client_id] then
      local result, left = project(item, line, cursor[1] - 1, start)
      if result then
        local stop = result:find(closing, start, true)
        local matches = exact[key(item.kind, result, #left, stop)] or completed[key(item.kind, result:gsub("%s+$", ""), #left, stop)]
        for _, path in ipairs(matches or {}) do
          if path == selected then
            table.insert(alternatives, item)
          else
            hidden[path] = true
          end
        end
      end
    end
  end
  -- Leave competing LSP candidates alone when the selected path is ambiguous.
  if #alternatives == 1 then
    hidden[alternatives[1]] = true
  end
  return hidden
end

return M
