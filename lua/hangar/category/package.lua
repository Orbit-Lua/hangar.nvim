local M = {
  capabilities = { toggle = false, install = true, reorder = false },
}

local mason = require("hangar.mason")

---@param name string
---@param on_done fun(success: boolean, err?: string)?
---@return boolean
function M.install(name, on_done)
  return mason.install(name, on_done)
end

return M
