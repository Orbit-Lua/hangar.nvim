local M = {
  capabilities = { toggle = true, install = true, reorder = false },
}

---@param opts Hangar.ApplyRuntimeOpts
---@return nil
function M.apply_runtime(opts)
  local name, is_enabled = opts.name, opts.is_enabled
  if is_enabled then
    vim.lsp.enable(name)
    vim.notify(
      name .. " enabled — reopen the file to attach",
      vim.log.levels.INFO
    )
  else
    vim.lsp.enable(name, false)
    for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
      client:stop()
    end
    vim.notify(
      name .. " stopped (takes full effect next session)",
      vim.log.levels.INFO
    )
  end
end

---@param opts Hangar.StatusOpts
---@return string, string
function M.entry_status(opts)
  local name = opts.name
  if not vim.lsp.is_enabled(name) then
    return "disabled", "DiagnosticError"
  end

  local clients = vim.lsp.get_clients({ name = name })
  if #clients > 0 then
    return "running " .. #clients, "DiagnosticOk"
  else
    return "idle", "DiagnosticWarn"
  end
end

return M
