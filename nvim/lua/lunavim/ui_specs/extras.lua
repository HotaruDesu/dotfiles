return {
  {
    "HiPhish/rainbow-delimiters.nvim",
    event = { "BufReadPost", "BufNewFile" },
  },
  -- code action
  {
    "rachartier/tiny-code-action.nvim",
    dependencies = {
      { "nvim-lua/plenary.nvim" },
      { "nvim-tree/nvim-web-devicons" },
    },
    event = "LspAttach",
    keys = {
      {
        "<leader>ca",
        function()
          require("tiny-code-action").code_action {
            sort = function(a, b)
              local function get_priority(kind)
                if string.match(kind or "", "^quickfix") then
                  return 1
                end
                if string.match(kind or "", "^refactor") then
                  return 2
                end
                return 3
              end

              local a_priority = get_priority(a.action.kind)
              local b_priority = get_priority(b.action.kind)

              return a_priority < b_priority
            end,
          }
        end,
        mode = { "n", "v" },
        desc = "Code Action (Tiny)",
      },
    },
    opts = {
      backend = "vim",
      backend_opts = {
        enabled_dirs = { "src", "include" },
      },
    },
    config = function(_, opts)
      require("tiny-code-action").setup(opts)
    end,
  },
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "Diffview: View current diff" },

      { "<leader>gw", "<cmd>DiffviewOpen -w<CR>", desc = "Diffview: Ignore format commit" },

      { "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", desc = "Diffview: History for current file" },

      { "<leader>gc", "<cmd>DiffviewClose<CR>", desc = "Diffview: Close Dashboard" },
    },
    opts = {
      enhanced_diff_hl = true,
      view = {
        default = {
          layout = "diff2_horizontal",
        },
        file_history = {
          layout = "diff2_horizontal",
        },
      },
      file_panel = {
        listing_style = "tree",
        tree_options = {
          flatten_dirs = true,
        },
      },
    },
  },
}
