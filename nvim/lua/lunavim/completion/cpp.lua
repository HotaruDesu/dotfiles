-- clangd normally supplies these keywords. Fill gaps only when the unfinished
-- identifier is in a recognizable C++ declaration or expression.
local M = {}

function M.new()
  return M
end

local expression_parent = {
  return_statement = true,
  co_return_statement = true,
  argument_list = true,
  condition_clause = true,
  parenthesized_expression = true,
  binary_expression = true,
  assignment_expression = true,
}
local access_specifier = { public = true, private = true, protected = true }

function M.keyword(ctx)
  local prefix = ctx.line:sub(ctx.bounds.start_col, ctx.cursor[2])
  if not vim.startswith(prefix, "sta") or not vim.startswith("static_cast", prefix) then
    return
  end
  local row, col = ctx.cursor[1] - 1, ctx.bounds.start_col - 1
  local parser = vim.treesitter.get_parser(ctx.bufnr, "cpp", { error = false })
  if not parser then
    return
  end
  parser:parse { row, row + 1 }
  local node = parser:named_node_for_range({ row, col, row, col }, { ignore_injections = true })
  if not node or (node:type() ~= "identifier" and node:type() ~= "type_identifier") then
    return
  end
  local parent = node:parent()
  if not parent then
    return
  end
  local kind = parent:type()
  local before = vim.trim(ctx.line:sub(1, col))
  if kind == "initializer_list" then
    -- With only a partial first statement, Tree-sitter can parse a function
    -- body as a braced initializer on its function declarator.
    local init = parent:parent()
    local declarator = init and init:field("declarator")[1]
    if declarator and declarator:type() == "function_declarator" then
      return vim.startswith("static", prefix) and "static" or nil
    end
    return "static_cast"
  end
  if expression_parent[kind] or (kind == "init_declarator" and parent:field("value")[1] == node) then
    return "static_cast"
  elseif kind == "expression_statement" or kind == "field_declaration" or kind == "ERROR" then
    local at_start = before == "" or before:match "[;{}]$" or access_specifier[before:match "([%a]+)%s*:$"]
    if at_start and vim.startswith("static", prefix) then
      return "static"
    end
  end
end

function M:get_completions(ctx, callback)
  local label = M.keyword(ctx)
  local items = {}
  if label then
    local item = { label = label, kind = vim.lsp.protocol.CompletionItemKind.Keyword }
    if label == "static_cast" then
      item.insertText = "static_cast<${1:type}>(${2:expr})$0"
      item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
    end
    items[1] = item
  end
  callback { items = items, is_incomplete_forward = true, is_incomplete_backward = true }
end

return M
