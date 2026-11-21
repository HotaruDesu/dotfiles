local M = {}
local installed

-- Snacks scrolls by moving the real cursor through intermediate lines. Finish
-- its last frame before processing a key so a fast G followed by an edit
-- operates at the destination. Synthetic keys from animation frames have no
-- typed bytes and should let the animation continue.
function M.setup()
  local animate = Snacks.animate
  if installed == animate then
    return
  end
  installed = animate
  local pending = setmetatable({}, { __mode = "v" })
  local add = animate.add
  animate.add = function(from, to, draw, opts)
    local id = opts and opts.id
    local win = type(id) == "string" and tonumber(id:match "^scroll_(%d+)$" or id:match "^scroll_repeat_(%d+)$")
    if not win then
      return add(from, to, draw, opts)
    end
    local finish
    local animation = add(from, to, function(value, ctx)
      if ctx.done and pending[win] == finish then
        pending[win] = nil
      end
      draw(value, ctx)
    end, opts)
    finish = function()
      if animation.timer and animation.timer:is_active() then
        draw(to, { anim = animation, prev = to, done = true })
      end
    end
    pending[win] = finish
    return animation
  end
  vim.on_key(function(_, typed)
    if typed == "" or not next(pending) then
      return
    end
    local win = vim.api.nvim_get_current_win()
    local finish = pending[win]
    if finish then
      pending[win] = nil
      finish()
    end
  end, vim.api.nvim_create_namespace "LunaScrollInput")
end

return M
