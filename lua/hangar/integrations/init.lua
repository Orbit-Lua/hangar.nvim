-- Applies the integrations of |hangar-integrations|. Conform, nvim-lint and
-- nvim-dap load after hangar, so one module loader runs their integration when
-- `require` returns the module. Each call reads the current options, so a
-- repeated setup changes behavior without a second loader.
local M = {}

local config = require("hangar.config")

---@class Hangar.LoadTarget
---@field option "conform"|"lint"|"dap" key in |Hangar.Integrations|
---@field apply fun(module: table) gates the loaded module; must be idempotent

---Integrations that run when a module loads, by module name.
---@type table<string, Hangar.LoadTarget>
M.targets = {
  conform = {
    option = "conform",
    apply = function(module)
      require("hangar.integrations.conform").apply(module)
    end,
  },
  lint = {
    option = "lint",
    apply = function(module)
      require("hangar.integrations.lint").apply(module)
    end,
  },
  dap = {
    option = "dap",
    apply = function(module)
      require("hangar.integrations.dap").apply(module)
    end,
  },
}

---@type function?
local loader

---@param option string
---@return boolean
local function enabled(option)
  return config.configured() and config.get().integrations[option] == true
end

---@param name string
---@param err any
local function report(name, err)
  vim.notify(
    "Hangar: " .. name .. " integration failed: " .. tostring(err),
    vim.log.levels.ERROR
  )
end

---Run the integration of a loaded module. A failure is reported and never
---breaks the `require` of the plugin.
---@param name string
---@param module any
local function apply(name, module)
  local target = M.targets[name]
  if not target or type(module) ~= "table" or not enabled(target.option) then
    return
  end
  local ok, err = pcall(target.apply, module)
  if not ok then
    report(name, err)
  end
end

---The function that an earlier `hook` wrapped, so a repeated hook or a
---reloaded module never wraps a wrapper.
---@param fn function
---@return function
local function unwrap(fn)
  local info = debug.getinfo(fn, "S")
  if not info.source:find("hangar[/\\]integrations[/\\]init%.lua$") then
    return fn
  end
  for index = 1, math.huge do
    local name, value = debug.getupvalue(fn, index)
    if name == nil then
      break
    elseif name == "original" then
      return value
    end
  end
  return fn
end

---Run `run` before or after each call of `module[key]`. A failure of `run` is
---reported and never breaks the call.
---@param module table
---@param key string
---@param when "before"|"after"
---@param run fun()
function M.hook(module, key, when, run)
  if type(module[key]) ~= "function" then
    return
  end
  local original = unwrap(module[key])
  local function guarded()
    local ok, err = pcall(run)
    if not ok then
      report(key, err)
    end
  end
  module[key] = function(...)
    if when == "before" then
      guarded()
      return original(...)
    end
    local result = vim.F.pack_len(original(...))
    guarded()
    return vim.F.unpack_len(result)
  end
end

---Find a target module through the other loaders and wrap the loader that
---they return. Return a message for other modules, as `require` expects.
---@param name string
---@return function|string|nil
local function find(name)
  -- A loader of a reloaded module instance steps aside for the current one.
  if not M.targets[name] or package.loaded["hangar.integrations"] ~= M then
    return nil
  end
  local messages = {}
  for _, other in ipairs(package.loaders) do
    if other ~= loader then
      local found, extra = other(name)
      if type(found) == "function" then
        return function(...)
          local module = found(...)
          apply(name, module)
          return module
        end,
          extra
      elseif type(found) == "string" then
        table.insert(messages, found)
      end
    end
  end
  return table.concat(messages)
end

---Install the loader once per editor and apply the integrations of modules
---that are already loaded.
function M.setup()
  if not loader then
    loader = find
    table.insert(package.loaders, 1, loader)
  end
  for name in pairs(M.targets) do
    apply(name, package.loaded[name])
  end
  require("hangar.integrations.lsp").setup()
  require("hangar.integrations.treesitter").setup()
end

return M
