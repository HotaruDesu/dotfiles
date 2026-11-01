local syntax = require "lunavim.plugins.lsp.signature.syntax"
local M = {}
local classify = syntax.classify

local function pos_le(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col <= b_col)
end

local function contains(range, row, col)
  return pos_le(range[1], range[2], row, col) and pos_le(row, col, range[3], range[4])
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

-- One discovery operation owns its requests, event listeners and deadline.
-- Closing it first makes cancellation callbacks and late LSP replies harmless.
local active
local next_operation = 0
local group = vim.api.nvim_create_augroup("LunaVimSignatureRequests", { clear = true })

local function finish(operation)
  if operation.finished then
    return
  end
  operation.finished = true
  if active == operation then
    active = nil
  end
  for _, autocmd in ipairs(operation.autocmds) do
    pcall(vim.api.nvim_del_autocmd, autocmd)
  end
  if operation.timer then
    operation.timer:stop()
    operation.timer:close()
  end
  for _, request_id in pairs(operation.requests) do
    pcall(operation.client.cancel_request, operation.client, request_id)
  end
end

function M.cancel()
  if active then
    finish(active)
  end
end

---@class LunaSignatureState
---@field declaration LunaSignatureTarget
---@field definition LunaSignatureTarget
---@field references table[]
---@field encoding string

---@param client vim.lsp.Client
---@param current LunaSignatureTarget
---@param callback fun(state: LunaSignatureState?, err: string?)
---@param options? { timeout_ms?: integer }
function M.discover(client, current, callback, options)
  M.cancel()
  next_operation = next_operation + 1
  local operation = {
    id = next_operation,
    client = client,
    requests = {},
    autocmds = {},
    finished = false,
  }
  active = operation
  local bufnr = current.bufnr
  local source_win = vim.api.nvim_get_current_win()
  local pending = 3
  local results = {}
  local methods = {
    { "declaration", "textDocument/declaration" },
    { "definition", "textDocument/definition" },
    { "references", "textDocument/references" },
  }
  local function valid()
    return active == operation
      and not operation.finished
      and vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_get_changedtick(bufnr) == current.changedtick
      and vim.api.nvim_get_current_buf() == bufnr
      and vim.api.nvim_get_current_win() == source_win
  end
  local function complete(state, err)
    if operation.finished then
      return
    end
    finish(operation)
    callback(state, err)
  end
  operation.timer = assert(vim.uv.new_timer())
  operation.timer:start(
    (options and options.timeout_ms) or 10000,
    0,
    vim.schedule_wrap(function()
      if active == operation and not operation.finished then
        complete(nil, "clangd timed out while locating signature targets")
      end
    end)
  )
  operation.autocmds[1] = vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      finish(operation)
    end,
  })
  operation.autocmds[2] = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if active == operation and vim.api.nvim_buf_get_changedtick(bufnr) ~= current.changedtick then
        complete(nil, "The current buffer changed while clangd was locating targets; the operation was aborted")
      end
    end,
  })
  local position = vim.lsp.util.make_position_params(source_win, client.offset_encoding)
  for _, method in ipairs(methods) do
    if operation.finished then
      break
    end
    local key, name = unpack(method)
    local params = vim.deepcopy(position)
    if key == "references" then
      params.context = { includeDeclaration = true }
    end
    local responded = false
    local sent, request_id = client:request(name, params, function(err, result)
      responded = true
      if active ~= operation or operation.finished then
        return
      end
      operation.requests[key] = nil
      if not valid() then
        complete(nil, "The current buffer or window changed while clangd was locating targets; the operation was aborted")
        return
      end
      if err then
        complete(nil, ("clangd %s request failed: %s"):format(key, err.message or tostring(err)))
        return
      end
      results[key] = result
      pending = pending - 1
      if pending == 0 then
        local ok, state, target_err = pcall(choose_targets, current, results, client.offset_encoding)
        if not ok then
          complete(nil, "Could not parse clangd signature targets: " .. tostring(state))
        else
          complete(state, target_err)
        end
      end
    end, bufnr)
    if not sent then
      complete(nil, ("Could not send the %s request to clangd"):format(key))
    elseif not operation.finished and not responded then
      operation.requests[key] = request_id
    end
  end
  return operation.id
end

M.choose_targets = choose_targets
M.location_parts = location_parts
M.lsp_col_to_byte = lsp_col_to_byte
M.byte_col_to_lsp = byte_col_to_lsp
M.location_is_target = location_is_target
return M
