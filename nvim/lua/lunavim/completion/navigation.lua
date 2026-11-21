local M = {}
local choice, full_providers, installed_list

function M.selected(ctx)
  if choice and ctx and ctx.id == choice.ctx.id and ctx.bufnr == choice.ctx.bufnr and ctx.line == choice.ctx.line and vim.deep_equal(ctx.cursor, choice.ctx.cursor) then
    return choice.item, choice.idx
  end
end

function M.same_item(a, b, ctx)
  if a == b then
    return true
  end
  if a.source_id == "lsp" then
    return require("lunavim.completion.semantic").same(a, b, ctx)
  end
  return a.source_id == b.source_id
    and a.client_id == b.client_id
    and a.label == b.label
    and a.kind == b.kind
    and a.detail == b.detail
    and vim.deep_equal(a.labelDetails, b.labelDetails)
    and a.insertText == b.insertText
    and a.insertTextFormat == b.insertTextFormat
    and a.insertTextMode == b.insertTextMode
    and vim.deep_equal(a.commitCharacters, b.commitCharacters)
    and vim.deep_equal(a.textEdit, b.textEdit)
    and vim.deep_equal(a.additionalTextEdits, b.additionalTextEdits)
    and vim.deep_equal(a.command, b.command)
    and vim.deep_equal(a.data, b.data)
end

function M.is_full(ctx)
  return full_providers ~= nil and ctx ~= nil and ctx.mode == "default" and ctx.providers == full_providers
end

local function navigate(method)
  -- An expression mapping cannot edit text. Queue the native preview *before*
  -- the next key: cmp.select_next/prev schedule it after pending typeahead.
  local keys = vim.keycode("<Cmd>lua require('blink.cmp.completion.list')." .. method .. "()<CR>")
  return function(cmp)
    local mode = vim.fn.mode()
    if (mode == "i" or mode == "R") and cmp.is_menu_visible() then
      return keys
    end
  end
end

M.select_next = navigate "select_next"
M.select_prev = navigate "select_prev"

function M.show_full(cmp)
  local ctx = require "blink.cmp.completion.trigger.context"
  if ctx.get_mode() ~= "default" then
    return cmp.show()
  end
  if cmp.is_menu_visible() and M.is_full(cmp.get_context()) then
    return
  end
  local list = require "blink.cmp.completion.list"
  -- Blink keeps the last undo edit even after hiding the list.
  local active = list.context
  local preview = active and active.bufnr == vim.api.nvim_get_current_buf() and cmp.is_menu_visible() and list.preview_undo
  if preview then
    -- Exit textlock before undoing a preview; cmp.show schedules the request next.
    vim.schedule(function()
      if list.context == active and active.bufnr == vim.api.nvim_get_current_buf() and list.preview_undo == preview then
        list.select(nil, { auto_insert = false, is_explicit_selection = false })
      end
    end)
  end
  full_providers = require("blink.cmp.sources.lib").get_enabled_provider_ids "default"
  return cmp.show { providers = full_providers }
end

function M.setup()
  local list = require "blink.cmp.completion.list"
  if installed_list == list then
    return
  end
  installed_list = list
  local override
  list.show_emitter:on(function(event)
    local item, idx = M.selected(event.context)
    if not item then
      return
    end
    -- Blink 1.x restores by label within the first ten rows. Use its native
    -- initial selection for this one refresh to keep the exact overload at any rank.
    if not event.items[idx] or not M.same_item(item, event.items[idx], event.context) then
      idx = nil
      for i, candidate in ipairs(event.items) do
        if M.same_item(item, candidate, event.context) then
          idx = i
          break
        end
      end
    end
    override = { ctx = event.context, initial = event.context.initial_selected_item_idx }
    event.context.initial_selected_item_idx = idx
    list.is_explicitly_selected = false
  end)
  list.select_emitter:on(function(event)
    if override then
      override.ctx.initial_selected_item_idx = override.initial
      override = nil
    end
    choice = nil
    if event.context.mode == "default" and event.item and list.is_explicitly_selected and list.preview_undo then
      choice = { ctx = event.context, item = event.item, idx = event.idx }
    end
  end)
  list.hide_emitter:on(function()
    choice = nil
  end)
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = vim.api.nvim_create_augroup("LunaCompletionPreview", { clear = true }),
    callback = function(event)
      local selected = choice
      choice = nil
      if not selected or not list.preview_undo or selected.ctx.bufnr ~= event.buf or vim.v.char == "" then
        return
      end
      local cursor = vim.api.nvim_win_get_cursor(0)
      if not vim.deep_equal(cursor, list.preview_undo.cursor_after) then
        return
      end
      local prefix = vim.api.nvim_get_current_line():sub(1, cursor[2]) .. vim.v.char
      vim.schedule(function()
        if vim.api.nvim_buf_is_loaded(event.buf) then
          local line = vim.api.nvim_buf_get_lines(event.buf, cursor[1] - 1, cursor[1], false)[1]
          if line and vim.startswith(line, prefix) then
            require("blink.cmp.fuzzy").access(selected.item)
          end
        end
      end)
    end,
  })
end

return M
