local M = {}

local function show_cursorline(win, visible)
  local config = vim.api.nvim_win_get_config(win)
  if config.relative ~= "" or config.external then
    return
  end
  if visible and vim.w[win].auto_cursorline then
    vim.w[win].auto_cursorline = nil
    vim.wo[win][0].cursorline = true
  elseif not visible and vim.wo[win].cursorline then
    vim.wo[win][0].cursorline = false
    vim.w[win].auto_cursorline = true
  end
end

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
  local previous_win
  vim.api.nvim_create_autocmd("WinLeave", {
    group = cursorline,
    callback = function()
      -- :tab split copies window options between WinLeave and WinEnter.
      previous_win = vim.api.nvim_get_current_win()
    end,
  })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = cursorline,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if previous_win and previous_win ~= win and vim.api.nvim_win_is_valid(previous_win) then
        show_cursorline(previous_win, false)
      end
      previous_win = nil
      show_cursorline(win, not vim.fn.mode():match "^[iR]")
    end,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = cursorline,
    pattern = { "*:[iR]*", "[iR]*:*" },
    callback = function()
      show_cursorline(0, not vim.v.event.new_mode:match "^[iR]")
    end,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = cursorline,
    pattern = "cursorline",
    callback = function()
      if vim.v.option_command ~= "setglobal" then
        vim.w.auto_cursorline = nil
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
