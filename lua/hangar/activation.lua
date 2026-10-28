-- Initial runtime names by filetype for formatters and linters. Re-enabling a
-- tool restores it only where this activation lists it, and default order
-- follows it. The session list outlives a repeated setup because the backend
-- still holds the lists that hangar changed.
local M = {}

local backends = {
  formatter = { module = "conform", field = "formatters_by_ft" },
  linter = { module = "lint", field = "linters_by_ft" },
}

-- Conform's "*" and "_" keys are not filetypes; hangar leaves them alone.
M.special_keys = { "*", "_" }

---@type table<string, { kind: "injected"|"record"|"capture", lists: table<string, string[]> }>
local sessions = {}

local function is_special(ft)
  return ft == "*" or ft == "_"
end

---Runtime names of a backend entry, or nil for a function-valued entry.
---@param entry any
---@return string[]?
function M.names(entry)
  if type(entry) ~= "table" then
    return nil
  end
  local names = {}
  for _, name in ipairs(entry) do
    if type(name) == "string" then
      table.insert(names, name)
    end
  end
  return names
end

local function snapshot(by_ft)
  local lists = {}
  for ft, entry in pairs(by_ft or {}) do
    local names = not is_special(ft) and M.names(entry)
    if names then
      lists[ft] = names
    end
  end
  return lists
end

---@param category "formatter"|"linter"
---@return table?, string? backend `*_by_ft` table, or why it is unavailable
function M.backend(category)
  local spec = backends[category]
  local ok, module = pcall(require, spec.module)
  if not ok then
    return nil, tostring(module)
  end
  if type(module) ~= "table" or type(module[spec.field]) ~= "table" then
    return nil, spec.module .. "." .. spec.field .. " is not a table"
  end
  return module[spec.field]
end

---Record the lists that a caller passes through `hangar.filter`.
---@param category "formatter"|"linter"
---@param by_ft table
function M.record(category, by_ft)
  sessions[category] = { kind = "record", lists = snapshot(by_ft) }
end

---Read the activation lists of a category. Injected activation wins and
---refreshes the session list; otherwise the recorded list is used as is, and a
---captured list merges names that the live backend gained.
---@param category "formatter"|"linter"
---@return table<string, string[]>?
function M.get(category)
  local injected = require("hangar.config").get().adapters.activation[category]
  if injected then
    local lists = snapshot(injected())
    sessions[category] = { kind = "injected", lists = lists }
    return lists
  end
  local session = sessions[category]
  if session and session.kind == "record" then
    return session.lists
  end
  local live = M.backend(category)
  if not session then
    if not live then
      return nil
    end
    session = { kind = "capture", lists = snapshot(live) }
    sessions[category] = session
  elseif live then
    for ft, names in pairs(snapshot(live)) do
      local list = session.lists[ft] or {}
      session.lists[ft] = list
      for _, name in ipairs(names) do
        if not vim.tbl_contains(list, name) then
          table.insert(list, name)
        end
      end
    end
  end
  return session.lists
end

---Why runtime changes cannot apply, or nil when an activation source exists.
---@param category "formatter"|"linter"
---@return string?
function M.unavailable(category)
  if M.get(category) then
    return nil
  end
  local _, err = M.backend(category)
  return string.format(
    "%s unavailable and no activation configured: inject adapters.activation.%s or call hangar.filter (%s)",
    backends[category].module,
    category,
    tostring(err)
  )
end

return M
