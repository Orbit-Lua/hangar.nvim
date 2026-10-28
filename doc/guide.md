# Guide

## Setup

`require("hangar").setup(opts)` validates the options and fills defaults. Only `registry` is required. A category or default-order table that the registry omits becomes empty, so every category can be browsed.

A caller's `ui` table stays the same object. Setup adds only its missing keys. `icons` gets the same treatment. To change the view options later, call `require("hangar").update_ui(values)`. A key that `values` omits takes its default. An open view then rebinds its keys and redraws. The selected category stays selected. If the new options remove it, the first category is selected. `categories` must name at least one known category. You can also change the `ui` table yourself and then fire `User HangarChanged`.

Use before setup raises an error that names `hangar.setup`. A repeated setup replaces the options, drops cached state and failures, and closes the open view. It is rejected while a toggle or an installation runs.

| Adapter | Contract |
| --- | --- |
| `adapters.activation.formatter` / `.linter` | Returns the initial runtime names by filetype. Re-enabling a tool restores it only where this list activates it. Optional: see [Formatters and linters](#formatters-and-linters). |
| `adapters.dap` | `runtime()` returns `apply_adapter(dap, name, enabled, options)` and `adapter_status(dap, name)`. `options()` returns the adapter definitions. |
| `adapters.linter.logs(name)` | Returns run errors for a linter. Each entry has `level`, `message` and optional `tags.kind`. |

Without a DAP owner, DAP status shows `no DAP owner configured`, and hangar changes no saved state.

## Formatters and linters

hangar needs the initial runtime names by filetype. It takes them from the first available source:

1. `adapters.activation`, read on each use.
2. The table that the last `require("hangar").filter(category, by_ft)` call received.
3. The backend lists, conform's `formatters_by_ft` or nvim-lint's `linters_by_ft`, captured at first use.

A captured list also takes names that the backend list gains later. A repeated setup keeps the list, so a tool that you disabled before can be enabled again. After setup without `adapters.activation`, hangar continues from the last injected lists.

hangar changes only the backend lists at runtime. To keep enablement and order after a restart, wrap the lists in `filter`. It returns a copy without disabled tools and in saved order. Unregistered names stay after the registered ones. Call it after setup.

Without a saved order, the initial order is the priority. A tool that you enable again returns to its position.

hangar keeps conform option keys such as `stop_after_first`. It leaves function entries and the `*` and `_` keys unchanged. Conform still runs a disabled tool that `*` or `_` lists. Its status shows `Disabled, still listed under "*"`.

If no source is available, status shows `Activation not configured`. Toggle and reorder then return an error, and hangar changes no saved state.

## Navigation

`require("hangar").open()` focuses the existing view if one is open. A new session captures the filetype and filename of the source buffer. `s` switches between that buffer and all registered tools.

Use `1`–`6` or Tab / Shift-Tab to select LSP, DAP, Linter, Formatter, Parser or Package. Number keys and help follow `ui.categories`, and footer hints follow `ui.mappings`. Buffer-scope formatter and linter lists show saved ranks. All-state lists group by filetype. Expand a group with `o`, Enter or `za`.

Logical selection survives reordering, resizing and refreshes. Category and expansion choices survive reopening. Help (`?` or `g?`) suspends tool actions and stays visible during refresh. Beside or below the list, details stay open and follow the cursor. They show the selected tool, a filetype group, an empty category or the category overview with an icon legend. `K` focuses details from any row. `q` or Escape returns to the list and keeps details open. If the editor is too narrow, `K` opens details on demand, and `q` closes them.

## Layout

`ui.layout` sets the spacing in cells. `padding` sets blank rows and columns inside the windows. `column_gap` separates the Tool, Enabled and Status columns. `gap` separates the list and details borders. `margin` keeps windows away from the editor edge. If the editor is too small, the margin, gap, vertical padding, horizontal padding and column gap shrink in that order. The configured values do not change.

## Install and enable

`i` installs a Mason package or parser without enabling a disabled runtime tool. Parsers and dependency packages support installation only.

Space toggles an LSP, DAP, formatter or linter. Installed and externally managed tools update saved intent and runtime immediately. With `ui.missing_package_policy = "auto"`, a missing Mason package installs first. The tool is enabled only after success. Concurrent requests share one installation. A newer toggle supersedes pending intent. Older completion cannot restore superseded enablement. A failure keeps the enablement.

With `ui.missing_package_policy = "manual"`, a missing package is not installed and the tool stays disabled. An unknown package or an unavailable registry reports a failure. Tools outside Mason need setup outside Mason. Mark such a tool with `mason = nil` in the registry.

Operations persist intent before runtime changes. A backend failure stays in details until a successful operation clears it. Installations continue after the view closes. Their callbacks cannot redraw a closed session or a replacement session.

## Status

| Status | Meaning |
| --- | --- |
| `Disabled` | Global saved enablement is off |
| `Installing…` | Mason installation is running |
| `Not installed` | Required package or parser is absent |
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

Installation, management source, runtime health and enablement are distinct facts in details. Installation alone does not activate a tool. Supported filetypes do not override the initial formatter and linter activation.

## Priority and persistence

Use `[` / `]` on a formatter or linter in buffer scope or in an expanded filetype group. Priority applies per filetype. Enablement is global to the tool. Saved order includes disabled tools. It is restored when they are enabled again. Reordering preserves unrelated runtime entries.

The registry uses logical IDs. At runtime, adapters translate them to backend aliases through `runtime_name`, for example `yaml` to conform's `yamlfmt`.

State is stored in the file that `state_path` returns. If the file is missing, hangar reads `legacy_state_path` when one is set. A malformed state falls back to defaults. Valid values merge with the current definitions. Removed tools and stale or duplicate order entries are left out.

A write takes an exclusive lock and reads the disk state again. Then it merges the selected change and replaces the file atomically. Unrelated changes from another instance stay. If the replacement is refused, the old disk state stays and the requested runtime change does not apply. If the lock is busy, try again after its writer finishes. Locks record a PID and ownership token. Recovery requires a confirmed dead process. Live locks are never stolen because of age. Malformed locks and abandoned recovery guards require operator inspection. Confirm that no writer owns the state before removing them. A cleanup failure reports saved intent separately from unchanged runtime. A write from another instance does not refresh a view that is already open.

## Session lifetime

Nui owns windows and mounting. Each view owns subscriptions, debounce timers, source context and selection. Normal close, external window closure and buffer deletion dispose the session. Lists and details stay scrollable when the layout shrinks. See [architecture](architecture.md) for module boundaries.
