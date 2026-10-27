local M = {
  capabilities = { toggle = true, install = true, reorder = false },
}

local config = require("hangar.config")

local MISSING_OWNER = "no DAP owner configured: inject adapters.dap"

---Report why runtime changes cannot apply, before any state is saved.
function M.unavailable()
  if not config.get().adapters.dap then
    return MISSING_OWNER
  end
end

function M.apply_runtime(opts)
  local dap_ok, dap = pcall(require, "dap")
  if not dap_ok then
    return false, "nvim-dap is unavailable: " .. tostring(dap)
  end
  local owner = config.get().adapters.dap
  if not owner then
    return false, MISSING_OWNER
  end
  return owner
    .runtime()
    .apply_adapter(dap, opts.name, opts.is_enabled, owner.options())
end

function M.entry_status(opts)
  local dap_ok, dap = pcall(require, "dap")
  if not dap_ok then
    return nil, nil
  end
  local owner = config.get().adapters.dap
  if not owner then
    return "no DAP owner configured", "DiagnosticWarn"
  end
  return owner.runtime().adapter_status(dap, opts.name)
end

return M
