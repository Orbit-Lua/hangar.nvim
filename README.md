# hangar.nvim

Manage language servers, debug adapters, formatters, linters, Tree-sitter parsers and Mason packages from one Neovim view.

[![Validate hangar.nvim](https://github.com/Orbit-Lua/hangar.nvim/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/Orbit-Lua/hangar.nvim/actions/workflows/validate.yml) [![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/) [![Release](https://img.shields.io/github/v/release/Orbit-Lua/hangar.nvim)](https://github.com/Orbit-Lua/hangar.nvim/releases)

## Install

Use Neovim 0.12+ and [nui.nvim](https://github.com/MunifTanjim/nui.nvim). Each category also uses its backend when it is installed:

| Category | Backend |
| --- | --- |
| LSP | `vim.lsp` |
| DAP | [nvim-dap](https://github.com/mfussenegger/nvim-dap) and an owner that you provide |
| Formatter | [conform.nvim](https://github.com/stevearc/conform.nvim) |
| Linter | [nvim-lint](https://github.com/mfussenegger/nvim-lint) |
| Parser | [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) |
| Installation | [mason.nvim](https://github.com/mason-org/mason.nvim) |

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Orbit-Lua/hangar.nvim",
  version = "^0.2",
  dependencies = { "MunifTanjim/nui.nvim" },
  opts = {
    registry = {
      lsp = { lua_ls = { mason = "lua-language-server", ft = { "lua" } } },
    },
  },
  keys = {
    { "<leader>us", function() require("hangar").open() end, desc = "Open hangar" },
  },
}
```

## Usage

Call `require("hangar").setup(opts)` once, then `require("hangar").open()`. hangar registers no command or mapping. `:help hangar` lists the public interface.

The registry lists logical tools by category: `lsp`, `dap`, `linter`, `formatter`, `parser` and `package`. Each entry can set `mason`, `ft`, `runtime_name`, `note` and `source`. `formatter_defaults` and `linter_defaults` give the initial order for each filetype.

| Key | Action |
| --- | --- |
| `1`–`6`, Tab / Shift-Tab | Select a category |
| `s` | Switch between the source buffer and all tools |
| Space | Toggle a tool, with automatic installation when needed |
| `i` | Install without changing enablement |
| `[` / `]` | Reorder formatters or linters for a filetype |
| `o`, Enter, `za` | Expand or collapse a filetype group |
| `K` | Focus details |
| `?`, `g?` | Toggle help |
| `q`, Escape | Close |

Enablement and order persist in `stdpath("data")/hangar.json`.

## Configuration

Only `registry` is required. The other options have defaults:

| Option | Default |
| --- | --- |
| `ui` | View size, mappings, layout spacing, details and missing-package policy |
| `icons`, `border` | Status glyphs and `"rounded"` |
| `state_path` | `stdpath("data")/hangar.json` |
| `defaults` | Additional initial orders by category and filetype |
| `adapters.activation.formatter` / `.linter` | None: hangar uses the lists that `filter` records, or else the backend lists |
| `adapters.dap` | None: DAP changes are refused |
| `adapters.linter.logs` | No linter run errors |

Formatter and linter changes work with only a registry. To keep them after a restart, wrap the backend lists in `filter`. It applies saved enablement and order:

```lua
require("conform").setup({
  formatters_by_ft = require("hangar").filter("formatter", {
    lua = { "stylua" },
  }),
})
```

Call `filter` after `setup`. See the [guide](doc/guide.md) for options, statuses, persistence and layout.
