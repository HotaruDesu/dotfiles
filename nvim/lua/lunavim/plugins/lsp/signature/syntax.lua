---@class LunaSignatureParameter
---@field name string
---@field type string
---@field text string

---@class LunaSignatureTarget
---@field bufnr integer
---@field uri string
---@field kind "declaration"|"definition"
---@field name string
---@field name_text string
---@field parameters LunaSignatureParameter[]
---@field signature string
---@field outer_range integer[]
---@field edit_range integer[]
---@field changedtick integer

local DECL_ONLY_PREFIX = { "static", "virtual", "explicit", "friend" }
local DECL_ONLY_SUFFIX = { "override", "final" }
local REJECTED_VIRTUAL = { "virtual", "override", "final" }

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lines(text)
  return vim.split(text, "\n", { plain = true })
end

local function node_text(node, source)
  return vim.treesitter.get_node_text(node, source)
end

local function source_text(source)
  if type(source) == "number" then
    return table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), "\n")
  end
  return source
end

local function find_descendant(node, wanted)
  if wanted[node:type()] then
    return node
  end
  for child in node:iter_children() do
    local found = find_descendant(child, wanted)
    if found then
      return found
    end
  end
end

local function find_parameter_name(node, source)
  local declarator = node:field("declarator")[1]
  if not declarator then
    return ""
  end
  local name = find_descendant(declarator, {
    identifier = true,
    field_identifier = true,
  })
  return name and node_text(name, source) or ""
end

local function function_name_node(declarator)
  local node = declarator:field("declarator")[1]
  while node do
    local kind = node:type()
    if kind == "qualified_identifier" then
      node = node:field("name")[1]
    elseif kind == "pointer_declarator" or kind == "reference_declarator" or kind == "parenthesized_declarator" then
      node = node:field("declarator")[1]
    else
      break
    end
  end
  if not node then
    return nil
  end
  if node:type() == "destructor_name" then
    return node
  end
  if node:type() == "identifier" or node:type() == "field_identifier" or node:type() == "operator_name" or node:type() == "conversion_operator_name" then
    return node
  end
end

local function byte_offset(text, row, col)
  local offset = 0
  local row_index = 0
  for line in (text .. "\n"):gmatch "(.-)\n" do
    if row_index == row then
      return offset + col
    end
    offset = offset + #line + 1
    row_index = row_index + 1
  end
  return #text
end

local function slice(text, start_row, start_col, end_row, end_col)
  local first = byte_offset(text, start_row, start_col)
  local last = byte_offset(text, end_row, end_col)
  return text:sub(first + 1, last)
end

local function signature_outer(declarator)
  local node = declarator
  while node do
    local kind = node:type()
    if kind == "function_definition" or kind == "declaration" or kind == "field_declaration" then
      return node
    end
    if kind == "call_expression" or kind == "compound_statement" or kind == "lambda_expression" then
      return nil
    end
    node = node:parent()
  end
end

local function enclosing_function(node)
  while node do
    if node:type() == "function_declarator" then
      local outer = signature_outer(node)
      if outer then
        return node, outer
      end
      return nil
    end
    local kind = node:type()
    if kind == "call_expression" or kind == "compound_statement" or kind == "lambda_expression" then
      return nil
    end
    node = node:parent()
  end
end

local function has_ancestor(node, kinds)
  node = node:parent()
  while node do
    if kinds[node:type()] then
      return true
    end
    node = node:parent()
  end
  return false
end

local function word_present(text, word)
  return text:find("%f[%w_]" .. word .. "%f[^%w_]") ~= nil
end

local function remove_words(text, words)
  for _, word in ipairs(words) do
    text = text:gsub("%f[%w_]" .. word .. "%f[^%w_]", "")
  end
  text = text:gsub("[ \t]+", " ")
  text = text:gsub("[ \t]+\n", "\n")
  text = text:gsub("\n[ \t]+", "\n")
  return text
end

