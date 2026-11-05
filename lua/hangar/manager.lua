---@class Hangar.Selection
---@field category Hangar.Category
---@field name string
---@class Hangar.SnapshotOptions
---@field category Hangar.Category
---@field scope? "buffer"|"states"
---@field source? { bufnr?: integer, filetype?: string, name?: string }

local M = {}

local config = require("hangar.config")
local catalog = require("hangar.catalog")
local data = require("hangar.data")
local order = require("hangar.order")
local state = require("hangar.state")
local categories = require("hangar.category")
local mason = require("hangar.mason")
local failures = {}
local pending = {}
-- Category installs (such as parser builds) that have not called back yet.
local installs = 0

local function done(callback, success, err)
  if callback then
    local ok, failure = pcall(callback, success, err)
    if not ok then
      vim.notify(
        "Hangar observer failed: " .. tostring(failure),
        vim.log.levels.ERROR
      )
    end
  end
end

local function apply(category, name, operation, opts, callback)
  local ok, result, err = true, true, nil
  if operation then
    ok, result, err = pcall(operation, opts)
  end
  local key = category .. ":" .. name
  if not ok or result == false then
    local message = "setting saved; runtime apply failed: "
      .. tostring(ok and err or result)
    failures[key] = message
    done(callback, false, message)
    return false
  end
  failures[key] = nil
  done(callback, true)
  return true
end

local save_errors = { setting = "tool state", order = "tool order" }

---Report a failed save of a setting or an order. A save that committed
---without confirmation leaves the runtime unchanged and caches a failure.
---@param kind "setting"|"order"
---@return boolean failed
local function save_failed(key, callback, kind, saved, save_error, committed)
  if saved then
    return false
  end
  if committed then
    local message = kind
      .. " saved; runtime unchanged: "
      .. tostring(save_error)
    failures[key] = message
    done(callback, false, message)
  else
    local message = "could not save " .. save_errors[kind] .. ": "
    done(callback, false, message .. tostring(save_error))
  end
  return true
end

local function valid_category(category)
  return type(category) == "string" and categories[category] ~= nil
end

local function definition(category, name)
  if not valid_category(category) or type(name) ~= "string" then
    return nil
  end
  return catalog.get(category, name)
end

local function policy()
  local setting = config.get().ui.missing_package_policy
  return setting == "manual" and "manual" or "auto"
end

---@param opts Hangar.SnapshotOptions
---@return table?
function M.snapshot(opts)
  opts = opts or {}
  if not valid_category(opts.category) then
    return nil
  end
  return data.snapshot(opts, failures)
end

---Selected-tool facts are queried through the same interface as list snapshots.
function M.details(selection)
  selection = selection or {}
  local category, name = selection.category, selection.name
  if not definition(category, name) then
    return nil
  end
  if category == "linter" then
    return {
      logs = config.get().adapters.linter.logs(name),
      diagnostics = categories.linter.get_linter_diagnostics(name),
    }
  end
  return { logs = {}, diagnostics = { messages = {} } }
end

---@class Hangar.ToggleOperation
---@field enabled boolean target state
---@field finish fun(success: boolean, err?: string) completes once

---Register a pending toggle. It inverts a pending toggle of the same tool,
---which then completes as superseded.
---@param on_complete fun(success: boolean, err?: string)?
---@return Hangar.ToggleOperation
local function begin_toggle(category, name, on_complete)
  local key = category .. ":" .. name
  local previous = pending[key]
  local enabled
  if previous then
    enabled = not previous.enabled
  else
    enabled = not state.is_enabled(category, name)
  end

  local completed = false
  local operation = { enabled = enabled }
  operation.finish = function(success, err)
    if completed then
      return
    end
    completed = true
    if pending[key] == operation then
      pending[key] = nil
    end
    done(on_complete, success, err)
  end
  pending[key] = operation
  if previous then
    previous.finish(false, "superseded by a newer toggle")
  end
  return operation
end

---Persist the toggle, then apply it at runtime.
---@param operation Hangar.ToggleOperation
---@return boolean
local function save_and_apply(category, name, handler, meta, operation)
  local enabled, finish = operation.enabled, operation.finish
  local key = category .. ":" .. name
  if
    save_failed(
      key,
      finish,
      "setting",
      state.set_enabled(category, name, enabled)
    )
  then
    return false
  end
  return apply(
    category,
    name,
    handler.apply_runtime,
    { name = name, meta = meta, is_enabled = enabled },
    finish
  )
end

