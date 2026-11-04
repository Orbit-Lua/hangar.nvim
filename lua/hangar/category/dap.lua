local M = {
  capabilities = { toggle = true, install = true, reorder = false },
}

local config = require("hangar.config")

---Report why a toggle cannot apply, before any state is saved.
---@return string?
function M.unavailable()
  if not config.get().integrations.dap then
    return "the dap integration is off (integrations.dap = false)"
  end
end

---The `dap.listeners.on_config` gate reads saved state at each session start,
---so a toggle needs no runtime change.
---@param opts Hangar.ApplyRuntimeOpts
---@return boolean
function M.apply_runtime(opts)
  local verb = opts.is_enabled and "enabled" or "disabled"
  vim.notify(
    "debug adapter " .. opts.name .. " " .. verb .. " for new sessions",
    vim.log.levels.INFO
  )
  return true
end

---@param dap table
---@param name string
---@return integer
local function count_configurations(dap, name)
  local count = 0
  for _, configurations in pairs(dap.configurations or {}) do
    for _, entry in ipairs(configurations) do
      if type(entry) == "table" and entry.type == name then
        count = count + 1
      end
    end
  end
  return count
end

---@param opts Hangar.StatusOpts
---@return string?, string?
function M.entry_status(opts)
  local dap_ok, dap = pcall(require, "dap")
  if not dap_ok or type(dap) ~= "table" then
    return nil, nil
  end
  if
    config.get().integrations.dap
    and not require("hangar.state").is_enabled("dap", opts.name)
  then
    return "disabled", "DiagnosticError"
  end

  local registered = type(dap.adapters) == "table"
    and dap.adapters[opts.name] ~= nil
  local count = count_configurations(dap, opts.name)
  local label = string.format(
    "%s %d cfg",
    registered and "registered" or "not registered",
    count
  )
  if not registered then
    return label, "DiagnosticError"
  elseif count == 0 then
    return label, "DiagnosticWarn"
  end
  return label, "DiagnosticOk"
end

return M
