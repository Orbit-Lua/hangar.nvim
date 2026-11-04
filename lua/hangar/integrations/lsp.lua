-- Gates LSP servers from saved state. A wrapper around `vim.lsp.enable` drops
-- and records each enable of a disabled server, so enabling it later replays
-- the consumer's own call. An owned LspAttach group stops clients that start
-- outside `vim.lsp.enable`, such as typescript-tools.
local M = {}

local GROUP = "hangar.lsp"

---Runtime names whose enable hangar dropped.
---@type table<string, boolean>
local recorded = {}

---Find the `vim.lsp.enable` that an earlier instance of this module wrapped,
---so a reload never wraps the wrapper.
---@param enable function
---@return function
local function unwrap(enable)
  local info = debug.getinfo(enable, "S")
  if not info.source:find("hangar[/\\]integrations[/\\]lsp%.lua$") then
    return enable
  end
  for index = 1, math.huge do
    local name, value = debug.getupvalue(enable, index)
    if name == nil then
      break
    elseif name == "original" then
      return value
    end
  end
  return enable
end

local original = unwrap(vim.lsp.enable)

---Whether this module instance gates servers. A wrapper of a reloaded
---instance passes every call through.
---@return boolean
local function active()
  local config = require("hangar.config")
  return package.loaded["hangar.integrations.lsp"] == M
    and config.configured()
    and config.get().integrations.lsp == true
end

---Whether saved state disables a server, by its runtime name.
---@param runtime_name string
---@return boolean
local function gated(runtime_name)
  if not active() then
    return false
  end
  local name = require("hangar.order").from_runtime("lsp", { runtime_name })[1]
  return not require("hangar.state").is_enabled("lsp", name)
end

---@param name string
local function record(name)
  recorded[name] = true
  require("hangar.catalog").record("lsp", name)
end

---@param name string|string[]
---@param enable? boolean
local function wrapper(name, enable)
  if enable == false or not active() then
    for _, item in ipairs(type(name) == "table" and name or { name }) do
      recorded[item] = nil
    end
    return original(name, enable)
  end
  local passed = {}
  for _, item in ipairs(type(name) == "table" and name or { name }) do
    if gated(item) then
      record(item)
    else
      table.insert(passed, item)
    end
  end
  if #passed > 0 then
    return original(type(name) == "table" and passed or passed[1], enable)
  end
end

---@param name string
local function stop_clients(name)
  for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
    client:stop()
  end
end

---Disable and record a server, and stop its clients.
---@param name string runtime name
function M.disable(name)
  if vim.lsp.is_enabled(name) then
    original(name, false)
    record(name)
  end
  stop_clients(name)
end

---Enable a server again. Hangar replays an enable that it dropped; it never
---enables a server that the consumer did not enable.
---@param name string runtime name
---@return boolean replayed
function M.enable(name)
  if not recorded[name] then
    return false
  end
  recorded[name] = nil
  original(name)
  return true
end

---Install the wrapper and bring runtime in line with saved state and options.
function M.setup()
  vim.lsp.enable = wrapper
  for name in pairs(vim.deepcopy(recorded)) do
    if not gated(name) then
      M.enable(name)
    end
  end
  if not active() then
    pcall(vim.api.nvim_del_augroup_by_name, GROUP)
    return
  end

  local order = require("hangar.order")
  for name, enabled in pairs(require("hangar.state").get().lsp or {}) do
    if enabled == false then
      M.disable(order.to_runtime("lsp", { name })[1])
    end
  end
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup(GROUP, { clear = true }),
    desc = "Stop clients of LSP servers that Hangar disables",
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and gated(client.name) then
        vim.schedule(function()
          client:stop()
        end)
      end
    end,
  })
end

return M
