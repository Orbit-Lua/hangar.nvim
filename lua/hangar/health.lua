local M = {}

---@param tool any
---@param command_field? string
---@return string? cmd, string? err
function M.resolve_cmd(tool, command_field)
  command_field = command_field or "cmd"
  -- nvim-lint accepts factories that build the linter for the current buffer.
  if type(tool) == "function" then
    local ok, built = pcall(tool)
    if not ok then
      return nil, "definition failed: " .. tostring(built)
    end
    tool = built
  end
  if type(tool) ~= "table" or not tool[command_field] then
    return nil, nil
  end

  local cmd = tool[command_field]
  if type(cmd) == "function" then
    local ok, resolved = pcall(cmd)
    if not ok then
      return nil, "command resolution failed: " .. tostring(resolved)
    end
    cmd = resolved
  end

  if type(cmd) ~= "string" or cmd == "" then
    return nil, nil
  end

  return cmd, nil
end

---@param tool any
---@param command_field? string
---@return string? message, string? cmd
function M.executable_error(tool, command_field)
  local cmd, err = M.resolve_cmd(tool, command_field)
  if err then
    return err, nil
  end
  if cmd and vim.fn.executable(cmd) ~= 1 then
    return "binary not found: " .. cmd, cmd
  end
  return nil, cmd
end

return M
