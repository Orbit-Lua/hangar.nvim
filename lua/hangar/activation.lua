-- Initial runtime names by filetype for formatters and linters. Re-enabling a
-- tool restores it only where this activation lists it, and default order
-- follows it. The activation comes from `hangar.filter`, then from the conform
-- and lint integrations, then from a capture of the backend lists. The session
-- outlives a repeated setup because the backend still holds the changed lists.
local M = {}

local backends = {
  formatter = {
    module = "conform",
    field = "formatters_by_ft",
    option = "conform",
  },
  linter = { module = "lint", field = "linters_by_ft", option = "lint" },
}

-- Conform's "*" and "_" keys are not filetypes; hangar leaves them alone.
M.special_keys = { "*", "_" }

---@type table<string, { kind: "record"|"capture", lists: table<string, string[]> }>
local sessions = {}

---The backend table that the integration synced last, by category.
---@type table<string, table>
local synced = setmetatable({}, { __mode = "v" })

---Activation names of each list entry that hangar wrote. A backend table that
---copies such an entry, as a repeated `conform.setup` does, keeps the names
---that the entry had before hangar filtered it.
---@type table<table, string[]>
local produced = setmetatable({}, { __mode = "k" })

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

---Activation names of an entry: those it had before hangar wrote it.
---@param entry any
---@return string[]?
local function source_names(entry)
  local names = produced[entry]
  return names and vim.deepcopy(names) or M.names(entry)
end

local function snapshot(by_ft)
  local lists = {}
  for ft, entry in pairs(by_ft or {}) do
    local names = not is_special(ft) and source_names(entry)
    if names then
      lists[ft] = names
    end
  end
  return lists
end

---Build a list entry with the given runtime names and keep the option keys of
---`entry`, such as conform's `stop_after_first`.
---@param entry any
---@param names string[] runtime names
---@param initial string[] activation names that the new entry stands for
---@return table
function M.rewrite(entry, names, initial)
  local result = vim.deepcopy(names)
  if type(entry) == "table" then
    for key, value in pairs(entry) do
      if type(key) ~= "number" then
        result[key] = vim.deepcopy(value)
      end
    end
  end
  produced[result] = vim.deepcopy(initial)
  return result
end

---Filter activation names by saved enablement and order.
---@param category "formatter"|"linter"
---@param ft string
---@param entry any the entry that the result replaces
---@param initial string[] activation names
---@return table
function M.filtered(category, ft, entry, initial)
  local order = require("hangar.order")
  local enabled = order.enabled_names_for_ft(
    category,
    ft,
    order.from_runtime(category, initial)
  )
  return M.rewrite(entry, order.to_runtime(category, enabled), initial)
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

---The backend table of a loaded module, without loading it.
---@param category "formatter"|"linter"
---@return table?
local function loaded_backend(category)
  local spec = backends[category]
  local module = package.loaded[spec.module]
  local by_ft = type(module) == "table" and module[spec.field]
  return type(by_ft) == "table" and by_ft or nil
end

---Record the lists that a caller passes through `hangar.filter`.
---@param category "formatter"|"linter"
---@param by_ft table
function M.record(category, by_ft)
  sessions[category] = { kind = "record", lists = snapshot(by_ft) }
end

---Adopt a backend table that the integration has not seen: its lists become
---the activation, and saved state filters it in place. A category that
---`hangar.filter` recorded is left alone.
---@param category "formatter"|"linter"
---@param module? table the backend module, for a module that is still loading
function M.sync(category, module)
  local spec = backends[category]
  local config = require("hangar.config")
  if
    not config.configured()
    or not config.get().integrations[spec.option]
    or (sessions[category] and sessions[category].kind == "record")
  then
    return
  end
  module = module or package.loaded[spec.module]
  local by_ft = type(module) == "table" and module[spec.field]
  if type(by_ft) ~= "table" or synced[category] == by_ft then
    return
  end
  synced[category] = by_ft
  local lists = snapshot(by_ft)
  sessions[category] = { kind = "capture", lists = lists }
  for ft, names in pairs(lists) do
    by_ft[ft] = M.filtered(category, ft, by_ft[ft], names)
  end
end

---Read the activation lists of a category. A recorded list is used as is; a
---captured list merges names that the live backend gained.
---@param category "formatter"|"linter"
---@return table<string, string[]>?
function M.get(category)
  M.sync(category)
  local session = sessions[category]
  if session and session.kind == "record" then
    return session.lists
  end
  -- Loading the backend can run the integration, which starts a session.
  local live
  if session then
    live = loaded_backend(category)
  else
    live = M.backend(category)
  end
  session = sessions[category]
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

---Activation lists without loading the backend: nil until the backend module
---is loaded or a list was recorded.
---@param category "formatter"|"linter"
---@return table<string, string[]>?
function M.loaded(category)
  if sessions[category] or package.loaded[backends[category].module] then
    return M.get(category)
  end
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
    "%s unavailable and hangar.filter was not called (%s)",
    backends[category].module,
    tostring(err)
  )
end

return M
