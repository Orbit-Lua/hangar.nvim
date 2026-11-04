-- Gates nvim-lint's `linters_by_ft` from saved state. Each table that the
-- consumer assigns becomes the linter activation and is filtered in place,
-- before nvim-lint runs and on each Hangar snapshot.
local M = {}

---@param module? table nvim-lint, while it is still loading
local function sync(module)
  require("hangar.activation").sync("linter", module)
end

---@param lint table
function M.apply(lint)
  require("hangar.integrations").hook(lint, "try_lint", "before", sync)
  sync(lint)
end

return M