---Run `continue` once the Mason package is installed. The `auto` policy
---installs a missing package first.
---@param package_name string
---@param finish fun(success: boolean, err?: string)
---@param continue fun(): boolean
---@return boolean
local function with_package(package_name, finish, continue)
  local installed, err = mason.package_status(package_name)
  if installed == nil then
    done(finish, false, err or "package status unavailable")
    return false
  elseif installed then
    return continue()
  elseif policy() == "manual" then
    done(finish, false, package_name .. " is not installed")
    return false
  end

  return mason.install(package_name, function(success, install_err)
    if success then
      continue()
    else
      done(finish, false, install_err or "package installation failed")
    end
  end)
end

---@param selection Hangar.Selection
---@param on_complete fun(success: boolean, err?: string)?
---@return boolean
function M.toggle(selection, on_complete)
  local category, name =
    selection and selection.category, selection and selection.name
  local meta = definition(category, name)
  local handler = valid_category(category) and categories[category]
  if not meta or not handler or not handler.capabilities.toggle then
    done(on_complete, false, "unknown or non-toggleable tool")
    return false
  end
  local blocked = handler.unavailable and handler.unavailable()
  if blocked then
    done(on_complete, false, blocked)
    return false
  end

  local key = category .. ":" .. name
  local operation = begin_toggle(category, name, on_complete)
  local function apply_toggle()
    if pending[key] ~= operation then
      return false
    end
    return save_and_apply(category, name, handler, meta, operation)
  end

  if operation.enabled and meta.mason then
    return with_package(meta.mason, operation.finish, apply_toggle)
  end
  return apply_toggle()
end

---@param selection Hangar.Selection
---@param on_complete fun(success: boolean, err?: string)?
---@return boolean
function M.install(selection, on_complete)
  local category, name =
    selection and selection.category, selection and selection.name
  local meta = definition(category, name)
  local handler = valid_category(category) and categories[category]
  if not meta or not handler or not handler.capabilities.install then
    done(on_complete, false, "unknown or non-installable tool")
    return false
  end
  if not handler.install and not meta.mason then
    local err = "no install mapping for " .. name
    done(on_complete, false, err)
    return false
  end
  -- Release the counter exactly once: on completion, or when the handler
  -- fails before it registers its callback.
  installs = installs + 1
  local released = false
  local function release()
    if not released then
      released = true
      installs = installs - 1
    end
  end
  local function finish(success, err)
    release()
    if success and handler.after_install then
      local ok, failure = pcall(handler.after_install, name, meta)
      if not ok then
        vim.notify(
          "Hangar: after install of "
            .. name
            .. " failed: "
            .. tostring(failure),
          vim.log.levels.ERROR
        )
      end
    end
    done(on_complete, success, err)
  end
  local ok, started = pcall(function()
    if handler.install then
      return handler.install(name, finish)
    end
    return mason.install(meta.mason, finish)
  end)
  if not ok then
    release()
    done(on_complete, false, tostring(started))
    return false
  end
  if started ~= true then
    release()
  end
  return started
end

---Report whether a toggle or an installation is still running.
---@return boolean
function M.busy()
  return next(pending) ~= nil or installs > 0 or mason.busy()
end

---Drop cached runtime failures before options are replaced.
function M.reset()
  failures = {}
end

---@param selection { category: Hangar.Category, filetype: string, name: string, direction: integer }
---@param on_complete fun(success: boolean, err?: string)?
---@return boolean
function M.reorder(selection, on_complete)
  local category = selection and selection.category
  local ft = selection and selection.filetype
  local name = selection and selection.name
  local direction = selection and selection.direction
  local meta = definition(category, name)
  local handler = valid_category(category) and categories[category]
  if
    not meta
    or (category ~= "formatter" and category ~= "linter")
    or not handler
    or not handler.capabilities.reorder
    or type(ft) ~= "string"
    or not vim.tbl_contains(meta.ft or {}, ft)
    or (direction ~= -1 and direction ~= 1)
  then
    done(on_complete, false, "invalid reorder selection")
    return false
  end
  local blocked = handler.unavailable and handler.unavailable()
  if blocked then
    done(on_complete, false, blocked)
    return false
  end

  local names = order.names_for_ft(category, ft)
  local index
  for i, current in ipairs(names) do
    if current == name then
      index = i
      break
    end
  end
  if not index or index + direction < 1 or index + direction > #names then
    done(on_complete, false, "tool is already at the order boundary")
    return false
  end
  names[index], names[index + direction] =
    names[index + direction], names[index]
  local key = category .. ":" .. name
  if
    save_failed(key, on_complete, "order", state.set_order(category, ft, names))
  then
    return false
  end
  return apply(category, name, handler.apply_order, {
    ft = ft,
    enabled_names = order.enabled_names_for_ft(category, ft, names),
  }, on_complete)
end

return M
