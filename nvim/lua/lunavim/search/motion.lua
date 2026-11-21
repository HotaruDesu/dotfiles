local M = {}
local states = setmetatable({}, { __mode = "k" })

local function hide(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win, state.row, state.parent = nil, nil, nil
end

function M.close(picker)
  local state = states[picker]
  if not state then
    return
  end
  states[picker] = nil
  state.detach()
  hide(state)
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
end

function M.attach(picker)
  if states[picker] or require("lunavim.config.ui").get().reduced_motion then
    return
  end
  local state = {}
  states[picker] = state
  local function update()
    local list = picker.list
    if picker.closed or not list.win:valid() or list:count() == 0 or picker.layout:is_hidden "list" then
      hide(state)
      return
    end
    local parent = list.win.win
    -- Reserve a sign gutter so the marker never covers icons or multi-select.
    -- Layout refreshes can reset options without changing the window ID.
    if state.configured_parent ~= parent or vim.wo[parent].signcolumn ~= "yes:1" or vim.wo[parent].statuscolumn ~= "" then
      vim.wo[parent].signcolumn = "yes:1"
      vim.wo[parent].statuscolumn = ""
      state.configured_parent = parent
    end
    local row = vim.api.nvim_win_get_cursor(parent)[1] - 1
    if state.win and vim.api.nvim_win_is_valid(state.win) and state.row == row and state.parent == parent then
      return
    end
    local config = {
      relative = "win",
      win = parent,
      row = row,
      col = 0,
      width = 1,
      height = 1,
      focusable = false,
      mouse = false,
      style = "minimal",
      border = "none",
      zindex = (vim.api.nvim_win_get_config(parent).zindex or 50) + 1,
      noautocmd = true,
    }
    if state.win and vim.api.nvim_win_is_valid(state.win) and state.parent == parent then
      vim.api.nvim_win_set_config(state.win, config)
    else
      hide(state)
      if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
        state.buf = vim.api.nvim_create_buf(false, true)
        vim.bo[state.buf].bufhidden = "hide"
        vim.bo[state.buf].filetype = "lunavim_picker_marker"
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "▎" })
        vim.bo[state.buf].modifiable = false
      end
      state.win = vim.api.nvim_open_win(state.buf, false, config)
      vim.wo[state.win].winhighlight = "Normal:LunaVimPickerMarker,NormalNC:LunaVimPickerMarker"
      vim.wo[state.win].winblend = 0
    end
    state.row, state.parent = row, parent
  end
  state.detach = require("lunavim.search.observe").attach(picker, update)
  update()
end

return M
