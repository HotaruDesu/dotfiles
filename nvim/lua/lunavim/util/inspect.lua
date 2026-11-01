local M = {}

local function summarize(mappings)
  return vim.tbl_map(function(mapping)
    return { lhs = mapping.lhs, rhs = mapping.rhs, callback = mapping.callback, desc = mapping.desc }
  end, mappings)
end

function M.inspect_global_keymaps(mode)
  return summarize(vim.api.nvim_get_keymap(mode))
end

function M.inspect_local_keymaps(mode)
  return summarize(vim.api.nvim_buf_get_keymap(0, mode))
end

function M.keymapping_exist(mode, key)
  -- maparg handles aliases and buffer-local precedence using Neovim's own
  -- key notation, without treating case-sensitive printable keys as equal.
  return next(vim.fn.maparg(key, mode, false, true)) ~= nil
end

return M
