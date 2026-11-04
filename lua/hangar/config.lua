---@alias Hangar.Category "lsp"|"dap"|"linter"|"formatter"|"parser"|"package"

---@tag hangar-options
---@text
--- Options of |hangar.setup()|. Every option is optional.
---@class Hangar.Options
---@field registry? Hangar.Registry install mapping and metadata (|hangar-registry|)
---@field defaults? fun(): { formatter?: table<string, string[]>, linter?: table<string, string[]> } user default orders
---@field state_path? fun(): string
---@field ui? table view options (|hangar-ui|)
---@field icons? table<string, string>
---@field border? any
---@field adapters? Hangar.Adapters
---@field integrations? Hangar.Integrations backends that hangar gates (|hangar-integrations|)

---@tag hangar-integrations
---@text
--- Backends that hangar gates from saved state. Each one defaults to `true`;
--- set it to `false` to leave that backend alone. Hangar applies the conform,
--- nvim-lint and nvim-dap integrations when the plugin loads, so hangar must be
--- set up before them.
---@class Hangar.Integrations
---@field lsp? boolean `vim.lsp.enable` and clients of disabled servers
---@field dap? boolean debug sessions of disabled adapters
---@field conform? boolean conform `formatters_by_ft`
---@field lint? boolean nvim-lint `linters_by_ft`
---@field treesitter? boolean Tree-sitter highlighting of disabled parsers

---@tag hangar-adapters
---@text
--- Owners that hangar calls for runtime changes.
---@class Hangar.Adapters
---@field linter? { logs?: fun(name: string): table[] } run errors recorded for a linter

local registry_spec = require("hangar.registry")

local M = {}

M.categories = registry_spec.categories

M.integrations = { "lsp", "dap", "conform", "lint", "treesitter" }

---@type Hangar.Options?
local options

---@tag hangar-ui
---@text
--- View options. |hangar.setup()| fills the keys that `ui` omits. Replace them
--- later with |hangar.update_ui()|.
---
--- - `categories`: category names in tab order; a nonempty list.
--- - `labels`: tab label by category.
--- - `mappings`: list of `{ keys, action, description }`.
--- - `width`, `height`, `details.width`: window sizes in cells.
--- - `layout`: `padding.vertical`, `padding.horizontal`, `column_gap`, `gap`
---   and `margin` in cells.
--- - `missing_package_policy`: `"auto"` or `"manual"`.

local function default_ui()
  return {
    categories = { "lsp", "dap", "linter", "formatter", "parser", "package" },
    labels = {
      lsp = "LSP",
      dap = "DAP",
      linter = "Linter",
      formatter = "Formatter",
      parser = "Parser",
      package = "Package",
    },
    -- The view installs these mappings and renders the same descriptions in help.
    mappings = {
      {
        keys = { "q", "<Esc>" },
        action = "close",
        description = "Close Hangar",
      },
      { keys = { "?", "g?" }, action = "help", description = "Toggle help" },
      {
        keys = { "s" },
        action = "scope",
        description = "Current buffer / all tool states",
      },
      { keys = { "<Tab>" }, action = "next", description = "Next category" },
      {
        keys = { "<S-Tab>" },
        action = "previous",
        description = "Previous category",
      },
      {
        keys = { "<Space>" },
        action = "toggle",
        description = "Enable / disable selected tool",
      },
      {
        keys = { "i" },
        action = "install",
        description = "Install selected tool",
      },
      {
        keys = { "[" },
        action = "up",
        description = "Move formatter / linter earlier",
      },
      {
        keys = { "]" },
        action = "down",
        description = "Move formatter / linter later",
      },
      {
        keys = { "o", "<CR>", "za" },
        action = "expand",
        description = "Expand / collapse entry",
      },
      { keys = { "K" }, action = "details", description = "Show tool details" },
    },
    details = {
      max_messages = 8,
      width = 54,
    },
    height = 40,
    layout = {
      column_gap = 3,
      gap = 2,
      margin = 2,
      padding = {
        horizontal = 2,
        vertical = 0,
      },
    },
    missing_package_policy = "auto",
    refresh = {
      debounce_ms = 500,
    },
    width = 120,
  }
