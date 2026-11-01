local M = {}

function M.send_to_next_tab()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local tab = vim.api.nvim_get_current_tabpage()
  if #vim.api.nvim_tabpage_list_wins(tab) <= 1 then
    return
  end

  local destination
  local tabs = vim.api.nvim_list_tabpages()
  for i, candidate in ipairs(tabs) do
    if candidate == tab then
      destination = tabs[i + 1]
      break
    end
  end
  if destination then
    vim.api.nvim_set_current_tabpage(destination)
    vim.cmd "leftabove vsplit"
  else
    vim.cmd "tabnew"
  end
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_set_current_tabpage(tab)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end)
end

return M
