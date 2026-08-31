return {
  {
    "github/copilot.vim",
    lazy = false,
    init = function()
      -- keep copilot's native <Tab> map off; nvim-cmp owns <Tab> and accepts the
      -- suggestion from there (see the nvim-cmp spec below). <C-l> force-accepts
      -- even when the cmp menu is open
      vim.g.copilot_no_tab_map = true
      vim.keymap.set("i", "<C-l>", 'copilot#Accept("\\<CR>")', {
        expr = true,
        replace_keycodes = false,
        desc = "Copilot accept",
      })
    end,
  },

  {
    -- <C-n>/<C-p> drive the completion menu, so <Tab> is free to accept Copilot.
    -- override NvChad's default cmp <Tab>/<S-Tab> (which selected menu items) to
    -- drop menu navigation and make <Tab> accept Copilot's ghost-text suggestion,
    -- falling back to snippet expand/jump, then a literal tab
    "hrsh7th/nvim-cmp",
    opts = function(_, opts)
      local cmp = require "cmp"
      local luasnip = require "luasnip"

      opts.mapping["<Tab>"] = cmp.mapping(function(fallback)
        if vim.fn["copilot#GetDisplayedSuggestion"]().text ~= "" then
          vim.api.nvim_feedkeys(vim.fn["copilot#Accept"] "", "i", true)
        elseif luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        else
          fallback()
        end
      end, { "i", "s" })

      opts.mapping["<S-Tab>"] = cmp.mapping(function(fallback)
        if luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, { "i", "s" })

      return opts
    end,
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "github/copilot.vim",
    },
    build = "make tiktoken",
    keys = {
      { "<leader>cc", "<cmd>CopilotChatToggle<cr>", desc = "CopilotChat - Toggle", mode = { "n", "v" } },
    },
    opts = {
      window = {
        layout = "vertical",
        width = 0.33,
      },
      auto_insert_mode = true,
      mappings = {
        close = { normal = "<C-c>", insert = "<C-c>" },
        submit_prompt = { normal = "<C-s>", insert = "<C-s>" },
      },
      on_open = function(bufnr)
        vim.api.nvim_set_option_value("wrap", true, { buf = bufnr })
      end,
    },
  },

  {
    "lukas-reineke/indent-blankline.nvim",
    enabled = false,
  },

  {
    "folke/snacks.nvim",
    lazy = false,
    opts = {
      indent = {
        enabled = true,
        char = "│",
      },
      scope = {
        enabled = true,
      },
    },
  },

  {
    "f-person/git-blame.nvim",
    event = "VeryLazy",
    opts = {
      enabled = true,
      message_template = " <author> • <date>",
      date_format = "%r",
    },
  },

  {
    "stevearc/conform.nvim",
    cmd = "ConformInfo",
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    "nvim-tree/nvim-tree.lua",
    opts = function()
      return require "configs.nvimtree"
    end,
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  {
    "L3MON4D3/LuaSnip",
    build = (function()
      if vim.fn.has "win32" == 1 or vim.fn.executable "make" == 0 then
        return
      end
      return "make install_jsregexp"
    end)(),
    dependencies = { "rafamadriz/friendly-snippets" },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main", -- 'master' is frozen and crashes on Neovim 0.11+ injection directives
    build = ":TSUpdate",
    config = function()
      -- NOTE: the 'main' branch installs parsers via the `tree-sitter` CLI.
      -- Make sure it's on PATH: `npm install -g tree-sitter-cli`.
      -- Neovim already bundles lua/vim/vimdoc/markdown parsers, so only the
      -- languages it doesn't ship are installed here.
      require("nvim-treesitter").install {
        "ruby", "embedded_template", -- embedded_template = ERB / Rails views
        "html", "css", "javascript", "typescript",
        "bash", "json", "yaml", "xml",
      }

      -- the 'main' branch no longer auto-enables highlighting; start it per buffer
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })
      -- also start it for any buffer already open when this plugin loads
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          pcall(vim.treesitter.start, buf)
        end
      end
    end,
  },
}
