-- Public entry point. Parsing, LSP discovery, edit plans and UI are independent
-- so changes can be verified without opening floating windows or running clangd.
local edits = require "lunavim.plugins.lsp.signature.edits"
local syntax = require "lunavim.plugins.lsp.signature.syntax"
local targets = require "lunavim.plugins.lsp.signature.targets"
local ui = require "lunavim.plugins.lsp.signature.ui"
local M = {}

local function notify(message)
  vim.notify(message, vim.log.levels.ERROR, { title = "C++ Change Signature" })
end

function M.change_signature()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "cpp" then
    notify "CppChangeSignature only supports C++ buffers"
    return
  end
  local clients = vim.lsp.get_clients { bufnr = bufnr, name = "clangd" }
  if #clients ~= 1 then
    notify(#clients == 0 and "No clangd client is attached to the current buffer" or "Multiple clangd clients are attached; the target is ambiguous")
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local ok, current, err = pcall(syntax.classify, bufnr, cursor[1] - 1, cursor[2])
  if not ok then
    notify("Could not parse the current C++ syntax tree: " .. tostring(current))
    return
  end
  if not current then
    notify(err)
    return
  end
  targets.discover(clients[1], current, function(state, discovery_err)
    if state then
      ui.open(state)
    elseif discovery_err then
      notify(discovery_err)
    end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("CppChangeSignature", M.change_signature, {
    desc = "Synchronize a C++ function declaration and definition",
    force = true,
  })
end

-- Preserve the existing inspection hooks while exposing the independently
-- testable plan and request lifecycle used by regression checks.
M._test = {
  parse_edited = syntax.parse_edited,
  build_source_signature = syntax.build_source_signature,
  validate_parameter_names = syntax.validate_parameter_names,
  classify = syntax.classify,
  current_ticks_match = edits.current_ticks_match,
  choose_targets = targets.choose_targets,
  replacement_texts = edits.replacement_texts,
  lsp_range = edits.lsp_range,
  quickfix_items = edits.quickfix_items,
}
return M
