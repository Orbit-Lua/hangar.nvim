-- Gates nvim-lint from saved state. Each `linters_by_ft` table that the
-- consumer assigns becomes the linter activation and is filtered in place,
-- before nvim-lint runs and on each Hangar snapshot. `try_lint(names)` drops
-- the disabled linters that a caller names.
local M = {}

---@param module? table nvim-lint, while it is still loading
local function sync(module)
  require("hangar.activation").sync("linter", module)
end

---Drop disabled linters from explicit `try_lint` names. Names that the
---registry does not know pass.
---@param names string|string[]|nil
---@return table? arguments that replace the call arguments
local function gate(names, ...)
  sync()
  local config = require("hangar.config")
  if
    names == nil
    or not config.configured()
    or not config.get().integrations.lint
  then
    return nil
  end
  local list = type(names) == "string" and { names } or names
  if type(list) ~= "table" then
    return nil
  end
  local order = require("hangar.order")
  local state = require("hangar.state")
  local kept = {}
  for _, name in ipairs(list) do
    local logical = order.from_runtime("linter", { name })[1] or name
    if state.is_enabled("linter", logical) then
      table.insert(kept, name)
    end
  end
  return vim.F.pack_len(kept, ...)
end

---@param lint table
function M.apply(lint)
  require("hangar.integrations").hook(lint, "try_lint", "before", gate)
  sync(lint)
end

return M
