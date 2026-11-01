local M = {}

---@alias LunaTerminalPosition "bottom"|"right"|"float"
---@alias LunaTerminalDirection "h"|"j"|"k"|"l"
---@class LunaTerminalSession
---@field cwd string
---@field terminal? snacks.terminal
---@field split "bottom"|"right"
---@field return_win? integer
---@field view? table

---@type table<integer, LunaTerminalSession>
local sessions = {}
local next_id = 0
local group = vim.api.nvim_create_augroup("LunaVimTerminal", { clear = true })
local layouts = {
  bottom = { position = "bottom", height = 0.3, width = 0, border = "none" },
  right = { position = "right", height = 0, width = 0.4, border = "none" },
  float = { position = "float", height = 0.9, width = 0.9, border = "rounded" },
}

---@param create? boolean
---@return LunaTerminalSession?
local function session(create)
  -- Buffer ownership also lets an orphaned terminal be used from :buffers.
  local tab = vim.b.lunavim_terminal_tab or vim.api.nvim_get_current_tabpage()
  if not sessions[tab] and create then
    sessions[tab] = { cwd = vim.fn.getcwd(), split = "bottom" }
  end
  return sessions[tab]
end

---@param terminal snacks.terminal
local function running(terminal)
  local job = terminal:buf_valid() and vim.b[terminal.buf].terminal_job_id
  return job and vim.fn.jobwait({ job }, 0)[1] == -1
end

---@param terminal snacks.terminal
local function enter_input(terminal)
  -- stopinsert takes effect after an Insert-mode mapping returns. Start the
  -- terminal input on the next turn, without stealing focus after another action.
  local win = vim.api.nvim_get_current_win()
  vim.schedule(function()
    if vim.api.nvim_get_current_win() == win and vim.api.nvim_get_current_buf() == terminal.buf and running(terminal) then
      vim.cmd.startinsert()
    end
  end)
end

---@param win? integer
local function editor_window(win)
  return win
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
    and vim.api.nvim_win_get_config(win).relative == ""
    and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
end

---@param state LunaTerminalSession
local function remember_editor(state)
  local win = vim.api.nvim_get_current_win()
  if editor_window(win) then
    state.return_win = win
  end
end

---@param state LunaTerminalSession
local function return_to_editor(state)
  vim.cmd.stopinsert()
  local win = state.return_win
  if not editor_window(win) then
    win = nil
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if editor_window(candidate) then
        win = candidate
        break
      end
    end
  end
  if win then
    vim.api.nvim_set_current_win(win)
  else
    -- Keep a real editing window even if the terminal was the last split.
    vim.cmd "aboveleft new"
  end
end

---@param state LunaTerminalSession
---@param terminal snacks.terminal
local function save_view(state, terminal)
  if terminal:valid() then
    state.view = vim.api.nvim_win_call(terminal.win, vim.fn.winsaveview)
  end
end

---@param state LunaTerminalSession
local function hide(state)
  local terminal = state.terminal
  if terminal and terminal:valid() then
    save_view(state, terminal)
    return_to_editor(state)
    terminal:hide()
  end
end

---@param state LunaTerminalSession
---@param input boolean
local function focus(state, input)
  local terminal = assert(state.terminal)
  terminal:show()
  terminal:focus()
  if input and running(terminal) then
    enter_input(terminal)
  else
    vim.cmd.stopinsert()
    if state.view then
      vim.fn.winrestview(state.view)
    end
  end
end

---@param state LunaTerminalSession
---@param position LunaTerminalPosition
local function set_layout(state, position)
  local terminal = assert(state.terminal)
  if terminal.opts.position ~= position then
    save_view(state, terminal)
    return_to_editor(state)
    terminal:hide()
  end
  for key, value in pairs(layouts[position]) do
    terminal.opts[key] = value
  end
  terminal.opts.wo.winfixheight = position == "bottom"
  terminal.opts.wo.winfixwidth = position == "right"
  terminal.opts.wo.winbar = position == "float" and "" or "%{b:term_title}"
  if position ~= "float" then
    state.split = position
  end
end