local function parameter_nodes(parameters)
  local result = {}
  for child in parameters:iter_children() do
    local kind = child:type()
    if kind == "parameter_declaration" or kind == "optional_parameter_declaration" then
      result[#result + 1] = child
    end
  end
  return result
end

local function strip_parameter_default(text, parameter, source)
  source = source_text(source)
  local default = parameter:field("default_value")[1]
  if not default then
    return text
  end
  local psr, psc = parameter:range()
  local dsr, dsc, der, dec = default:range()
  local before_default = slice(source, psr, psc, dsr, dsc)
  local equals = before_default:match "()%s*=%s*$"
  if not equals then
    return text
  end
  local remove_start = equals - 1
  local remove_end = byte_offset(source, der, dec) - byte_offset(source, psr, psc)
  return text:sub(1, remove_start) .. text:sub(remove_end + 1):gsub("^%s+", "")
end

local function parameters_without_defaults(parameters, source)
  source = source_text(source)
  local text = node_text(parameters, source)
  local psr, psc = parameters:range()
  local base = byte_offset(source, psr, psc)
  local removals = {}
  for _, parameter in ipairs(parameter_nodes(parameters)) do
    local default = parameter:field("default_value")[1]
    if default then
      local parameter_row, parameter_col = parameter:range()
      local default_row, default_col, default_end_row, default_end_col = default:range()
      local before_default = slice(source, parameter_row, parameter_col, default_row, default_col)
      local equals = before_default:match "()%s*=%s*$"
      if equals then
        removals[#removals + 1] = {
          byte_offset(source, parameter_row, parameter_col) - base + equals - 1,
          byte_offset(source, default_end_row, default_end_col) - base,
        }
      end
    end
  end
  table.sort(removals, function(a, b)
    return a[1] > b[1]
  end)
  for _, removal in ipairs(removals) do
    text = text:sub(1, removal[1]) .. text:sub(removal[2] + 1)
  end
  return text
end

local function parameter_info(parameters, source)
  local plain_source = source_text(source)
  local result = {}
  for _, parameter in ipairs(parameter_nodes(parameters)) do
    local text = strip_parameter_default(node_text(parameter, source), parameter, plain_source)
    local name = find_parameter_name(parameter, source)
    local type_text = text
    if name ~= "" then
      type_text = type_text:gsub("%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]", "", 1)
    end
    result[#result + 1] = {
      name = name,
      type = type_text:gsub("%s+", ""),
      text = trim(text),
    }
  end
  return result
end

local function classify(bufnr, row, byte_col)
  vim.treesitter.language.add "cpp"
  local parser = vim.treesitter.get_parser(bufnr, "cpp")
  local tree = parser:parse()[1]
  local root = tree:root()
  local node = root:named_descendant_for_range(row, byte_col, row, byte_col)
  local declarator, outer = enclosing_function(node)
  if not declarator then
    return nil, "The cursor must be on a C++ function declaration or definition"
  end
  local name_node = function_name_node(declarator)
  local parameters = declarator:field("parameters")[1]
  if not name_node or not parameters then
    return nil, "This function declaration form is not supported"
  end
  local name = node_text(name_node, bufnr)
  local declared_name = declarator:field("declarator")[1]
  if name:find("operator", 1, true) or find_descendant(name_node, {
    operator_name = true,
    conversion_operator_name = true,
  }) then
    return nil, "Operator overloads are not supported"
  end
  if has_ancestor(outer, { template_declaration = true }) then
    return nil, "Function templates and explicit specializations are not supported"
  end
  local signature_end = declarator
  local kind = outer:type() == "function_definition" and "definition" or "declaration"
  local body = outer:field("body")[1]
  local sr, sc = outer:range()
  local _, _, er, ec = signature_end:range()
  local signature = vim.api.nvim_buf_get_text(bufnr, sr, sc, er, ec, {})
  signature = table.concat(signature, "\n")
  local _, _, outer_er, outer_ec = outer:range()
  local outer_range = { sr, sc, outer_er, outer_ec }
  local edit_range = { sr, sc, er, ec }
  if kind == "definition" and body then
    local br, bc = body:range()
    edit_range = { sr, sc, br, bc }
  end
  local whole = table.concat(vim.api.nvim_buf_get_text(bufnr, sr, sc, outer_er, outer_ec, {}), "\n")
  if whole:match "^%s*#" or has_ancestor(outer, {
    preproc_call = true,
    preproc_function_def = true,
    preproc_def = true,
  }) then
    return nil, "Macro-generated functions are not supported"
  end
  if whole:match "template%s*<" then
    return nil, "Function templates and explicit specializations are not supported"
  end
  for _, word in ipairs(REJECTED_VIRTUAL) do
    if word_present(signature, word) then
      return nil, "Virtual function hierarchies are not propagated; update the full hierarchy manually"
    end
  end
  return {
    bufnr = bufnr,
    uri = vim.uri_from_bufnr(bufnr),
    kind = kind,
    name = name,
    name_text = declared_name and node_text(declared_name, bufnr) or name,
    parameters = parameter_info(parameters, bufnr),
    signature = trim(signature),
    outer_range = outer_range,
    edit_range = edit_range,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
  }
end

local function parse_edited(text, expected_name)
  text = trim(text)
  text = text:gsub(";%s*$", "")
  if text == "" then
    return nil, "The signature cannot be empty"
  end
  if text:find "[{}]" then
    return nil, "Enter a signature without a function body"
  end
  local class_name = expected_name:gsub("^~", "")
  if class_name == "" or not class_name:match "^[%a_][%w_]*$" then
    class_name = "LunaSignatureHost"
  end
  local prefix = "class " .. class_name .. " {\n"
  local source = prefix .. text .. ";\n};"
  local parser = vim.treesitter.get_string_parser(source, "cpp")
  local root = parser:parse()[1]:root()
  if root:has_error() then
    return nil, "The signature is not a valid C++ declaration"
  end
  -- Parsing only the first function silently accepts a second declaration or
  -- field. Require one declaration in the wrapper, allowing comments around it.
  local host = root:named_child(0)
  local body = host and host:field("body")[1]
  local declaration
  if body then
    for child in body:iter_children() do
      local kind = child:type()
      if kind == "field_declaration" or kind == "declaration" then
        if declaration then
          return nil, "Enter exactly one function declaration"
        end
        declaration = child
      elseif kind ~= "{" and kind ~= "}" and kind ~= "comment" then
        return nil, "Enter exactly one function declaration"
      end
    end
  end
  if not declaration or #declaration:field "declarator" ~= 1 then
    return nil, "Enter exactly one function declaration"
  end
  local declarator = find_descendant(declaration, { function_declarator = true })
  if not declarator then
    return nil, "No function declaration was found"
  end
  local outer = signature_outer(declarator)
  local name_node = function_name_node(declarator)
  local parameters = declarator:field("parameters")[1]
  if not outer or not name_node or not parameters then
    return nil, "This function declaration form is not supported"
  end
  local name = node_text(name_node, source)
  if name ~= expected_name then
    return nil, "Function names cannot be changed here; use vim.lsp.buf.rename()"
  end
  if name:find("operator", 1, true) then
    return nil, "Operator overloads are not supported"
  end
  for _, word in ipairs(REJECTED_VIRTUAL) do
    if word_present(text, word) then
      return nil, "Virtual function hierarchies are not propagated; update the full hierarchy manually"
    end
  end
  local sr, sc = outer:range()
  local _, _, er, ec = declarator:range()
  local nsr, nsc, ner, nec = name_node:range()
  local _, _, per, pec = parameters:range()
  return {
    text = text,
    name = name,
    parameters = parameter_info(parameters, source),
    prefix = slice(source, sr, sc, nsr, nsc),
    params_without_defaults = parameters_without_defaults(parameters, source),
    suffix_after_params = slice(source, per, pec, er, ec),
    name_suffix = slice(source, ner, nec, er, ec),
  }
end

local function name_counts(parameters)
  local counts = {}
  for _, parameter in ipairs(parameters) do
    if parameter.name ~= "" then
      counts[parameter.name] = (counts[parameter.name] or 0) + 1
    end
  end
  return counts
end

local function same_counts(a, b)
  for key, value in pairs(a) do
    if b[key] ~= value then
      return false
    end
  end
  for key, value in pairs(b) do
    if a[key] ~= value then
      return false
    end
  end
  return true
end

local function validate_parameter_names(old, new)
  if #old == #new and not same_counts(name_counts(old), name_counts(new)) then
    return false, "Existing parameter names cannot be changed here; use vim.lsp.buf.rename()"
  end
  local old_by_name = {}
  local new_by_name = {}
  for _, parameter in ipairs(old) do
    if parameter.name ~= "" then
      old_by_name[parameter.name] = true
    end
  end
  for _, parameter in ipairs(new) do
    if parameter.name ~= "" then
      new_by_name[parameter.name] = true
    end
  end
  if #old ~= #new then
    for _, old_parameter in ipairs(old) do
      if old_parameter.name ~= "" and not new_by_name[old_parameter.name] then
        for _, new_parameter in ipairs(new) do
          if new_parameter.name ~= "" and not old_by_name[new_parameter.name] and old_parameter.type == new_parameter.type then
            return false, "A possible parameter rename was detected; use vim.lsp.buf.rename() first"
          end
        end
      end
    end
  end
  return true
end

local function source_parameters(edited, declaration, definition)
  if not declaration or not definition then
    return edited.params_without_defaults
  end
  local replacements = {}
  for index, old_parameter in ipairs(declaration.parameters) do
    local definition_parameter = definition.parameters[index]
    if old_parameter.name ~= "" and definition_parameter and definition_parameter.name ~= "" and old_parameter.name ~= definition_parameter.name then
      replacements[old_parameter.name] = definition_parameter.name
    end
  end
  if vim.tbl_isempty(replacements) then
    return edited.params_without_defaults
  end
  local result = {}
  for _, parameter in ipairs(edited.parameters) do
    local text = parameter.text
    local replacement = replacements[parameter.name]
    if replacement then
      local start = 1
      local last_start, last_end
      while true do
        local found_start, found_end = text:find("%f[%w_]" .. vim.pesc(parameter.name) .. "%f[^%w_]", start)
        if not found_start then
          break
        end
        last_start, last_end = found_start, found_end
        start = found_end + 1
      end
      if last_start then
        text = text:sub(1, last_start - 1) .. replacement .. text:sub(last_end + 1)
      end
    end
    result[#result + 1] = text
  end
  return "(" .. table.concat(result, ", ") .. ")"
end

local function build_source_signature(edited, definition, declaration)
  local prefix = remove_words(edited.prefix, DECL_ONLY_PREFIX)
  local suffix = remove_words(edited.suffix_after_params, DECL_ONLY_SUFFIX)
  return trim(prefix .. definition.name_text .. source_parameters(edited, declaration, definition) .. suffix)
end

return {
  trim = trim,
  lines = lines,
  classify = classify,
  parse_edited = parse_edited,
  validate_parameter_names = validate_parameter_names,
  build_source_signature = build_source_signature,
}
