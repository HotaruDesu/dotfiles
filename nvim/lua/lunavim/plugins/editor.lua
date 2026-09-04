return {
  -- Negative file in buffer
  {
    "stevearc/oil.nvim",
    cmd = "Oil",
    keys = LunaVim.plugin_lazy "oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      default_file_explorer = true,
      columns = { "icon" },
      keymaps = {
        ["g?"] = "actions.show_help",
        ["<CR>"] = "actions.select",
        ["<C-s>"] = { "actions.select", opts = { vertical = true } },
        ["<C-h>"] = { "actions.select", opts = { horizontal = true } },
        ["<C-t>"] = { "actions.select", opts = { tab = true } },
        ["-"] = "actions.parent",
        ["_"] = "actions.open_cwd",
        ["<Esc>"] = { "actions.close", mode = "n" },
        ["gs"] = "actions.change_sort",
        ["gx"] = "actions.open_external",
        ["g."] = "actions.toggle_hidden",
      },
      view_options = {
        show_hidden = true,
        is_hidden_file = function(name)
          return vim.startswith(name, ".")
        end,
      },
    },
  },
  -- File tree
  {
    "nvim-neo-tree/neo-tree.nvim",
    cmd = "Neotree",
    keys = LunaVim.plugin_lazy "neo-tree.nvim",
    opts = {
      close_if_last_window = true,
      popup_border_style = "rounded",
      filesystem = {
        bind_to_cwd = false,
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
      },
      window = {
        width = 30,
        position = "left",
        mappings = {
          ["<space>"] = "none",
        },
      },
      default_component_configs = {
        indent = {
          with_expanders = true,
          expander_collapsed = "",
          expander_expanded = "",
        },
        icon = {
          folder_closed = LunaVim.icons.ui.Folder,
          folder_open = LunaVim.icons.ui.FolderOpen,
          folder_empty = LunaVim.icons.ui.EmptyFolder,
          default = LunaVim.icons.ui.Folder,
        },
        git_status = {
          symbols = LunaVim.icons.git,
        },
      },
    },
  },
  -- Better escape
  {
    "max397574/better-escape.nvim",
    event = "InsertEnter",
    opts = {
      timeout = 200,
      mappings = {
        i = { j = { k = "<Esc>", j = "<Esc>" } },
        c = { j = { k = "<Esc>", j = "<Esc>" } },
        t = { j = { k = "<C-\\><C-n>" } },
      },
    },
  },
  -- Quick jump
  {
    "folke/flash.nvim",
    event = "BufReadPre",
    keys = LunaVim.plugin_lazy "flash.nvim",
    opts = {
      incremental = false,
      modes = {
        search = {
          enabled = true,
        },
        char = {
          enabled = false,
        },
        remote = {
          remote_op = { restore = true, motion = true },
        },
      },
    },
  },
  -- Class structure
  {
    "stevearc/aerial.nvim",
    event = "LspAttach",
    opts = function()
      return {
        on_attach = function(bufnr)
          vim.keymap.set("n", "{", "<cmd>AerialPrev<cr>", { buffer = bufnr })
          vim.keymap.set("n", "}", "<cmd>AerialNext<cr>", { buffer = bufnr })
        end,
        layout = { min_width = 20, default_direction = "right" },
        icons = LunaVim.icons.kinds,
      }
    end,
    keys = LunaVim.plugin_lazy "aerial.nvim",
  },
  -- Git sign
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
      },
    },
  },
  -- Keymaps manager
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      win = { border = "rounded" },
      spec = {
        { "<leader>c", group = "Code" },
        { "<leader>f", group = "Find" },
        { "<leader>g", group = "Git" },
        { "<leader>m", group = "CMake" },
        { "<leader>s", group = "Search" },
        { "<leader>w", group = "Workspace" },
        { "<leader>x", group = "Diagnostics" },
      },
    },
  },
  -- Persist session
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {
      options = { "buffers", "curdir", "tabpages", "winsize" },
      need = 1,
    },
    keys = LunaVim.plugin_lazy "persistence.nvim",
  },
  -- tmux
  -- TODO comment
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      {
        "]t",
        function()
          require("todo-comments").jump_next()
        end,
        desc = "Next Todo",
      },
      {
        "[t",
        function()
          require("todo-comments").jump_prev()
        end,
        desc = "Prev Todo",
      },
      { "<leader>st", "<cmd>TodoSnacks<cr>", desc = "Search Todo (Snacks)" },
    },
    opts = {
      signs = true,
      highlight = {
        multiline = true,
        keyword = "bg",
        after = "fg",
        pattern = [[.*<(KEYWORDS)\s*:]],
      },
    },
  },
  -- {
  --   "chrisgrieser/nvim-spider",
  --   lazy = true,
  --   keys = LunaVim.plugin_lazy "nvim-spider",
  --   opts = {
  --     skipInsignificantPunctuation = false,
  --   },
  -- },
}
