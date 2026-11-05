local M = {
  capabilities = { toggle = true, install = true, reorder = false },
}

local function integration()
  local config = require("hangar.config")
  return config.get().integrations.lsp and require("hangar.integrations.lsp")
    or nil
end

---Stop the clients of a server by its runtime name.
---@param name string
local function stop_clients(name)
  for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
    client:stop()
  end
end

---@param opts Hangar.ApplyRuntimeOpts
---@return nil
function M.apply_runtime(opts)
  local name = opts.meta.runtime_name or opts.name
  local lsp = integration()
  if opts.is_enabled then
    -- A plugin client starts on its own; the integration replays only an
    -- enable that it dropped.
    if lsp then
      lsp.enable(name)
    elseif not opts.meta.plugin then
      vim.lsp.enable(name)
    end
    vim.notify(
      name .. " enabled — reopen the file to attach",
      vim.log.levels.INFO
    )
    return
  end

  if lsp and not opts.meta.plugin then
    lsp.disable(name)
  else
    if not opts.meta.plugin then
      vim.lsp.enable(name, false)
    end
    stop_clients(name)
  end
  vim.notify(
    name .. " stopped (takes full effect next session)",
    vim.log.levels.INFO
  )
end

---Report `no binary` when the configured command is not executable. Neovim
---then refuses to start the server, so it never attaches.
---@param name string
---@return boolean
local function missing_executable(name)
  local ok, config = pcall(function()
    return vim.lsp.config[name]
  end)
  local cmd = ok and type(config) == "table" and config.cmd
  return type(cmd) == "table"
    and type(cmd[1]) == "string"
    and vim.fn.executable(cmd[1]) == 0
end

---A plugin client has no `vim.lsp.config` entry, so its status counts clients.
---@param opts Hangar.StatusOpts
---@return string, string
function M.entry_status(opts)
  local name = opts.meta.runtime_name or opts.name
  if not opts.meta.plugin and not vim.lsp.is_enabled(name) then
    return "disabled", "DiagnosticError"
  end

  local clients = vim.lsp.get_clients({ name = name })
  if #clients > 0 then
    return "running " .. #clients, "DiagnosticOk"
  elseif not opts.meta.plugin and missing_executable(name) then
    return "no binary", "DiagnosticWarn"
  else
    return "idle", "DiagnosticWarn"
  end
end

return M
