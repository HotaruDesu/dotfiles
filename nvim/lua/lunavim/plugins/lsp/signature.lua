local M = {}

local TITLE = "C++ Change Signature"
local DECL_ONLY_PREFIX = { "static", "virtual", "explicit", "friend" }
local DECL_ONLY_SUFFIX = { "override", "final" }
local REJECTED_VIRTUAL = { "virtual", "override", "final" }

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = TITLE })
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lines(text)
  return vim.split(text, "\n", { plain = true })
end

local function pos_le(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col <= b_col)
end

local function contains(range, row, col)
  return pos_le(range[1], range[2], row, col) and pos_le(row, col, range[3], range[4])
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

local function first_function_declarator(root)
  return find_descendant(root, { function_declarator = true })
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
  local declarator = first_function_declarator(root)
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
  local psr, psc, per, pec = parameters:range()
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

local function location_parts(location)
  if location.targetUri then
    return location.targetUri, location.targetSelectionRange or location.targetRange
  end
  return location.uri, location.range
end

local function flatten_locations(result)
  if not result then
    return {}
  end
  if result.uri or result.targetUri then
    return { result }
  end
  return result
end

local function lsp_col_to_byte(bufnr, row, character, encoding)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return vim.str_byteindex(line, encoding, character, false)
end

local function byte_col_to_lsp(bufnr, row, byte_col, encoding)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return vim.str_utfindex(line, encoding, byte_col, false)
end

local function parse_location(location, encoding)
  local uri, range = location_parts(location)
  if not uri or not range then
    return nil
  end
  local bufnr = vim.uri_to_bufnr(uri)
  vim.fn.bufload(bufnr)
  if vim.bo[bufnr].filetype == "" then
    vim.bo[bufnr].filetype = "cpp"
  end
  local ok, parsed, err = pcall(classify, bufnr, range.start.line, lsp_col_to_byte(bufnr, range.start.line, range.start.character, encoding))
  if not ok then
    return nil
  end
  return parsed, err
end

local function target_key(target)
  return table.concat({ target.uri, target.outer_range[1], target.outer_range[2], target.outer_range[3], target.outer_range[4] }, ":")
end

local function location_is_target(location, target, encoding)
  local uri, range = location_parts(location)
  if uri ~= target.uri then
    return false
  end
  local row = range.start.line
  local col = lsp_col_to_byte(target.bufnr, row, range.start.character, encoding)
  return contains(target.outer_range, row, col)
end

local function current_ticks_match(state)
  for _, target in ipairs { state.declaration, state.definition } do
    if not vim.api.nvim_buf_is_valid(target.bufnr) or vim.api.nvim_buf_get_changedtick(target.bufnr) ~= target.changedtick then
      return false
    end
  end
  return true
end

local function close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function floating_window(bufnr, opts)
  local width = math.min(opts.width or 100, math.max(40, vim.o.columns - 8))
  local height = math.min(opts.height or 12, math.max(3, vim.o.lines - 8))
  return vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = opts.title,
    title_pos = "center",
  })
end

local function target_label(target)
  local name = vim.api.nvim_buf_get_name(target.bufnr)
  return name ~= "" and vim.fn.fnamemodify(name, ":~:.") or target.uri
end

local function replacement_texts(state, edited)
  return edited.text, build_source_signature(edited, state.definition, state.declaration) .. " "
end

local function unified_diff(label, before, after)
  local diff = vim.diff(before .. "\n", after .. "\n", {
    result_type = "unified",
    ctxlen = 3,
  })
  if diff == "" then
    diff = "(no changes)\n"
  end
  return ("--- %s\n+++ %s\n%s"):format(label .. " (before)", label .. " (after)", diff)
end

local function lsp_range(target, encoding)
  local range = target.edit_range
  return {
    start = {
      line = range[1],
      character = byte_col_to_lsp(target.bufnr, range[1], range[2], encoding),
    },
    ["end"] = {
      line = range[3],
      character = byte_col_to_lsp(target.bufnr, range[3], range[4], encoding),
    },
  }
end

