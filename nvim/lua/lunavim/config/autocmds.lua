-- show cursor line only in active window
local cursorline_group = vim.api.nvim_create_augroup("LunaVimCursorLine", { clear = true })

vim.api.nvim_create_autocmd({ "InsertLeave", "WinEnter" }, {
  group = cursorline_group,
  callback = function()
    if vim.w.auto_cursorline then
      -- Window-scoped variables for the current window
      vim.w.auto_cursorline = false
      -- Window-scoped options for the current window
      vim.wo.cursorline = true
    end
  end,
})

vim.api.nvim_create_autocmd({ "InsertEnter", "WinLeave" }, {
  group = cursorline_group,
  callback = function()
    -- Reverse options
    if vim.wo.cursorline then
      vim.w.auto_cursorline = true
      vim.wo.cursorline = false
    end
  end,
})


local function cleanup_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  if vim.bo[buf].buftype ~= "" or vim.bo[buf].modified then
    return
  end

  if #vim.fn.win_findbuf(buf) > 0 then
    return
  end

  vim.api.nvim_buf_delete(buf, { force = false })
end

vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(event)
    local win = tonumber(event.match)
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end

    local buf = vim.api.nvim_win_get_buf(win)

    vim.schedule(function()
      cleanup_buffer(buf)
    end)
  end,
})

vim.api.nvim_create_user_command("BufPrune", function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    cleanup_buffer(buf)
  end
end, {})
