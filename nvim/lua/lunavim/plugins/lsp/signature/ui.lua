local edits = require "lunavim.plugins.lsp.signature.edits"
local syntax = require "lunavim.plugins.lsp.signature.syntax"
local M = {}
local TITLE = "C++ Change Signature"
local trim, lines = syntax.trim, syntax.lines
local parse_edited, validate_parameter_names = syntax.parse_edited, syntax.validate_parameter_names
local current_ticks_match, replacement_texts = edits.current_ticks_match, edits.replacement_texts

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = TITLE })
end

local function close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function floating_window(bufnr, opts)
  local width = math.min(opts.width or 100, math.max(40, vim.o.columns - 8))
  local height = math.min(opts.height or 12, math.max(3, vim.o.lines - 8))
  local win = vim.api.nvim_open_win(bufnr, true, {
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
  vim.wo[win].winblend = require("lunavim.config.ui").get().float_blend
  return win
end

local function target_label(target)
  local name = vim.api.nvim_buf_get_name(target.bufnr)
  return name ~= "" and vim.fn.fnamemodify(name, ":~:.") or target.uri
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

local function apply_changes(state, declaration_text, definition_text, preview_win, edit_win)
  if not current_ticks_match(state) then
    close_window(preview_win)
    close_window(edit_win)
    notify("The declaration or definition changed during preview; apply was aborted", vim.log.levels.ERROR)
    return
  end
  local plan = edits.plan(state, declaration_text, definition_text)
  local ok, err = edits.apply(state, plan)
  if not ok then
    notify(err, vim.log.levels.ERROR)
    return
  end
  close_window(preview_win)
  close_window(edit_win)
  vim.fn.setqflist({}, " ", {
    title = "C++ signature call sites",
    items = plan.quickfix,
  })
  if #plan.quickfix > 0 then
    vim.cmd "copen"
  end
  notify(("Synchronized declaration and definition; added %d original call sites to quickfix (files remain unsaved)"):format(#plan.quickfix))
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

M.open = open_editor
return M