end

local function default_icons()
  return {
    enabled = "",
    idle = "",
    installing = "",
    unknown = "",
    info = "",
    disabled = "",
    warning = "",
    error = "",
    expanded = "",
    collapsed = "",
  }
end

local function check(value, kind, path, optional)
  if optional and value == nil then
    return
  end
  if type(value) ~= kind then
    error("hangar.setup: " .. path .. " must be a " .. kind, 4)
  end
end

local function validate(opts)
  check(opts, "table", "options")
  check(opts.defaults, "function", "defaults", true)
  check(opts.state_path, "function", "state_path", true)
  check(opts.ui, "table", "ui", true)
  check(opts.icons, "table", "icons", true)
  local adapters = opts.adapters or {}
  check(adapters, "table", "adapters")
  if adapters.dap ~= nil then
    error(
      "hangar.setup: adapters.dap was removed; the dap integration gates debug sessions",
      3
    )
  end
  if adapters.activation ~= nil then
    error(
      "hangar.setup: adapters.activation was removed; use the conform and lint integrations or hangar.filter",
      3
    )
  end
  check(adapters.linter, "table", "adapters.linter", true)
  check((adapters.linter or {}).logs, "function", "adapters.linter.logs", true)
  check(opts.integrations, "table", "integrations", true)
  for key, value in pairs(opts.integrations or {}) do
    if not vim.tbl_contains(M.integrations, key) then
      error(
        "hangar.setup: integrations."
          .. tostring(key)
          .. " is not an integration",
        3
      )
    end
    check(value, "boolean", "integrations." .. key)
  end
end

---Fill missing keys in place, so the caller keeps its table reference.
local function fill(target, defaults)
  for key, value in pairs(defaults) do
    if target[key] == nil then
      target[key] = vim.deepcopy(value)
    elseif
      type(target[key]) == "table"
      and type(value) == "table"
      and not vim.islist(value)
    then
      fill(target[key], value)
    end
  end
  return target
end

---A view needs at least one category, and each must be one hangar knows.
local function check_categories(categories, path)
  local valid = type(categories) == "table"
    and vim.islist(categories)
    and #categories > 0
  for _, category in ipairs(valid and categories or {}) do
    valid = valid and vim.tbl_contains(M.categories, category)
  end
  if not valid then
    error(
      path .. " must be a nonempty list of " .. table.concat(M.categories, ", "),
      4
    )
  end
end

---Validate options and apply defaults. The registry gets every category and
---default-order table, so a partial registry can browse all categories.
---@param opts? Hangar.Options
---@return Hangar.Options
function M.resolve(opts)
  opts = opts or {}
  validate(opts)
  local registry = registry_spec.resolve(opts.registry)
  local adapters = opts.adapters or {}
  local integrations = {}
  for _, key in ipairs(M.integrations) do
    integrations[key] = (opts.integrations or {})[key] ~= false
  end
  local ui = fill(opts.ui or {}, default_ui())
  check_categories(ui.categories, "hangar.setup: ui.categories")
  return {
    registry = registry,
    defaults = opts.defaults or function()
      return {}
    end,
    state_path = opts.state_path or function()
      return vim.fn.stdpath("data") .. "/hangar.json"
    end,
    ui = ui,
    icons = fill(opts.icons or {}, default_icons()),
    border = opts.border or "rounded",
    integrations = integrations,
    adapters = {
      linter = {
        logs = (adapters.linter or {}).logs or function()
          return {}
        end,
      },
    },
  }
end

---Build view options from `values` and the defaults, so a key that `values`
---omits returns to its default.
---@param values table
---@return table
function M.resolve_ui(values)
  if type(values) ~= "table" then
    error("hangar.update_ui: values must be a table", 3)
  end
  local ui = fill(vim.deepcopy(values), default_ui())
  check_categories(ui.categories, "hangar.update_ui: categories")
  return ui
end

---@return Hangar.Options
function M.get()
  if not options then
    error("hangar is not configured: call hangar.setup() first", 2)
  end
  return options
end

---@return boolean
function M.configured()
  return options ~= nil
end

---@param resolved Hangar.Options
function M.set(resolved)
  options = resolved
end

return M
