# hangar.nvim

Turn language servers, debug adapters, formatters, linters and Tree-sitter parsers on and off from one Neovim view.

[![Validate hangar.nvim](https://github.com/Orbit-Lua/hangar.nvim/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/Orbit-Lua/hangar.nvim/actions/workflows/validate.yml) [![Release](https://img.shields.io/github/v/release/Orbit-Lua/hangar.nvim)](https://github.com/Orbit-Lua/hangar.nvim/releases/latest) [![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)

## Install

Use Neovim 0.12+ and [nui.nvim](https://github.com/MunifTanjim/nui.nvim). Each category uses its backend when it is installed:

| Category | Backend |
| --- | --- |
| LSP | `vim.lsp` |
| DAP | [nvim-dap](https://github.com/mfussenegger/nvim-dap) |
| Formatter | [conform.nvim](https://github.com/stevearc/conform.nvim) |
| Linter | [nvim-lint](https://github.com/mfussenegger/nvim-lint) |
| Parser | Neovim Tree-sitter, and [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) for installation |
| Package | [mason.nvim](https://github.com/mason-org/mason.nvim) |

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Orbit-Lua/hangar.nvim",
  version = "^0.4",
  lazy = false,
  dependencies = { "MunifTanjim/nui.nvim" },
  opts = {},
  keys = {
    { "<leader>us", function() require("hangar").open() end, desc = "Open hangar" },
  },
}
```

Load hangar at startup. It must be set up before your LSP, conform, nvim-lint and nvim-dap configuration runs.

## Usage

Call `require("hangar").setup()` once, then `require("hangar").open()`. hangar registers no command or mapping. `:help hangar` lists the public interface.

The view lists the tools that your configuration registers. Space turns the selected tool on or off. The change applies at once and persists in `stdpath("data")/hangar.json`. At the next start, hangar applies the saved state before the tools run.

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

## Ownership

Your configuration and hangar each own separate tasks:

| Task | Owner |
| --- | --- |
| Declare the tools of each language | Your configuration: `vim.lsp.config` and `vim.lsp.enable`, conform `formatters_by_ft`, nvim-lint `linters_by_ft`, nvim-dap `adapters` and `configurations`, Tree-sitter start |
| Map a tool to its Mason package | The optional registry |
| Install packages | mason.nvim, when hangar asks it |
| Save and apply enablement and order | hangar |

hangar never adds a tool and never guesses a Mason package. It only stops or filters the tools that your configuration declares.

## Integrations

Each integration gates one backend from the saved state:

| Option | Effect of a disabled tool |
| --- | --- |
| `integrations.lsp` | `vim.lsp.enable` skips the server, and hangar stops its clients |
| `integrations.dap` | A debug session of that adapter type does not start |
| `integrations.conform` | conform's `formatters_by_ft` drops the formatter |
| `integrations.lint` | nvim-lint's `linters_by_ft` drops the linter |
| `integrations.treesitter` | Tree-sitter stops in buffers of that language |

Each one defaults to `true`. Set one to `false` to leave its backend alone.

## Registry

The registry is optional. Without it, the view lists the tools that the backends report, and installation reports that no install mapping exists. Add a registry to install tools through Mason:

```lua
---@type Hangar.Registry
local registry = {
  lsp = { lua_ls = { mason = "lua-language-server", ft = { "lua" } } },
  formatter = { stylua = { mason = "stylua", ft = { "lua" } } },
}

require("hangar").setup({ registry = registry })
```

`setup` rejects an unknown key, field or value with an error that names its path. `:help hangar-registry` lists the fields.

## Configuration

Every option is optional:

| Option | Default |
| --- | --- |
| `registry` | None: tools come from the backends |
| `integrations` | All on |
| `ui` | View size, mappings, layout spacing, details and missing-package policy |
| `icons`, `border` | Status glyphs and `"rounded"` |
| `state_path` | `stdpath("data")/hangar.json` |
| `defaults` | Additional initial orders by category and filetype |
| `adapters.linter.logs` | No linter run errors |

With the conform or lint integration off, wrap the backend lists in `filter`. It applies the saved enablement and order:

```lua
require("conform").setup({
  formatters_by_ft = require("hangar").filter("formatter", {
    lua = { "stylua" },
  }),
})
```

See the [guide](doc/guide.md) for statuses, persistence and layout.
