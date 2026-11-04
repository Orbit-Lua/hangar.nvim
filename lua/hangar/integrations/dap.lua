-- Gates debug sessions from saved state. One `dap.listeners.on_config` entry
-- stops each session whose adapter type is disabled. It gates at session start,
-- not at registration, because a consumer can reassign `dap.adapters` at any
-- time. The listener reads the options per call, so a repeated setup or
-- `integrations.dap = false` changes behavior without a second listener.
local M = {}

local LISTENER = "hangar"

---@param type_name string
---@return boolean
local function disabled(type_name)
  local config = require("hangar.config")
  return config.configured()
    and config.get().integrations.dap
    and not require("hangar.state").is_enabled("dap", type_name)
end

---Abort a configuration of a disabled adapter type. nvim-dap shows an error
---raised here only as a traceback, so the gate notifies and returns the
---public `dap.ABORT` sentinel in a copy of the configuration instead.
---@param dap table
---@param run_config table
---@return table
function M.gate(dap, run_config)
  if type(run_config) ~= "table" or type(run_config.type) ~= "string" then
    return run_config
  end
  if not disabled(run_config.type) then
    return run_config
  end

  vim.notify(
    "Hangar: debug adapter " .. run_config.type .. " is disabled in Hangar",
    vim.log.levels.ERROR
  )
  return vim.tbl_extend("force", run_config, { hangar = dap.ABORT })
end

---@param dap table
function M.apply(dap)
  if
    type(dap.listeners) ~= "table" or type(dap.listeners.on_config) ~= "table"
  then
    return
  end
  dap.listeners.on_config[LISTENER] = function(run_config)
    return require("hangar.integrations.dap").gate(dap, run_config)
  end
end

return M
