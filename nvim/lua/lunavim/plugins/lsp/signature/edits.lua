local syntax = require "lunavim.plugins.lsp.signature.syntax"
local targets = require "lunavim.plugins.lsp.signature.targets"
local M = {}
local byte_col_to_lsp = targets.byte_col_to_lsp
local lsp_col_to_byte = targets.lsp_col_to_byte
local location_parts = targets.location_parts
local location_is_target = targets.location_is_target
local build_source_signature = syntax.build_source_signature

local function current_ticks_match(state)
  for _, target in ipairs { state.declaration, state.definition } do
    if not vim.api.nvim_buf_is_valid(target.bufnr) or vim.api.nvim_buf_get_changedtick(target.bufnr) ~= target.changedtick then
      return false
    end
  end
  return true
end

local function replacement_texts(state, edited)
  return edited.text, build_source_signature(edited, state.definition, state.declaration) .. " "
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

---@class LunaSignatureEditPlan
---@field workspace_edit table
---@field quickfix table[]

---Group both edits by URI: a declaration and definition may share a file.
---@param state LunaSignatureState
---@param declaration_text string
---@param definition_text string
---@return LunaSignatureEditPlan
function M.plan(state, declaration_text, definition_text)
  local changes = {}
  for _, change in ipairs {
    { target = state.declaration, text = declaration_text },
    { target = state.definition, text = definition_text },
  } do
    local uri = change.target.uri
    changes[uri] = changes[uri] or {}
    changes[uri][#changes[uri] + 1] = {
      range = lsp_range(change.target, state.encoding),
      newText = change.text,
    }
  end
  return { workspace_edit = { changes = changes }, quickfix = quickfix_items(state) }
end

---@param state LunaSignatureState
---@param plan LunaSignatureEditPlan
---@return boolean, string?
function M.apply(state, plan)
  if not current_ticks_match(state) then
    return false, "The declaration or definition changed during preview; apply was aborted"
  end
  local ok, err = pcall(vim.lsp.util.apply_workspace_edit, plan.workspace_edit, state.encoding)
  if not ok then
    return false, "Failed to apply the signature change: " .. tostring(err)
  end
  return true
end

M.current_ticks_match = current_ticks_match
M.replacement_texts = replacement_texts
M.lsp_range = lsp_range
M.quickfix_items = quickfix_items
return M
