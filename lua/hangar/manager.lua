---@class Hangar.Selection
---@field category Hangar.Category
---@field name string
---@class Hangar.SnapshotOptions
---@field category Hangar.Category
---@field scope? "buffer"|"states"
---@field source? { bufnr?: integer, filetype?: string, name?: string }

local M = {}

local config = require("hangar.config")
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

local function valid_category(category)
  return type(category) == "string"
    and type(config.get().registry[category]) == "table"
    and categories[category] ~= nil
end

local function definition(category, name)
  if not valid_category(category) or type(name) ~= "string" then
    return nil
  end
  return config.get().registry[category][name]
end

local function policy()
  local setting = config.get().ui.missing_package_policy
  return setting == "manual" and "manual" or "auto"
end

---@param opts Hangar.SnapshotOptions
---@return table?
function M.snapshot(opts)
  opts = opts or {}
  local category = opts.category
  if not valid_category(category) then
    return nil
  end

  local source = opts.source or {}
  local bufnr = source.bufnr or vim.api.nvim_get_current_buf()
  local ft = source.filetype
  if ft == nil and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    ft = vim.bo[bufnr].filetype
  end
  local scope = opts.scope == "states" and "states" or "buffer"
  local entries
  if scope == "states" then
    entries = data.tool_entries(category)
  elseif ft and ft ~= "" then
    entries = data.tool_entries(category, ft)
  else
    entries = {}
  end
  local snapshot = {
    category = category,
    tools = {},
    groups = scope == "states" and data.build_ft_groups(category)
      or (ft and ft ~= "" and data.build_ft_groups(category, ft) or {}),
    summary = {
      total = #entries,
      enabled = 0,
      disabled = 0,
      installed = 0,
      missing = 0,
      attention = 0,
    },
  }
  for _, entry in ipairs(entries) do
    local health_status = data.health_status(
      category,
      entry.name,
      entry.meta,
      scope == "buffer" and ft or nil,
      bufnr
    )
    local failure = failures[category .. ":" .. entry.name]
    if failure then
      health_status.reason = failure
      health_status.label = "Apply failed"
      health_status.severity = "DiagnosticError"
      health_status.attention = true
    end
    table.insert(snapshot.tools, {
      name = entry.name,
      meta = vim.deepcopy(entry.meta),
      status = health_status.label,
      status_hl = health_status.severity,
      enabled = state.is_enabled(category, entry.name),
      health_status = health_status,
    })
    if health_status.attention then
      snapshot.summary.attention = snapshot.summary.attention + 1
    end
    if health_status.enabled == true then
      snapshot.summary.enabled = snapshot.summary.enabled + 1
    elseif health_status.enabled == false then
      snapshot.summary.disabled = snapshot.summary.disabled + 1
    end
    if health_status.installation == "installed" then
      snapshot.summary.installed = snapshot.summary.installed + 1
    elseif health_status.installation == "missing" then
      snapshot.summary.missing = snapshot.summary.missing + 1
    end
  end
  return snapshot
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
  local previous = pending[key]
  local enabled
  if previous then
    enabled = not previous.enabled
  else
    enabled = not state.is_enabled(category, name)
  end
  local callback = on_complete
  local completed = false
  local operation = { enabled = enabled }
  on_complete = function(success, err)
    if completed then
      return
    end
    completed = true
    if pending[key] == operation then
      pending[key] = nil
    end
    done(callback, success, err)
  end
  operation.finish = on_complete
  pending[key] = operation
  if previous then
    previous.finish(false, "superseded by a newer toggle")
  end
  local function apply_toggle()
    if pending[key] ~= operation then
      return false
    end
    local saved, save_error, committed =
      state.set_enabled(category, name, enabled)
    if not saved and committed then
      local message = "setting saved; runtime unchanged: "
        .. tostring(save_error)
      failures[key] = message
      done(on_complete, false, message)
      return false
    end
    if not saved then
      done(
        on_complete,
        false,
        "could not save tool state: " .. tostring(save_error)
      )
      return false
    end
    return apply(
      category,
      name,
      handler.apply_runtime,
      { name = name, meta = meta, is_enabled = enabled },
      on_complete
    )
  end

  if enabled and meta.mason then
    local installed, err = mason.package_status(meta.mason)
    if installed == false then
      if policy() == "manual" then
        local message = meta.mason .. " is not installed"
        done(on_complete, false, message)
        return false
      end
      return mason.install(meta.mason, function(success, install_err)
        if success then
          apply_toggle()
        else
          done(on_complete, false, install_err or "package installation failed")
        end
      end)
    elseif installed == nil then
      done(on_complete, false, err or "package status unavailable")
      return false
    end
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
    local err = "no install package for " .. name
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
  local saved, save_error, committed = state.set_order(category, ft, names)
  if not saved and committed then
    local message = "order saved; runtime unchanged: " .. tostring(save_error)
    failures[category .. ":" .. name] = message
    done(on_complete, false, message)
    return false
  end
  if not saved then
    done(
      on_complete,
      false,
      "could not save tool order: " .. tostring(save_error)
    )
    return false
  end
  return apply(category, name, handler.apply_order, {
    ft = ft,
    enabled_names = order.enabled_names_for_ft(category, ft, names),
  }, on_complete)
end

return M
