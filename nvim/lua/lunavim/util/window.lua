local M = {}
local api = vim.api

local function is_split(win)
  local config = api.nvim_win_get_config(win)
  return config.relative == "" and not config.external
end

local function new_tab(source)
  if api.nvim_open_tabpage then
    return api.nvim_open_tabpage(0, false, {})
  end
  -- Neovim 0.11 can only create a tab by entering it.
  vim.cmd "tab split"
  local destination = api.nvim_get_current_tabpage()
  api.nvim_set_current_tabpage(source)
  return destination
end

function M.send_to_next_tab()
  local win = api.nvim_get_current_win()
  local source = api.nvim_get_current_tabpage()
  if not is_split(win) or #vim.tbl_filter(is_split, api.nvim_tabpage_list_wins(source)) < 2 then
    return
  end

  local view = vim.fn.winsaveview()
  local destination = api.nvim_list_tabpages()[api.nvim_tabpage_get_number(source) + 1]
  local created = destination == nil
  destination = destination or new_tab(source)
  local target = api.nvim_tabpage_get_win(destination)
  if not is_split(target) then
    target = vim.tbl_filter(is_split, api.nvim_tabpage_list_wins(destination))[1]
  end

  local ok, err = pcall(api.nvim_win_set_config, win, { split = "left", win = target })
  if created and api.nvim_win_is_valid(target) then
    api.nvim_win_close(target, false)
  end
  api.nvim_win_call(win, function()
    vim.fn.winrestview(view)
  end)
  if not ok then
    error(err, 0)
  end
  api.nvim_tabpage_set_win(destination, win)
end

return M
