local M = {}

local function cleanup_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  if vim.bo[buf].buftype ~= "" or vim.bo[buf].modified or #vim.fn.win_findbuf(buf) > 0 then
    return
  end
  vim.api.nvim_buf_delete(buf, { force = false })
end

function M.setup()
  local cursorline = vim.api.nvim_create_augroup("LunaVimCursorLine", { clear = true })
  vim.api.nvim_create_autocmd({ "InsertLeave", "WinEnter" }, {
    group = cursorline,
    callback = function()
      if vim.w.auto_cursorline then
        vim.w.auto_cursorline = false
        vim.wo.cursorline = true
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertEnter", "WinLeave" }, {
    group = cursorline,
    callback = function()
      if vim.wo.cursorline then
        vim.w.auto_cursorline = true
        vim.wo.cursorline = false
      end
    end,
  })

  local buffers = vim.api.nvim_create_augroup("LunaVimBuffers", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = buffers,
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
  end, { desc = "Remove saved, hidden file buffers", force = true })

  local reload = vim.api.nvim_create_augroup("LunaVimFileReload", { clear = true })
  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
    group = reload,
    callback = function()
      if vim.fn.mode() ~= "c" then
        vim.cmd "checktime"
      end
    end,
  })
  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = reload,
    callback = function(args)
      vim.notify("auto reload file: " .. args.file, vim.log.levels.INFO)
    end,
  })
end

return M
