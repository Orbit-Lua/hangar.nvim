local order = require("hangar.order")
local catalog = require("hangar.catalog")
local activation = require("hangar.activation")

local M = {}

---@class Hangar.ListAdapterSpec
---@field module string
---@field field string
---@field category "formatter"|"linter"

---@param spec Hangar.ListAdapterSpec
---@return table? module
---@return string? err
local function backend(spec)
  local ok, module = pcall(require, spec.module)
  if not ok then
    return nil, tostring(module)
  end
  return module
end

---Return the backend module when runtime changes can apply.
---@param spec Hangar.ListAdapterSpec
---@return table? module
---@return string? err
local function writable_backend(spec)
  local blocked = activation.unavailable(spec.category)
  if blocked then
    return nil, blocked
  end
  return backend(spec)
end

---Replace the runtime names of a list entry and keep its option keys,
---such as conform's `stop_after_first`. The new entry stands for the
---activation names of its filetype and the names that the old entry had.
---@param spec Hangar.ListAdapterSpec
---@param entry any
---@param names string[]
---@param ft string
local function rewrite(spec, entry, names, ft)
  local initial = vim.deepcopy((activation.get(spec.category) or {})[ft] or {})
  for _, name in ipairs(activation.names(entry) or {}) do
    if not vim.tbl_contains(initial, name) then
      table.insert(initial, name)
    end
  end
  return activation.rewrite(entry, names, initial)
end

---Add or remove one runtime name in a list. Enabling restores the name
---only where the activation lists it for the filetype.
---@param list string[]
---@param runtime_name string
---@param enabled boolean
---@param initial string[] activation names of the filetype
local function update_names(list, runtime_name, enabled, initial)
  if not enabled then
    for i = #list, 1, -1 do
      if list[i] == runtime_name then
        table.remove(list, i)
      end
    end
    return
  end

  if
    vim.tbl_contains(initial, runtime_name)
    and not vim.tbl_contains(list, runtime_name)
  then
    table.insert(list, runtime_name)
  end
end

---@param spec Hangar.ListAdapterSpec
local function apply_runtime(spec, opts)
  local module, err = writable_backend(spec)
  if not module then
    return false, err
  end

  -- Enabling restores a tool only where the activation lists it; other
  -- supported filetypes stay unwired, matching the next startup.
  local initial = activation.get(spec.category) or {}
  local runtime_name = opts.meta.runtime_name or opts.name
  for _, ft in ipairs(opts.meta.ft or {}) do
    local entry = module[spec.field][ft]
    -- A function-valued entry is the backend's own logic; hangar leaves it.
    if type(entry) ~= "function" then
      local list = activation.names(entry) or {}
      update_names(list, runtime_name, opts.is_enabled, initial[ft] or {})
      if entry or #list > 0 then
        local names = order.from_runtime(spec.category, list)
        local ordered = order.enabled_names_for_ft(spec.category, ft, names)
        module[spec.field][ft] =
          rewrite(spec, entry, order.to_runtime(spec.category, ordered), ft)
      end
    end
  end
end

---@param spec Hangar.ListAdapterSpec
local function apply_order(spec, opts)
  local module, err = writable_backend(spec)
  if not module then
    return false, err
  end
  local entry = module[spec.field][opts.ft]
  if type(entry) == "function" then
    return
  end

  local old = activation.names(entry) or {}
  local known = {}
  for name, meta in pairs(catalog.entries(spec.category)) do
    if vim.tbl_contains(meta.ft or {}, opts.ft) then
      known[meta.runtime_name or name] = true
    end
  end
  local result = vim.tbl_filter(function(name)
    return vim.tbl_contains(old, name)
  end, order.to_runtime(spec.category, opts.enabled_names))
  for _, name in ipairs(old) do
    if not known[name] and not vim.tbl_contains(result, name) then
      table.insert(result, name)
    end
  end
  module[spec.field][opts.ft] = rewrite(spec, entry, result, opts.ft)
end

---The special backend key ("*" or "_") that still lists a tool, if any.
---@param spec Hangar.ListAdapterSpec
---@param opts Hangar.StatusOpts
---@return string?
local function special_listing(spec, opts)
  local module = backend(spec)
  if not module or type(module[spec.field]) ~= "table" then
    return nil
  end
  local runtime_name = opts.meta.runtime_name or opts.name
  for _, key in ipairs(activation.special_keys) do
    local names = activation.names(module[spec.field][key])
    if names and vim.tbl_contains(names, runtime_name) then
      return key
    end
  end
end

---@param spec Hangar.ListAdapterSpec
---@param opts Hangar.StatusOpts
local function wiring_status(spec, opts)
  local module = backend(spec)
  if not module then
    return nil, nil
  end
  if activation.unavailable(spec.category) then
    return "activation not configured", "DiagnosticWarn"
  end

  local filetypes = opts.filetype and { opts.filetype } or (opts.meta.ft or {})
  if #filetypes == 0 then
    return "no ft", "DiagnosticWarn"
  end

  -- Measure against the activation, the set enabling restores.
  local runtime_name = opts.meta.runtime_name or opts.name
  local initial = activation.get(spec.category) or {}
  local total, configured = 0, 0
  for _, ft in ipairs(filetypes) do
    if type(module[spec.field][ft]) == "function" then
      -- The backend decides at run time; hangar reports it as configured.
      total, configured = total + 1, configured + 1
    elseif vim.tbl_contains(initial[ft] or {}, runtime_name) then
      total = total + 1
      local names = activation.names(module[spec.field][ft]) or {}
      if vim.tbl_contains(names, runtime_name) then
        configured = configured + 1
      end
    end
  end

  if configured == 0 then
    return "not configured", "DiagnosticWarn"
  elseif configured < total then
    return string.format("partly configured %d/%d", configured, total),
      "DiagnosticWarn"
  end
  return nil, nil
end

---@param spec Hangar.ListAdapterSpec
---@return Hangar.CategoryHandler
function M.new(spec)
  local adapter = {
    capabilities = { toggle = true, install = true, reorder = true },
  }

  ---Report why runtime changes cannot apply, before any state is saved.
  function adapter.unavailable()
    return activation.unavailable(spec.category)
  end

  function adapter.apply_runtime(opts)
    return apply_runtime(spec, opts)
  end

  function adapter.apply_order(opts)
    return apply_order(spec, opts)
  end

  ---@param opts Hangar.StatusOpts
  ---@return string?
  function adapter.special_listing(opts)
    return special_listing(spec, opts)
  end

  ---@param opts Hangar.StatusOpts
  function adapter.wiring_status(opts)
    return wiring_status(spec, opts)
  end

  return adapter
end

return M
