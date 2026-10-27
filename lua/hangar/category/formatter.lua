local M = require("hangar.category.list").new({
  module = "conform",
  field = "formatters_by_ft",
  category = "formatter",
})

local function command_not_found(message)
  return type(message) == "string" and message:match("^Command '.+' not found$")
end

local function executable_status(conform, name, bufnr)
  if type(conform.get_formatter_info) ~= "function" then
    return nil, nil
  end

  local function inspect()
    return conform.get_formatter_info(name, bufnr)
  end
  local ok, info
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    ok, info = pcall(vim.api.nvim_buf_call, bufnr, inspect)
  else
    ok, info = pcall(inspect)
  end
  if not ok or type(info) ~= "table" then
    return nil, nil
  end

  if info.available == false and command_not_found(info.available_msg) then
    return "no binary", "DiagnosticError"
  end
  return nil, nil
end

---@param opts Hangar.StatusOpts
---@return string?, string?
function M.entry_status(opts)
  local conform_ok, conform = pcall(require, "conform")
  if not conform_ok then
    return nil, nil
  end

  local wiring_text, wiring_hl = M.wiring_status(opts)
  if wiring_text then
    return wiring_text, wiring_hl
  end

  local executable_text, executable_hl =
    executable_status(conform, opts.meta.runtime_name or opts.name, opts.bufnr)
  if executable_text then
    return executable_text, executable_hl
  end

  return "configured", "DiagnosticOk"
end

return M
