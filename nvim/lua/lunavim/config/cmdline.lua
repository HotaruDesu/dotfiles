local M = {}

-- Nui puts text in a child window. The parent includes the visible border
-- and padding, which also occupy grid rows when the command fits on one line.
function M.card_edge()
  if vim.fn.getcmdtype() ~= ":" then
    return
  end
  local noice = package.loaded.noice
  local prompt = noice and noice.api.get_cmdline_position()
  if not prompt or not vim.api.nvim_win_is_valid(prompt.win) then
    return
  end
  local parent = vim.api.nvim_win_get_config(prompt.win).win
  if not parent or not vim.api.nvim_win_is_valid(parent) then
    return
  end
  local top = vim.api.nvim_win_get_position(parent)[1]
  local bottom = top + vim.api.nvim_win_get_height(parent) - 1
  local below = vim.o.lines - bottom - 1
  if below >= top then
    return prompt, bottom, "s", below
  end
  return prompt, top, "n", top
end

-- Both backends supply a byte offset. screenpos accounts for wrapping and
-- wide characters and returns a one-based screen column.
function M.word_col(prompt, offset)
  -- Completion offsets omit the colon. Noice's concealed prefix includes it.
  local active = require("noice.ui.cmdline").last()
  local concealed = active and math.max(0, active.offset - 1) or 0
  local col = prompt.bufpos.col + math.max(0, offset - concealed)
  local word = vim.fn.screenpos(prompt.win, prompt.bufpos.row, col)
  return math.max(0, word.col - 1)
end

function M.menu_highlight(winhighlight)
  local normal = winhighlight:gsub("Normal:[^,]+", "Normal:LunaVimCmdlineMenu")
  return (normal:gsub("FloatBorder:[^,]+", "FloatBorder:LunaVimCmdlineBorder"))
end

return M