local function quickfix_items(state)
  local items = {}
  local seen = {}
  for _, location in ipairs(state.references) do
    if not location_is_target(location, state.declaration, state.encoding) and not location_is_target(location, state.definition, state.encoding) then
      local uri, range = location_parts(location)
      local key = uri .. ":" .. range.start.line .. ":" .. range.start.character
      if not seen[key] then
        seen[key] = true
        local bufnr = vim.uri_to_bufnr(uri)
        vim.fn.bufload(bufnr)
        local byte_col = lsp_col_to_byte(bufnr, range.start.line, range.start.character, state.encoding)
        items[#items + 1] = {
          bufnr = bufnr,
          lnum = range.start.line + 1,
          col = byte_col + 1,
          text = "Update call for changed signature",
        }
      end
    end
  end
  return items
end

local function apply_changes(state, declaration_text, definition_text, preview_win, edit_win)
  if not current_ticks_match(state) then
    close_window(preview_win)
    close_window(edit_win)
    notify("The declaration or definition changed during preview; apply was aborted", vim.log.levels.ERROR)
    return
  end
  local items = quickfix_items(state)
  local edit = { changes = {} }
  edit.changes[state.declaration.uri] = {
    { range = lsp_range(state.declaration, state.encoding), newText = declaration_text },
  }
  edit.changes[state.definition.uri] = {
    { range = lsp_range(state.definition, state.encoding), newText = definition_text },
  }
  local ok, err = pcall(vim.lsp.util.apply_workspace_edit, edit, state.encoding)
  if not ok then
    notify("Failed to apply the signature change: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  close_window(preview_win)
  close_window(edit_win)
  vim.fn.setqflist({}, " ", {
    title = "C++ signature call sites",
    items = items,
  })
  if #items > 0 then
    vim.cmd "copen"
  end
  notify(("Synchronized declaration and definition; added %d original call sites to quickfix (files remain unsaved)"):format(#items))
end

local function preview(state, edit_buf, edit_win)
  if not current_ticks_match(state) then
    close_window(edit_win)
    notify("The declaration or definition changed during editing; the operation was aborted", vim.log.levels.ERROR)
    return
  end
  local edited_text = table.concat(vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false), "\n")
  local edited, err = parse_edited(edited_text, state.declaration.name)
  if not edited then
    notify(err, vim.log.levels.ERROR)
    return
  end
  local valid, name_err = validate_parameter_names(state.declaration.parameters, edited.parameters)
  if not valid then
    notify(name_err, vim.log.levels.ERROR)
    return
  end
  local declaration_text, definition_text = replacement_texts(state, edited)
  local preview_buf = vim.api.nvim_create_buf(false, true)
  local content = unified_diff(target_label(state.declaration), state.declaration.signature, declaration_text)
    .. "\n"
    .. unified_diff(target_label(state.definition), trim(state.definition.signature), trim(definition_text))
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines(content))
  vim.bo[preview_buf].buftype = "nofile"
  vim.bo[preview_buf].bufhidden = "wipe"
  vim.bo[preview_buf].swapfile = false
  vim.bo[preview_buf].modifiable = false
  vim.bo[preview_buf].filetype = "diff"
  local preview_win = floating_window(preview_buf, {
    width = math.floor(vim.o.columns * 0.82),
    height = math.floor(vim.o.lines * 0.72),
    title = " Signature Diff | y apply | e edit | q cancel ",
  })
  local function cancel()
    close_window(preview_win)
    close_window(edit_win)
    notify "Signature change cancelled"
  end
  vim.keymap.set("n", "y", function()
    apply_changes(state, declaration_text, definition_text, preview_win, edit_win)
  end, { buffer = preview_buf, nowait = true, silent = true })
  vim.keymap.set("n", "e", function()
    close_window(preview_win)
    if vim.api.nvim_win_is_valid(edit_win) then
      vim.api.nvim_set_current_win(edit_win)
    end
  end, { buffer = preview_buf, nowait = true, silent = true })
  for _, key in ipairs { "q", "<Esc>" } do
    vim.keymap.set("n", key, cancel, { buffer = preview_buf, nowait = true, silent = true })
  end
end

local function open_editor(state)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines(state.declaration.signature))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "cpp"
  local height = math.max(3, math.min(16, vim.api.nvim_buf_line_count(buf) + 2))
  local win = floating_window(buf, {
    width = math.floor(vim.o.columns * 0.75),
    height = height,
    title = " Edit Signature | <C-s> preview | Esc cancel ",
  })
  vim.wo[win].wrap = false
  vim.cmd "startinsert"
  local function cancel()
    close_window(win)
    notify "Signature change cancelled"
  end
  local function show_preview()
    vim.cmd "stopinsert"
    preview(state, buf, win)
  end
  vim.keymap.set({ "n", "i" }, "<C-s>", show_preview, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "q", cancel, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ "n", "i" }, "<Esc>", cancel, { buffer = buf, nowait = true, silent = true })