---@param state LunaTerminalSession
---@param position LunaTerminalPosition
local function create_terminal(state, position)
  next_id = next_id + 1
  local tab = vim.api.nvim_get_current_tabpage()
  local keys = {
    q = function()
      hide(state)
    end,
    gf = function()
      local file = vim.fn.findfile(vim.fn.expand "<cfile>", state.cwd .. "/**")
      if file == "" then
        vim.notify("No file under cursor", vim.log.levels.WARN)
        return
      end
      hide(state)
      vim.cmd.edit(vim.fn.fnameescape(file))
    end,
  }
  for key, spec in pairs {
    t = { M.toggle, "Toggle Terminal" },
    z = { M.toggle_zoom, "Zoom Terminal" },
    x = { M.destroy, "Destroy Terminal" },
  } do
    keys["<C-\\>" .. key] = { spec[1], mode = "t", desc = spec[2] }
  end
  for _, direction in ipairs { "h", "j", "k", "l" } do
    keys["<C-\\>" .. direction] = {
      function()
        M.navigate(direction)
      end,
      mode = "t",
      desc = "Move to " .. direction .. " window",
    }
  end
  local win = vim.tbl_deep_extend("force", {}, layouts[position], {
    enter = true,
    stack = false,
    backdrop = false,
    bo = { scrollback = 100000, bufhidden = "hide", buflisted = true },
    b = { lunavim_terminal_tab = tab },
    wo = { number = false, relativenumber = false, signcolumn = "no", statuscolumn = "" },
    keys = keys,
  })
  local terminal = Snacks.terminal.open(nil, {
    cwd = state.cwd,
    -- Nvim 0.12 auto-deletes a bare &shell on exit(0); an explicit interactive
    -- shell retains its transcript without changing other terminals' handlers.
    shell = vim.o.shell .. " -i",
    -- Negative, never-reused counts avoid collisions with user counts and stale callbacks.
    count = -next_id,
    interactive = false,
    win = win,
  })
  state.terminal = terminal
  set_layout(state, position)

  -- These listeners outlive the window: Snacks removes its own group on hide().
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = terminal.buf,
    callback = function()
      if state.terminal == terminal then
        save_view(state, terminal)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = terminal.buf,
    once = true,
    callback = function()
      if state.terminal == terminal then
        state.terminal, state.view = nil, nil
        if not vim.api.nvim_tabpage_is_valid(tab) then
          sessions[tab] = nil
        end
      end
    end,
  })
end

---Show the tab's terminal in a specific layout, retaining its job and output.
---@param position LunaTerminalPosition
function M.show(position)
  assert(layouts[position], "Invalid terminal position")
  local state = assert(session(true))
  remember_editor(state)
  local terminal = state.terminal
  local input = not terminal or vim.api.nvim_get_current_buf() ~= terminal.buf or vim.fn.mode():sub(1, 1) == "t"
  if not terminal or not terminal:buf_valid() then
    create_terminal(state, position)
  else
    set_layout(state, position)
  end
  focus(state, input)
end

---Focus the tab's terminal; hide it if already focused.
function M.toggle()
  local state = session()
  local terminal = state and state.terminal
  if terminal and terminal:buf_valid() and vim.api.nvim_get_current_buf() == terminal.buf then
    hide(state)
  else
    M.show(terminal and terminal.opts.position or "bottom")
  end
end

---Switch between a large float and the last split layout.
function M.toggle_zoom()
  local state = session()
  local terminal = state and state.terminal
  M.show(terminal and terminal.opts.position == "float" and state.split or "float")
end

---Use Neovim's native split navigation, entering a managed shell ready to type.
---@param direction LunaTerminalDirection
function M.navigate(direction)
  assert(direction:match "^[hjkl]$", "Invalid window direction")
  local state = session()
  local terminal = state and state.terminal
  local was_input = vim.fn.mode():sub(1, 1) == "t"
  if terminal and terminal.buf == vim.api.nvim_get_current_buf() and terminal.opts.position == "float" then
    set_layout(state, state.split)
    focus(state, was_input)
  end
  local target = vim.fn.win_getid(vim.fn.winnr(direction))
  if target == vim.api.nvim_get_current_win() then
    return
  end
  if state then
    remember_editor(state)
  end
  vim.cmd.stopinsert()
  vim.api.nvim_set_current_win(target)
  local destination = session()
  local shell = destination and destination.terminal
  if shell and shell.buf == vim.api.nvim_get_current_buf() and running(shell) then
    enter_input(shell)
  end
end

---Stop the job and discard its output; the next toggle creates a fresh shell.
function M.destroy()
  local state = session()
  local terminal = state and state.terminal
  if not terminal or not terminal:buf_valid() then
    return
  end
  remember_editor(state)
  if running(terminal) then
    if vim.fn.jobstop(vim.b[terminal.buf].terminal_job_id) ~= 1 then
      vim.notify("Could not stop terminal job", vim.log.levels.ERROR)
      return
    end
  end
  hide(state)
  terminal:close()
  if terminal:buf_valid() then
    vim.notify("Could not remove terminal buffer", vim.log.levels.ERROR)
    return
  end
  if state.terminal == terminal then
    state.terminal, state.view = nil, nil
  end
end

return M
