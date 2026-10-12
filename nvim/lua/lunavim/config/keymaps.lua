local M = {}

local function lock_table(list)
  for _, tbl in ipairs(list) do
    LunaVim.util.lock_table(tbl)
  end
end

local generic_opts_any = { noremap = true, silent = true }

local generic_opts = {
  insert_mode = generic_opts_any,
  normal_mode = generic_opts_any,
  visual_mode = generic_opts_any,
  visual_block_mode = generic_opts_any,
  command_mode = generic_opts_any,
  term_mode = { silent = true },
}

local mode_adapter = {
  insert_mode = "i",
  normal_mode = "n",
  visual_mode = "v",
  visual_block_mode = "x",
  command_mode = "c",
  term_mode = "t",
}

local mode_radapter = {}
(function()
  for k, v in pairs(mode_adapter) do
    mode_radapter[v] = k
  end
end)()

local defaults = {
  normal_mode = {
    -- Cursor movement
    ["<C-H>"] = { "<C-W>h", { desc = "Move cursor left" } },
    ["<C-J>"] = { "<C-W>j", { desc = "Move cursor down" } },
    ["<C-K>"] = { "<C-W>k", { desc = "Move cursor up" } },
    ["<C-L>"] = { "<C-W>l", { desc = "Move cursor right" } },

    -- Split create
    ["<leader>sv"] = { "<C-w>v", { desc = "Split window vertically" } },
    ["<leader>sh"] = { "<C-w>s", { desc = "Split window horizontally" } },
    ["<leader>se"] = { "<C-w>=", { desc = "Make split equal size" } },
    ["<leader>sx"] = { ":close<Return>", { desc = "Close current split" } },

    -- Split resize
    ["<C-S-Up>"] = { ":resize   -2<Return>", { desc = "Expand split to top" } },
    ["<C-S-Down>"] = { ":resize   +2<Return>", { desc = "Expand split to wodn" } },
    ["<C-S-Left>"] = { ":vertical resize -2<Return>", { desc = "Expand split to left" } },
    ["<C-S-Right>"] = { ":vertical resize +2<Return>", { desc = "Expand split to right" } },

    -- Tab create
    ["<leader>to"] = {
      function()
        vim.cmd "tabnew"
        vim.cmd("tcd " .. vim.fn.fnameescape(vim.fn.getcwd()))
      end,
      { desc = "Open a new tab in cwd" },
    },
    ["<leader>tx"] = { ":tabclose<Return>", { desc = "Close a new tab" } },

    -- Tab movement
    ["<A-h>"] = { "gT", { desc = "Goto prev tab" } },
    ["<A-l>"] = { "gt", { desc = "Goto next tab" } },
    ["<D-h>"] = { "gT", { desc = "Goto prev tab" } },
    ["<D-l>"] = { "gt", { desc = "Goto next tab" } },
    ["<Tab>"] = { "gt", { desc = "Goto next tab" } },
    ["<S-Tab>"] = { "gT", { desc = "Goto prev tab" } },

    -- Move tabs
    ["<A-S-h>"] = { ":tabm -1<Return>", { desc = "Move tab to left" } },
    ["<A-S-l>"] = { ":tabm +1<Return>", { desc = "Move tab to right" } },
    ["<D-S-h>"] = { ":tabm -1<Return>", { desc = "Move tab to left" } },
    ["<D-S-l>"] = { ":tabm +1<Return>", { desc = "Move tab to right" } },
    ["<leader>tH"] = { ":tabm -1<Return>", { desc = "Move tab to left" } },
    ["<leader>tL"] = { ":tabm +1<Return>", { desc = "Move tab to right" } },

    -- tags
    ["<C-N>"] = { "<C-i>", { desc = "Jump to next" } },
    ["<C-P>"] = { "<C-o>", { desc = "Jump to prev" } },
    ["]]"] = { "<C-i>", { desc = "Jump to next" } },
    ["[["] = { "<C-o>", { desc = "Jump to prev" } },

    ["<leader>nh"] = { ":nohl<Return>", { desc = "No highlight" } },

    ["<leader>rn"] = {
      function()
        vim.lsp.buf.rename()
      end,
      { desc = "Rename" },
    },
    ["<leader>,,"] = {
      function()
        require("conform").format { async = true, lsp_format = "fallback" }
      end,
      { desc = "Format Buffer" },
    },
  },

  insert_mode = {},

  visual_mode = {},

  visual_block_mode = {},

  term_mode = {
    -- Terminal window navigation
    -- ["<C-h>"] = { "<C-\\><C-N><C-w>h", { desc = "Move to left window" } },
    ["<C-j>"] = { "<C-\\><C-N><C-w>j", { desc = "Move to lower window" } },
    ["<C-k>"] = { "<C-\\><C-N><C-w>k", { desc = "Move to upper window" } },
    -- ["<C-l>"] = { "<C-\\><C-N><C-w>l", { desc = "Move to right window" } },
  },
}

