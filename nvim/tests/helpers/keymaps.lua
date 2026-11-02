return function(maps)
  local rows = {}
  local function add(owner, modes, key, action, opts)
    opts = opts or {}
    modes = type(modes) == "table" and modes or { modes }
    for _, mode in ipairs(modes) do
      local id = owner .. "|" .. mode .. "|" .. key
      local fields = { id, type(action) == "string" and action or "<callback>", opts.desc or "" }
      for _, option in ipairs { "silent", "noremap", "expr", "nowait", "remap" } do
        fields[#fields + 1] = option .. "=" .. tostring(opts[option])
      end
      -- Last assignment wins, matching Neovim's effective keymap behavior.
      rows[id] = table.concat(fields, "\t")
    end
  end
  for mode, list in pairs(maps.get_defaults()) do
    for key, mapping in pairs(list) do
      local opts = vim.tbl_extend("force", { silent = true, noremap = true }, mapping[2] or {})
      add("default", maps.get_adapter()[mode], key, mapping[1], opts)
    end
  end
  for plugin, list in pairs(maps.get_plguins()) do
    if #list == 0 then
      for name, key in pairs(list) do
        add(plugin, "raw", name, key)
      end
    else
      for _, mapping in ipairs(list) do
        local opts = mapping[3] or {}
        add(plugin, mapping.mode or opts.mode or "n", mapping[1], mapping[2], opts)
      end
    end
  end
  local keys = vim.tbl_keys(rows)
  table.sort(keys)
  return vim.tbl_map(function(key)
    return rows[key]
  end, keys)
end
