local M = {}
local pending = {}

function M.is_installing(name)
  if pending[name] then
    return true
  end
  local package = M.get_package(name)
  return package
      and type(package.is_installing) == "function"
      and package:is_installing()
    or false
end

---@return boolean
function M.busy()
  return next(pending) ~= nil
end

---Observe registry changes for a single view session without retaining it.
function M.observe(callback)
  local ok, registry = pcall(require, "mason-registry")
  if
    not ok
    or type(registry.on) ~= "function"
    or type(registry.off) ~= "function"
  then
    return function() end
  end
  local events = {
    "package:install:handle",
    "package:install:success",
    "package:install:failed",
    "package:uninstall:success",
    "package:uninstall:failed",
    "update:success",
  }
  for _, event in ipairs(events) do
    registry:on(event, callback)
  end
  return function()
    for _, event in ipairs(events) do
      registry:off(event, callback)
    end
  end
end

local function finish_install(pkg_name, success, err)
  local callbacks = pending[pkg_name] or {}
  pending[pkg_name] = nil
  for _, callback in ipairs(callbacks) do
    local ok, failure = pcall(callback, success, err)
    if not ok then
      vim.notify(
        "Hangar observer failed: " .. tostring(failure),
        vim.log.levels.ERROR
      )
    end
  end
end

---@param pkg_name string
---@return table? pkg, string? err
function M.get_package(pkg_name)
  local reg_ok, reg = pcall(require, "mason-registry")
  if not reg_ok then
    return nil, "mason registry is unavailable"
  end

  local pkg_ok, pkg = pcall(reg.get_package, pkg_name)
  if not pkg_ok or not pkg then
    return nil, "mason package not found: " .. pkg_name
  end

  return pkg, nil
end

---A broken package keeps its install directory without a receipt, as a failed
---Windows uninstall leaves it. Mason then counts it installed, but no shim exists.
---@param pkg table
---@return boolean
local function is_broken(pkg)
  if type(pkg.get_receipt) ~= "function" or not pkg:is_installed() then
    return false
  end
  local ok, receipt = pcall(pkg.get_receipt, pkg)
  return ok
    and type(receipt) == "table"
    and type(receipt.is_present) == "function"
    and not receipt:is_present()
end

---@param pkg_name string
---@return boolean? installed, string? err, boolean? broken
function M.package_status(pkg_name)
  local pkg, err = M.get_package(pkg_name)
  if not pkg then
    return nil, err
  end
  if is_broken(pkg) then
    return false, nil, true
  end
  return pkg:is_installed(), nil
end

---@param pkg_name string
---@param pkg table
---@return boolean
local function start_install(pkg_name, pkg)
  if pkg:is_installed() and not is_broken(pkg) then
    vim.notify(pkg_name .. " is already installed", vim.log.levels.INFO)
    finish_install(pkg_name, true)
    return true
  end

  vim.notify("Installing " .. pkg_name .. "…", vim.log.levels.INFO)
  -- Mason's promote step removes a broken directory before it moves the new one.
  local install_ok, handle = pcall(pkg.install, pkg)
  if not install_ok or not handle or type(handle.once) ~= "function" then
    local install_err = install_ok and "invalid install handle"
      or tostring(handle)
    vim.notify("Failed to install " .. pkg_name, vim.log.levels.ERROR)
    finish_install(pkg_name, false, install_err)
    return false
  end
  handle:once("closed", function()
    vim.schedule(function()
      if pkg:is_installed() and not is_broken(pkg) then
        vim.notify(pkg_name .. " installed", vim.log.levels.INFO)
        finish_install(pkg_name, true)
      else
        vim.notify("Failed to install " .. pkg_name, vim.log.levels.ERROR)
        finish_install(pkg_name, false, "installation failed")
      end
    end)
  end)
  return true
end

---@param pkg_name string
---@param err string
local function fail_lookup(pkg_name, err)
  vim.notify("Hangar: " .. err, vim.log.levels.WARN)
  finish_install(pkg_name, false, err)
end

---Install a package. A failed lookup refreshes the Mason registry once, since a
---first start has no registry until Mason downloads it.
---@param pkg_name string?
---@param on_done (fun(success: boolean, err?: string)?)?
---@return boolean
function M.install(pkg_name, on_done)
  if not pkg_name then
    return false
  end

  if pending[pkg_name] then
    if on_done then
      table.insert(pending[pkg_name], on_done)
    end
    return true
  end
  pending[pkg_name] = on_done and { on_done } or {}

  local pkg, err = M.get_package(pkg_name)
  if pkg then
    return start_install(pkg_name, pkg)
  end

  local reg_ok, reg = pcall(require, "mason-registry")
  if not reg_ok or type(reg.refresh) ~= "function" then
    fail_lookup(pkg_name, err)
    return false
  end
  local refresh_ok, refresh_err = pcall(
    reg.refresh,
    vim.schedule_wrap(function()
      local retry, retry_err = M.get_package(pkg_name)
      if retry then
        start_install(pkg_name, retry)
      else
        fail_lookup(pkg_name, retry_err)
      end
    end)
  )
  if not refresh_ok then
    fail_lookup(pkg_name, tostring(refresh_err))
    return false
  end
  return true
end

return M
