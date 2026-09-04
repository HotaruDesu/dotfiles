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
