local M = require("hangar.category.list").new({
  module = "lint",
  field = "linters_by_ft",
  category = "linter",
})

local config = require("hangar.config")
local health = require("hangar.health")

local function executable_status(name)
  local lint_ok, lint = pcall(require, "lint")
  if not lint_ok or type(lint.linters) ~= "table" then
    return nil, nil
  end

  local linter = lint.linters[name]
  if not linter then
    return nil, nil
  end

  local err = health.executable_error(linter)
  if err then
    return "no binary", "DiagnosticError"
  end
  return nil, nil
end

---@class Hangar.LinterDiagnosticMessage
---@field file string
---@field lnum integer
---@field col integer
---@field severity integer
---@field message string

---@class Hangar.LinterDiagnosticSummary
---@field error_count integer
---@field warn_count integer
---@field messages Hangar.LinterDiagnosticMessage[]

---Counts E/W diagnostics and collects messages for `linter_name` across all
---loaded buffers. Queries by nvim-lint's namespace (keyed by linter name) to
---avoid source-name mismatches (e.g. markdownlint-cli2 uses source "markdownlint").
---@param linter_name string
---@return Hangar.LinterDiagnosticSummary
function M.get_linter_diagnostics(linter_name)
  local ns_id = vim.api.nvim_get_namespaces()[linter_name]
  if not ns_id then
    return { error_count = 0, warn_count = 0, messages = {} }
  end

  local error_count = 0
  local warn_count = 0
  local messages = {}

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      for _, diagnostic in
        ipairs(vim.diagnostic.get(bufnr, { namespace = ns_id }))
      do
        if diagnostic.severity == vim.diagnostic.severity.ERROR then
          error_count = error_count + 1
        elseif diagnostic.severity == vim.diagnostic.severity.WARN then
          warn_count = warn_count + 1
        end
        table.insert(messages, {
          file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t"),
          lnum = diagnostic.lnum + 1,
          col = diagnostic.col + 1,
          severity = diagnostic.severity,
          message = diagnostic.message,
        })
      end
    end
  end

  table.sort(messages, function(a, b)
    if a.severity ~= b.severity then
      return a.severity < b.severity
    end
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.lnum < b.lnum
  end)

  return {
    error_count = error_count,
    warn_count = warn_count,
    messages = messages,
  }
end

---@param opts Hangar.StatusOpts
---@return string, string
function M.entry_status(opts)
  local name = opts.name
  local wire_text, wire_hl = M.wiring_status(opts)
  if wire_text then
    return wire_text, wire_hl
  end

  local executable_text, executable_hl = executable_status(name)
  if executable_text then
    return executable_text, executable_hl
  end

  local run_errors = config.get().adapters.linter.logs(name)
  if #run_errors > 0 then
    local latest_error = run_errors[#run_errors]
    local status_text
    if latest_error.tags and latest_error.tags.kind == "binary_not_found" then
      status_text = "no binary"
    elseif
      latest_error.tags
      and latest_error.tags.kind == "definition_not_found"
    then
      status_text = "missing definition"
    else
      status_text = "error"
    end
    return status_text, "DiagnosticError"
  end
  local summary = M.get_linter_diagnostics(name)
  if summary.error_count > 0 then
    return summary.error_count .. "E " .. summary.warn_count .. "W",
      "DiagnosticError",
      { diagnostics = summary }
  elseif summary.warn_count > 0 then
    return summary.warn_count .. "W",
      "DiagnosticWarn",
      { diagnostics = summary }
  else
    return "ok", "DiagnosticOk"
  end
end

return M
