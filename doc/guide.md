# Guide

## Setup

`require("hangar").setup(opts)` validates the options and fills defaults. Every option is optional. A category or default-order table that the registry omits becomes empty, so every category can be browsed.

A caller's `ui` table stays the same object. Setup adds only its missing keys. `icons` gets the same treatment. To change the view options later, call `require("hangar").update_ui(values)`. A key that `values` omits takes its default. An open view then rebinds its keys and redraws. The selected category stays selected. If the new options remove it, the first category is selected. `categories` must name at least one known category. You can also change the `ui` table yourself and then fire `User HangarChanged`.

Use before setup raises an error that names `hangar.setup`. A repeated setup replaces the options, drops cached state and failures, and closes the open view. It is rejected while a toggle or an installation runs.

`adapters.linter.logs(name)` returns run errors for a linter. Each entry has `level`, `message` and optional `tags.kind`. Setup rejects the removed `adapters.dap` and `adapters.activation` options with an error.

## Registry and discovery

The registry is optional. Each category lists the registry entries and the tools that the loaded backends report:

| Category | Discovered from |
| --- | --- |
| LSP | Names that `vim.lsp.enable` enabled, or that hangar disabled |
| DAP | The keys of nvim-dap's `adapters` |
| Formatter | conform's `formatters_by_ft` |
| Linter | nvim-lint's `linters_by_ft` |
| Parser | Parsers that nvim-treesitter installed |

A registry field wins over a discovered one. A tool without a `mason` field has no install mapping. Its install action reports `no install mapping for <name>`.

An LSP client that a plugin starts outside `vim.lsp.config` needs a registry entry with `plugin`, such as `plugin = "typescript-tools"`. Its status counts the running clients.

## Integrations

Setup installs the integrations of `integrations`. Each one defaults to `true`. Set one to `false` to leave its backend alone. With the DAP or Tree-sitter integration off, that category refuses toggles. With the LSP integration off, a toggle calls `vim.lsp.enable` and changes only the running session.

- **LSP**: setup wraps `vim.lsp.enable`. An enable of a disabled server is recorded and skipped. Re-enabling the server replays that enable. hangar never enables a server that your configuration did not enable. An `LspAttach` handler stops clients of disabled servers, also clients that a plugin starts.
- **DAP**: a `dap.listeners.on_config` listener aborts a session of a disabled adapter type and reports it.
- **conform** and **lint**: each table that `conform.setup` or your configuration assigns becomes the activation. hangar filters it in place before conform formats and before nvim-lint runs. hangar also drops disabled linters from the names that a caller passes to `try_lint`.
- **Tree-sitter**: a `FileType` handler stops Tree-sitter in buffers of a disabled language. Re-enabling restarts it only in the buffers that hangar stopped. The parser files stay installed.

hangar applies the conform, nvim-lint and nvim-dap integrations when `require` first loads that plugin, through one module loader. A plugin that is already loaded at setup is gated at once. Set up hangar at startup, before these plugins load and before your configuration calls `vim.lsp.enable`.

## Formatters and linters

hangar needs the initial runtime names by filetype. It takes them from the first available source:

1. The table that the last `require("hangar").filter(category, by_ft)` call received.
2. The backend table that the conform or lint integration adopted.
3. The backend lists, conform's `formatters_by_ft` or nvim-lint's `linters_by_ft`, captured at first use.

A captured list also takes names that the backend list gains later. A repeated setup keeps the list, so a tool that you disabled before can be enabled again.

With the integration on, hangar keeps the backend lists in line with saved state. With the integration off, hangar changes only the backend lists at runtime. To keep enablement and order after a restart, wrap the lists in `filter`. It returns a copy without disabled tools and in saved order. Unregistered names stay after the registered ones. Call it after setup. A list that `filter` produced is not filtered a second time.

Without a saved order, the initial order is the priority. A tool that you enable again returns to its position.

hangar keeps conform option keys such as `stop_after_first`. It leaves function entries and the `*` and `_` keys unchanged. Conform still runs a disabled tool that `*` or `_` lists. Its status shows `Disabled, still listed under "*"`.

If no source is available, status shows `Activation not configured`. Toggle and reorder then return an error, and hangar changes no saved state.

## Navigation

`require("hangar").open()` focuses the existing view if one is open. A new session captures the filetype and filename of the source buffer. `s` switches between that buffer and all tools.

Use `1`–`6` or Tab / Shift-Tab to select LSP, DAP, Linter, Formatter, Parser or Package. Number keys and help follow `ui.categories`, and footer hints follow `ui.mappings`. Buffer-scope formatter and linter lists show saved ranks. All-state lists group by filetype. Expand a group with `o`, Enter or `za`.

Logical selection survives reordering, resizing and refreshes. Category and expansion choices survive reopening. Help (`?` or `g?`) suspends tool actions and stays visible during refresh. Beside or below the list, details stay open and follow the cursor. They show the selected tool, a filetype group, an empty category or the category overview with an icon legend.

`<C-l>` focuses details, including the overview during help. `<C-h>`, `q` or Escape returns from details to the list. Beside or below the list, details stay open. On narrow screens, `<C-l>` opens popup details, and returning closes them. `K` has no default binding. Assign the `details` and `back` actions in `ui.mappings` to change the focus keys.

