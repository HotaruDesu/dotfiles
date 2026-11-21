local M = {}
local states = setmetatable({}, { __mode = "k" })

-- Observe completed list renders, including unfocused cursor moves, without
-- changing Snacks globally or waiting for its throttled preview callback.
function M.attach(picker, callback)
  local list = picker.list
  local state = states[list]
  if not state then
    state = { callbacks = {}, own = rawget(list, "render"), original = list.render }
    states[list] = state
    state.render = function(self, ...)
      local result = state.original(self, ...)
      for fn in pairs(state.callbacks) do
        fn()
      end
      return result
    end
    list.render = state.render
  end
  state.callbacks[callback] = true
  return function()
    state.callbacks[callback] = nil
    if not next(state.callbacks) then
      if list.render == state.render then
        list.render = state.own
      end
      states[list] = nil
    end
  end
end

return M
