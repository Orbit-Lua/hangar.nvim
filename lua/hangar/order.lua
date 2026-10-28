---@class Hangar.FtGroup
---@field ft string
---@field names string[]
local M = {}

local config = require("hangar.config")

local function tools()
  return config.get().registry
end
local state_mod = require("hangar.state")

function M.from_runtime(category, names)
  local aliases = {}
  for name, meta in pairs(tools()[category] or {}) do
    aliases[meta.runtime_name or name] = name
  end
  return vim.tbl_map(function(name)
    return aliases[name] or name
  end, names)
end

function M.to_runtime(category, names)
  return vim.tbl_map(function(name)
    local meta = tools()[category][name]
    return meta and (meta.runtime_name or name) or name
  end, names)
end

---@param names string[]
---@return table<string, boolean>
local function to_set(names)
  local set = {}
  for _, name in ipairs(names) do
    set[name] = true
  end
  return set
end

---@param names string[]
---@param seen table<string, boolean>
---@param out string[]
local function append_unseen(names, seen, out)
  for _, name in ipairs(names) do
    if not seen[name] then
      table.insert(out, name)
      seen[name] = true
    end
  end
end

---@param category Hangar.Category
---@param ft string
---@return string[]
local function tool_names_for_ft(category, ft)
  local names = {}
  for name, meta in pairs(tools()[category] or {}) do
    if vim.tbl_contains(meta.ft or {}, ft) then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

---@param category Hangar.Category
---@param ft string
---@return string[]?
local function configured_order(category, ft)
  if category ~= "formatter" and category ~= "linter" then
    return nil
  end
  local saved = state_mod.get_order(category --[[@as "formatter"|"linter"]], ft)
    or tools()[category .. "_defaults"][ft]
  if saved then
    return saved
  end
  -- Without a configured order, the activation order is the priority, so a
  -- re-enabled tool returns to its original position.
  local lists = require("hangar.activation").get(category)
  return lists and lists[ft] and M.from_runtime(category, lists[ft])
end

---@param category Hangar.Category
---@param ft string
---@param names string[]?
---@return string[]
function M.names_for_ft(category, ft, names)
  local candidates = names and vim.deepcopy(names)
    or tool_names_for_ft(category, ft)
  local candidate_set = to_set(candidates)
  local order = configured_order(category, ft)
  if not order then
    return candidates
  end

  local seen = {}
  local ordered = {}
  for _, name in ipairs(order) do
    if candidate_set[name] and not seen[name] then
      table.insert(ordered, name)
      seen[name] = true
    end
  end
  append_unseen(candidates, seen, ordered)
  return ordered
end

---@param category Hangar.Category
---@param ft string
---@param names string[]?
---@return string[]
function M.enabled_names_for_ft(category, ft, names)
  return vim.tbl_filter(function(name)
    return state_mod.is_enabled(category, name)
  end, M.names_for_ft(category, ft, names))
end

---@param category Hangar.Category
---@return Hangar.FtGroup[]
function M.build_ft_groups(category)
  local ft_set = {}
  for _, meta in pairs(tools()[category] or {}) do
    for _, ft in ipairs(meta.ft or {}) do
      ft_set[ft] = true
    end
  end

  local filetypes = vim.tbl_keys(ft_set)
  table.sort(filetypes)

  local groups = {}
  for _, ft in ipairs(filetypes) do
    table.insert(groups, { ft = ft, names = M.names_for_ft(category, ft) })
  end
  return groups
end

return M
