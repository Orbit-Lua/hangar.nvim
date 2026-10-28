---@tag hangar.txt hangar hangar.nvim
---@text
--- Manage language servers, debug adapters, formatters, linters, Tree-sitter
--- parsers and Mason packages from one view.
---
--- This help lists the public interface. The guide in `doc/guide.md` of the
--- repository describes the view, statuses, locks and session behavior.

local M = {}
local view
local state = { category = 1, expanded = {} }

---@tag hangar.close()
---@signature hangar.close()
---@text
--- Close the open view. Running operations continue.
function M.close()
  if view then
    view:close()
  end
end

---@tag hangar.setup()
---@signature hangar.setup(opts)
---@text
--- Validate {opts} and fill the defaults. Only `registry` is required. See
--- |hangar-options|.
---
--- A repeated call replaces the options, drops cached state and failures, and
--- closes the open view. It raises an error while a toggle or an installation
--- runs.
---@param opts Hangar.Options
function M.setup(opts)
  local config = require("hangar.config")
  local resolved = config.resolve(opts)
  if config.configured() then
    local manager = require("hangar.manager")
    if manager.busy() then
      error(
        "hangar.setup: an operation is in flight; retry after it finishes",
        2
      )
    end
    M.close()
    manager.reset()
    require("hangar.state").reset()
    state = { category = 1, expanded = {} }
  end
  config.set(resolved)
end

---@tag hangar.filter()
---@signature hangar.filter(category, by_ft)
---@text
--- Apply saved enablement and order to a table of tool names by filetype.
--- Use it for conform's `formatters_by_ft` and nvim-lint's `linters_by_ft`, so
--- intent from the view persists across restarts without an adapter.
---
--- Returns a new table. {by_ft} becomes the activation that re-enabling
--- restores. Unregistered names stay after the registered ones. Option keys,
--- function entries and the `*` and `_` keys stay unchanged.
---
--- Call it after |hangar.setup()|.
---@param category string `"formatter"` or `"linter"`
---@param by_ft table<string, any> tool names by filetype
---@return table<string, any>
---@usage >lua
---   opts = {
---     formatters_by_ft = require("hangar").filter("formatter", {
---       lua = { "stylua" },
---     }),
---   }
--- <
function M.filter(category, by_ft)
  require("hangar.config").get()
  if category ~= "formatter" and category ~= "linter" then
    error('hangar.filter: category must be "formatter" or "linter"', 2)
  end
  if type(by_ft) ~= "table" then
    error("hangar.filter: by_ft must be a table", 2)
  end
  local activation = require("hangar.activation")
  local order = require("hangar.order")
  activation.record(category, by_ft)
  local result = {}
  for ft, entry in pairs(by_ft) do
    local names = activation.names(entry)
    if not names or ft == "*" or ft == "_" then
      result[ft] = vim.deepcopy(entry)
    else
      local enabled = order.enabled_names_for_ft(
        category,
        ft,
        order.from_runtime(category, names)
      )
      local filtered = order.to_runtime(category, enabled)
      for key, value in pairs(entry) do
        if type(key) ~= "number" then
          filtered[key] = vim.deepcopy(value)
        end
      end
      result[ft] = filtered
    end
  end
  return result
end

---@tag hangar.update_ui()
---@signature hangar.update_ui(values)
---@text
--- Replace the view options with {values}. A key that {values} omits takes
--- its default. An open view rebinds its keys and redraws. See |hangar-ui|.
---
--- It raises an error when `categories` is empty or names an unknown category.
---@param values table
function M.update_ui(values)
  local config = require("hangar.config")
  local resolved = config.resolve_ui(values)
  config.get().ui = resolved
  vim.api.nvim_exec_autocmds("User", { pattern = "HangarChanged" })
end

---@tag hangar.open()
---@signature hangar.open()
---@text
--- Open the view for the current buffer, or focus the open view.
function M.open()
  if view and view:active() then
    vim.api.nvim_set_current_win(view.body.winid)
    return
  end
  M.close()
  local buffer = vim.api.nvim_get_current_buf()
  local source = {
    bufnr = buffer,
    filetype = vim.bo[buffer].filetype,
    name = vim.api.nvim_buf_get_name(buffer),
  }
  state.scope = "buffer"
  state.help = false
  require("hangar.ui.view").normalize(state)
  view = require("hangar.ui.view").new(source, state, function(closed)
    if view == closed then
      view = nil
    end
  end)
end

---@tag hangar-events
---@text
--- `User HangarChanged`
--- An open view redraws when this event fires. |hangar.update_ui()| fires it.
--- Fire it yourself after you change the `ui` table that you passed to
--- |hangar.setup()|.

---@tag hangar-highlights
---@text
--- Each status icon has its own group: `HangarIconEnabled`, `HangarIconIdle`,
--- `HangarIconInfo`, `HangarIconInstalling`, `HangarIconWarning`,
--- `HangarIconError`, `HangarIconUnknown` and `HangarIconDisabled`.
---
--- Category tabs use `HangarCategoryActive` and `HangarCategoryInactive`.
---
--- Each group links to a built-in group by default. To override a group,
--- define it in your color scheme or configuration.

return M
