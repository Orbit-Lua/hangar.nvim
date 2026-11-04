local M = {
  capabilities = { toggle = true, install = true, reorder = false },
}

local config = require("hangar.config")

---Report why a toggle cannot apply, before any state is saved.
---@return string?
function M.unavailable()
  if not config.get().integrations.treesitter then
    return "the treesitter integration is off (integrations.treesitter = false)"
  end
end

---Stop or restart Tree-sitter in the open buffers of the parser language. The
---parser files stay installed.
---@param opts Hangar.ApplyRuntimeOpts
---@return boolean
function M.apply_runtime(opts)
  local treesitter = require("hangar.integrations.treesitter")
  if opts.is_enabled then
    treesitter.enable(opts.name)
  else
    treesitter.disable(opts.name)
  end
  return true
end

local function treesitter()
  local ok, module = pcall(require, "nvim-treesitter")
  if not ok then
    return nil
  end
  return module
end

---Installed parser languages, or nil when nvim-treesitter is unavailable.
---@return string[]?
function M.installed()
  local module = treesitter()
  if not module or type(module.get_installed) ~= "function" then
    return nil
  end

  local ok, installed = pcall(module.get_installed, "parsers")
  if not ok or type(installed) ~= "table" then
    return nil
  end
  return installed
end

local function installed_set()
  local installed = M.installed()
  if not installed then
    return nil
  end

  local result = {}
  for _, name in ipairs(installed) do
    result[name] = true
  end
  return result
end

---Availability query shared by snapshots and the category status.
function M.installation_status(name)
  local installed = installed_set()
  if not installed then
    return nil, "Tree-sitter is unavailable"
  end
  return installed[name] == true
end

---@param name string
---@param on_done fun(success: boolean, err?: string)?
---@return boolean
function M.install(name, on_done)
  local module = treesitter()
  if not module or type(module.install) ~= "function" then
    local err = "nvim-treesitter is unavailable"
    vim.notify("Hangar: " .. err, vim.log.levels.WARN)
    if on_done then
      on_done(false, err)
    end
    return false
  end

  local ok, task = pcall(module.install, { name })
  if not ok then
    if on_done then
      on_done(false, tostring(task))
    end
    return false
  end
  vim.notify(
    "Installing Treesitter parser " .. name .. "…",
    vim.log.levels.INFO
  )
  if not task or type(task.await) ~= "function" then
    local err = "nvim-treesitter returned no install task"
    vim.notify("Hangar: " .. err, vim.log.levels.ERROR)
    if on_done then
      on_done(false, err)
    end
    return false
  end

  task:await(vim.schedule_wrap(function(err, installed)
    if err or installed ~= true then
      local message = err or "installation failed"
      vim.notify(
        "Failed to install Treesitter parser " .. name,
        vim.log.levels.ERROR
      )
      if on_done then
        on_done(false, message)
      end
    elseif on_done then
      on_done(true)
    end
  end))
  return true
end

return M
