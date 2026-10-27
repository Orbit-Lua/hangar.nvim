local M = {}

---Truncate to a display width, ending with an ellipsis when text is cut.
---@param s string
---@param max_w integer
---@return string
function M.trunc(s, max_w)
  local ellipsis = "…"
  if max_w <= 0 then
    return ""
  end
  if vim.fn.strdisplaywidth(s) <= max_w then
    return s
  end

  local ellipsis_w = vim.fn.strdisplaywidth(ellipsis)
  if max_w <= ellipsis_w then
    return vim.fn.strcharpart(ellipsis, 0, max_w)
  end

  local result = ""
  for i = 0, vim.fn.strchars(s) - 1 do
    local char = vim.fn.strcharpart(s, i, 1)
    local candidate = result .. char
    if vim.fn.strdisplaywidth(candidate) + ellipsis_w > max_w then
      break
    end
    result = candidate
  end

  return result .. ellipsis
end

---Pad with spaces on the right to a display width.
---@param s string
---@param w integer
---@return string
function M.rpad(s, w)
  local dw = vim.fn.strdisplaywidth(s)
  return dw < w and (s .. string.rep(" ", w - dw)) or s
end

---Write a complete file beside its destination, then atomically replace it.
---@param path string
---@param contents string
---@return boolean, string?, string?
function M.atomic_write(path, contents)
  local parent = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(parent) == 0 then
    local mkdir_ok, created = pcall(vim.fn.mkdir, parent, "p")
    if not mkdir_ok then
      return false, tostring(created)
    end
    if created == 0 and vim.fn.isdirectory(parent) == 0 then
      return false, "failed to create parent directory: " .. parent
    end
  end

  local file, temporary, open_code = vim.uv.fs_mkstemp(path .. ".hangar-XXXXXX")
  if not file then
    return false, temporary, open_code
  end
  local offset, write_error = 0, nil
  while offset < #contents do
    local written, err = vim.uv.fs_write(file, contents:sub(offset + 1), offset)
    if not written or written == 0 then
      write_error = err or "temporary write made no progress"
      break
    end
    offset = offset + written
  end
  local closed, close_error = vim.uv.fs_close(file)
  if write_error or not closed then
    vim.uv.fs_unlink(temporary)
    return false, write_error or close_error
  end

  local renamed, rename_error, code = vim.uv.fs_rename(temporary, path)
  if not renamed then
    local cleaned, cleanup_error = vim.uv.fs_unlink(temporary)
    if not cleaned then
      return false, "temporary cleanup failed: " .. tostring(cleanup_error)
    end
    return false, rename_error, code
  end
  return true
end

return M