Setup and `update_ui()` reject conflicting mappings before they replace accepted options. Keycode aliases, category numbers and prefixes of other mappings conflict. For example, `<Tab>` and `<C-i>` cannot name separate actions. All Hangar mappings stay local to its view buffers.

## Layout

`ui.layout` sets the spacing in cells. `padding` sets blank rows and columns inside the windows. `column_gap` separates the Tool, Enabled and Status columns. `gap` separates the list and details borders. `margin` keeps windows away from the editor edge. If the editor is too small, the margin, gap, vertical padding, horizontal padding and column gap shrink in that order. The configured values do not change.

`header_gap` sets blank rows between the category tabs, buffer scope and column headings. It defaults to `1`; use `0` for a dense header. It accepts nonnegative integers. Header gaps shrink first when the frame cannot fit them alongside useful content. Compact headers omit the gaps and column headings.

## Install and enable

`i` installs a Mason package or parser without enabling a disabled runtime tool. After an install, an enabled LSP server attaches to open buffers. Dependency packages support installation only.

Space toggles an LSP, DAP, formatter, linter or parser. Installed and externally managed tools update saved intent and runtime immediately. With `ui.missing_package_policy = "auto"`, a missing Mason package installs first. The tool is enabled only after success. Concurrent requests share one installation. A newer toggle supersedes pending intent. Older completion cannot restore superseded enablement. A failure keeps the enablement.

With `ui.missing_package_policy = "manual"`, a missing package is not installed and the tool stays disabled. An unknown package or an unavailable Mason registry reports a failure. Tools outside Mason need setup outside Mason. Leave out the `mason` field of such a tool, or set `source = "external"`.

Operations persist intent before runtime changes. A backend failure stays in details until a successful operation clears it. Installations continue after the view closes. Their callbacks cannot redraw a closed session or a replacement session.

## Status

| Status | Meaning |
| --- | --- |
| `Disabled` | Global saved enablement is off |
| `Installing…` | Mason installation is running |
| `Not installed` | Required package or parser is absent |
| `Broken install` | The Mason package directory has no receipt; install it again |
| `Unknown` | Registry or backend availability cannot be confirmed |
| `Not configured` / `Partly configured` | Runtime wiring is missing for part or all of the selected scope |
| `Activation not configured` | No formatter or linter activation is available |
| `Disabled, still listed under "*"` | The backend still runs the disabled tool through `*` or `_` |
| `Missing executable` | Command resolution failed |
| `Not active` | Saved enablement is on but runtime activation is absent |
| `Configured`, `Registered…`, `Running…`, `Idle` | Category-specific runtime health |
| `Diagnostics: …` | Findings in source code |
| `Failed` | An operation or a linter run failed |

Each status icon has its own highlight group:

- `HangarIconEnabled`
- `HangarIconIdle`
- `HangarIconInfo`
- `HangarIconInstalling`
- `HangarIconWarning`
- `HangarIconError`
- `HangarIconUnknown`
- `HangarIconDisabled`

Category tabs use `HangarCategoryActive` and `HangarCategoryInactive`. Each group links to a built-in group by default. To override a group, define it in your color scheme or configuration.

`HangarColumnHeader` styles column headings. `HangarContext` styles source context. `HangarSeparator` styles header and footer rules. They link to `Title`, `Comment` and `FloatBorder` by default.

Installation, management source, runtime health and enablement are distinct facts in details. Installation alone does not activate a tool. Supported filetypes do not override the initial formatter and linter activation.

Parser activity includes parsed injected languages, such as LuaDoc in Lua. Each highlighted buffer counts once per language, regardless of its injection regions.

## Priority and persistence

Use `[` / `]` on a formatter or linter in buffer scope or in an expanded filetype group. Priority applies per filetype. Enablement is global to the tool. Saved order includes disabled tools. It is restored when they are enabled again. Reordering preserves unrelated runtime entries.

The registry uses logical IDs. At runtime, adapters translate them to backend aliases through `runtime_name`, for example `yaml` to conform's `yamlfmt`.

State is stored in the file that `state_path` returns. Only this file is read. Missing or malformed state falls back to defaults. Valid values merge with the current definitions. Saved enablement stays for a tool that the view does not list now, because discovery depends on the loaded backends. The view lists only current tools. Stale or duplicate order entries are left out.

A write takes an exclusive lock and reads the disk state again. Then it merges the selected change and replaces the file atomically. Unrelated changes from another instance stay. If the replacement is refused, the old disk state stays and the requested runtime change does not apply. If the lock is busy, try again after its writer finishes. Locks record a PID and ownership token. Recovery requires a confirmed dead process. Live locks are never stolen because of age. Malformed locks and abandoned recovery guards require operator inspection. Confirm that no writer owns the state before removing them. A cleanup failure reports saved intent separately from unchanged runtime. A write from another instance does not refresh a view that is already open.

## Session lifetime

Nui owns windows and mounting. Each view owns subscriptions, debounce timers, source context and selection. Normal close, external window closure and buffer deletion dispose the session. Lists and details stay scrollable when the layout shrinks. See [architecture](architecture.md) for module boundaries.