local plugins = {
  -- stylua: ignore start
  ["snacks.nvim"] = {
    -- search
    { "<leader>ff", function() Snacks.picker.files() end, { desc = "Find Files" } },
    { "<leader>fs", function() Snacks.picker.grep() end, { desc = "Grep Text" } },
    { "<leader>fr", function() Snacks.picker.recent() end, { desc = "Recent Files" } },
    { "<leader>fp", function() Snacks.picker.projects() end, { desc = "Projects" } },
    { "<leader><space>", function() Snacks.picker.smart() end, { desc = "Smart Find Files" } },
    { "<leader>fc", function() Snacks.picker.grep_word { words = vim.fn.expand "<cword>" } end, { desc = "Visual selection or word", mode = { "n", "x" } } },
    -- lsp
    { "gr", function() Snacks.picker.lsp_references() end, { desc = "LSP References", nowait = true } },
    { "gd", function() Snacks.picker.lsp_definitions() end, { desc = "LSP Definitions" } },
    { "gD", function() Snacks.picker.lsp_declarations() end, { desc = "Goto Declaration" } },
    { "gi", function() Snacks.picker.lsp_implementations() end, { desc = "Goto Implementation" } },
    { "gy", function() Snacks.picker.lsp_type_definitions() end, { desc = "Goto T[y]pe Definition" } },
    { "ghc", function() Snacks.picker.lsp_incoming_calls() end, { desc = "C[a]lls Incoming" } },
    { "ghc", function() Snacks.picker.lsp_outgoing_calls() end, { desc = "C[a]lls Outgoing" } },
    { "<leader>ss", function() Snacks.picker.lsp_symbols() end, { desc = "LSP Symbols" } },
    { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, { desc = "LSP Workspace Symbols" } },
    { "<leader>xd", function() Snacks.picker.diagnostics() end, { desc = "Diagnostics" } },
    -- git
    { "<leader>gb", function() Snacks.picker.git_branches() end, { desc = "Git Branches" } },
    { "<leader>gl", function() Snacks.picker.git_log() end, { desc = "Git Log" } },
    { "<leader>gL", function() Snacks.picker.git_log_line() end, { desc = "Git Log Line" } },
    { "<leader>gs", function() Snacks.picker.git_status() end, { desc = "Git Status" } },
    { "<leader>gS", function() Snacks.picker.git_stash() end, { desc = "Git Stash" } },
    { "<leader>gD", function() Snacks.picker.git_diff() end, { desc = "Git Diff (Hunks)" } },
    { "<leader>gf", function() Snacks.picker.git_log_file() end, { desc = "Git Log File" } },
    -- gh
    { "<leader>gi", function() Snacks.picker.gh_issue() end, { desc = "GitHub Issues (open)" } },
    { "<leader>gI", function() Snacks.picker.gh_issue { state = "all" } end, { desc = "GitHub Issues (all)" } },
    { "<leader>gp", function() Snacks.picker.gh_pr() end, { desc = "GitHub Pull Requests (open)" } },
    { "<leader>gP", function() Snacks.picker.gh_pr { state = "all" } end, { desc = "GitHub Pull Requests (all)" } },
    -- util
    { "<leader>hs", function() Snacks.notifier.show_history() end, { desc = "Notification History" } },
    { "<leader>nd", function() Snacks.notifier.hide() end, { desc = "Dismiss All Notifications" } },
    { "<leader>lg", function() Snacks.lazygit() end, { desc = "Lazygit" } },
    { "<leader>tt", function() Snacks.terminal(nil, { win = { position = "float", border = "rounded" } }) end, { desc = "Toggle Terminal (Float)" } },
    { "<leader>th", function() Snacks.terminal(nil, { win = { position = "bottom" } }) end, { desc = "Toggle Terminal (Bottom)" } },
    { "<leader>tv", function() Snacks.terminal(nil, { win = { position = "right" } }) end, { desc = "Toggle Terminal (Right)" } },
    { "<leader>z", function() Snacks.zen() end, { desc = "Toggle Zen Mode" } },
    -- { "]]", function() Snacks.words.jump(vim.v.count1) end, { desc = "Next Reference", mode = { "n", "t" } } },
    -- { "[[", function() Snacks.words.jump(-vim.v.count1) end, { desc = "Prev Reference", mode = { "n", "t" } } },
  },
  ["mini.surround"] = {
    add       = ",a", -- add:       ,a + textobj +    sign
    delete    = ",d", -- del:       ,d + sign
    replace   = ",r", -- replqce:   ,r + old     sign + new sign
    find      = ",n", -- find:      ,n + textobj
    find_left = ",p", -- rfind:     ,p + textobj
    highlight = ",h", -- highlight: ,h + textobj
  },
  ["lsp"] = {
    { "K", function() vim.lsp.buf.hover({ border = "rounded" }) end, { desc = "Hover", mode = "n" } },
    -- { "<C-k>", function() vim.lsp.buf.signature_help({ border = "rounded" }) end, { desc = "Signature help", mode = "n" } },
  },
  ["persistence.nvim"] = {
    { "<leader>ws", function() require("persistence").save() end, { desc = "Save Session" }, },
    { "<leader>wr", function() require("persistence").load() end, { desc = "Restore Session" }, },
    { "<leader>wd", function() require("persistence").stop() end, { desc = "Stop Auto Save Session" }, },
  },
  ["flash.nvim"] = {
    { "f", mode = { "n", "x", "o" }, function() require("flash").jump() end, { desc = "Flash Jump" } },
    { "t", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, { desc = "Flash Treesitter" } },
    { "r", mode = { "o" }, function() require("flash").remote() end, { desc = "Remote Flash" } },
    { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, { desc = "Treesitter Search" } },
    { "<c-x>", mode = { "n" }, function() require("flash").toggle() end, { desc = "Toggle Flash Search" } },
  },
  -- stylua: ignore end
  ["mini.align"] = {
    start = "<leader>ll",
    start_with_preview = "<leader>LL",
  },
  ["treesj"] = {
    { "<leader>tj", "<CMD>TSJToggle<Return>", { desc = "Toggle split/join code" } },
  },
  ["trouble.nvim"] = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<Return>", { desc = "Project Diagnostics" } },
    { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<Return>", { desc = "Buffer Diagnostics" } },
    { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<Return>", { desc = "Symbols (Trouble)" } },
    { "<leader>xl", "<cmd>Trouble lsp toggle focus=false win.position=right<Return>", { desc = "LSP Definitions" } },
    { "<leader>o", "<cmd>Trouble symbols toggle focus=false<cr>", { desc = "Code outline" } },
  },
  ["oil.nvim"] = {
    { "-", "<cmd>Oil<cr>", { desc = "Open Parent Directory (Oil)" } },
  },
  ["neo-tree.nvim"] = {
    { "<leader>ee", "<cmd>Neotree toggle<cr>", { desc = "Explorer NeoTree" } },
  },
  ["aerial.nvim"] = {
    { "<leader>cs", "<cmd>AerialToggle! right<cr>", { desc = "Code Outline" } },
  },
}

lock_table { generic_opts_any, generic_opts, mode_adapter, mode_radapter, defaults, plugins }

function M.set_keymaps(mode, key, val)
  local opts = generic_opts[mode_radapter[mode]] or generic_opts_any
  if type(val) == "table" then
    if val[2] ~= nil then
      opts = vim.tbl_deep_extend("force", opts, val[2])
    end
    val = val[1]
  end
  if val then
    vim.keymap.set(mode, key, val, opts)
  else
    vim.keymap.del(mode, key)
  end
end

function M.load_modes(mode, mapping)
  mode = mode_adapter[mode]
  for lhs, rhs in pairs(mapping) do
    M.set_keymaps(mode, lhs, rhs)
  end
end

function M.load(keymaps)
  for mode, mapping in pairs(keymaps) do
    M.load_modes(mode, mapping)
  end
end

function M.get_defaults()
  return defaults
end

function M.get_adapter()
  return mode_adapter
end

function M.load_defaults()
  M.load(M.get_defaults())
end

function M.clear_defaults(mappings)
  local default = M.get_defaults()
  for mode, keymaps in pairs(mappings) do
    for key, _ in pairs(keymaps) do
      if default[mode][key] ~= nil then
        M.set_keymaps(mode, key)
      end
    end
  end
end

function M.get_plguins()
  return plugins
end

local function report_keymaps(default_plugins, plugin_name)
  local cadidete_name = nil
  for k in pairs(default_plugins) do
    if k:lower():find(plugin_name:lower()) then
      cadidete_name = k
      break
    end
  end
  if cadidete_name then
    LunaVim.util.log_warn(("plugin: %s don't have keymaps, do you mean: %s?"):format(plugin_name, cadidete_name))
  else
    LunaVim.util.log_warn(("plugin: %s don't have keymaps"):format(plugin_name))
  end
end

function M.nvim_normized(keymaps)
  local opts = vim.fn.deepcopy(keymaps[3])
  local mode = opts.mode and opts.mode or { "n" }
  opts.mode = nil
  return { mode, keymaps[1], keymaps[2], opts }
end

function M.lazy_normized(keymaps)
  local opts = vim.fn.deepcopy(keymaps[3] or {})
  opts.mode = keymaps.mode or opts.mode or { "n" }
  opts[1] = keymaps[1]
  opts[2] = keymaps[2]
  return opts
end

function M.plugin_normized(keymaps, opts)
  local finial_keymaps = {}
  for _, mapping in ipairs(keymaps) do
    if opts and opts.lazy then
      table.insert(finial_keymaps, M.lazy_normized(mapping))
    else
      table.insert(finial_keymaps, M.nvim_normized(mapping))
    end
  end
  return finial_keymaps
end

function M.plugin_lazy(plugin_name)
  local local_plguins = M.get_plguins()
  if local_plguins[plugin_name] == nil then
    return report_keymaps(local_plguins, plugin_name)
  end
  return M.plugin_normized(M.get_plguins()[plugin_name], { lazy = true })
end

function M.plugin_nvim(plugin_name)
  local local_plguins = M.get_plguins()
  if local_plguins[plugin_name] == nil then
    return report_keymaps(local_plguins, plugin_name)
  end
  return M.plugin_normized(M.get_plguins()[plugin_name])
end

function M.plugin_raw(plugin_name)
  local local_plguins = M.get_plguins()
  if local_plguins[plugin_name] == nil then
    return report_keymaps(local_plguins, plugin_name)
  end
  return M.get_plguins()[plugin_name]
end

return M
