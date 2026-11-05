-- Gates conform's `formatters_by_ft` from saved state. Each table that
-- `conform.setup` builds becomes the formatter activation and is filtered in
-- place, before conform formats and on each Hangar snapshot.
local M = {}

---@param module? table conform, while it is still loading
local function sync(module)
  require("hangar.activation").sync("formatter", module)
end

---Sync the loaded module; a hook ignores the arguments of the call.
local function resync()
  sync()
end

---@param conform table
function M.apply(conform)
  local integrations = require("hangar.integrations")
  integrations.hook(conform, "setup", "after", resync)
  integrations.hook(conform, "format", "before", resync)
  sync(conform)
end

return M