end

local function choose_targets(current, results, encoding)
  local candidates = {}
  local declaration_locations = flatten_locations(results.declaration)
  local definition_locations = flatten_locations(results.definition)
  local reference_locations = flatten_locations(results.references)
  for _, group in ipairs { declaration_locations, definition_locations, reference_locations } do
    for _, location in ipairs(group) do
      local target = parse_location(location, encoding)
      if target and target.name == current.name and #target.parameters == #current.parameters then
        candidates[target_key(target)] = target
      end
    end
  end
  candidates[target_key(current)] = current
  local declarations, definitions = {}, {}
  for _, target in pairs(candidates) do
    if target.kind == "definition" then
      definitions[#definitions + 1] = target
    else
      declarations[#declarations + 1] = target
    end
  end
  if #declarations == 0 and #definitions == 1 and target_key(current) == target_key(definitions[1]) then
    return nil, "This inline function has only one definition; cross-file synchronization is unnecessary"
  end
  if #declarations ~= 1 or #definitions ~= 1 then
    return nil, ("Expected one distinct declaration and definition; found %d declarations and %d definitions"):format(#declarations, #definitions)
  end
  if declarations[1].uri == definitions[1].uri and target_key(declarations[1]) == target_key(definitions[1]) then
    return nil, "This inline function has only one definition; cross-file synchronization is unnecessary"
  end
  return {
    declaration = declarations[1],
    definition = definitions[1],
    references = reference_locations,
    encoding = encoding,
  }
end

local function request_targets(client, bufnr, current, start_tick)
  local methods = {
    declaration = "textDocument/declaration",
    definition = "textDocument/definition",
    references = "textDocument/references",
  }
  local pending = 3
  local results = {}
  local failed
  local position = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local function complete()
    pending = pending - 1
    if pending > 0 then
      return
    end
    if failed then
      notify(failed, vim.log.levels.ERROR)
      return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_buf_get_changedtick(bufnr) ~= start_tick then
      notify("The current buffer changed while clangd was locating targets; the operation was aborted", vim.log.levels.ERROR)
      return
    end
    local state, err = choose_targets(current, results, client.offset_encoding)
    if not state then
      notify(err, vim.log.levels.ERROR)
      return
    end
    open_editor(state)
  end
  for key, method in pairs(methods) do
    local params = vim.deepcopy(position)
    if key == "references" then
      params.context = { includeDeclaration = true }
    end
    local ok = client:request(method, params, function(err, result)
      if err then
        failed = ("clangd %s request failed: %s"):format(key, err.message or tostring(err))
      else
        results[key] = result
      end
      complete()
    end, bufnr)
    if not ok then
      failed = ("Could not send the %s request to clangd"):format(key)
      complete()
    end
  end
end

function M.change_signature()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "cpp" then
    notify("CppChangeSignature only supports C++ buffers", vim.log.levels.ERROR)
    return
  end
  local clients = vim.lsp.get_clients { bufnr = bufnr, name = "clangd" }
  if #clients ~= 1 then
    notify(#clients == 0 and "No clangd client is attached to the current buffer" or "Multiple clangd clients are attached; the target is ambiguous", vim.log.levels.ERROR)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local ok, current, err = pcall(classify, bufnr, cursor[1] - 1, cursor[2])
  if not ok then
    notify("Could not parse the current C++ syntax tree: " .. tostring(current), vim.log.levels.ERROR)
    return
  end
  if not current then
    notify(err, vim.log.levels.ERROR)
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  request_targets(clients[1], bufnr, current, tick)
end

function M.setup()
  vim.api.nvim_create_user_command("CppChangeSignature", M.change_signature, {
    desc = "Synchronize a C++ function declaration and definition",
    force = true,
  })
end

M._test = {
  parse_edited = parse_edited,
  build_source_signature = build_source_signature,
  validate_parameter_names = validate_parameter_names,
  classify = classify,
  current_ticks_match = current_ticks_match,
  choose_targets = choose_targets,
  replacement_texts = replacement_texts,
  lsp_range = lsp_range,
  quickfix_items = quickfix_items,
}

return M
