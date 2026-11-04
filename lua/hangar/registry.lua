---@tag hangar-registry
---@text
--- The registry is optional. It adds install mapping and metadata to the tools
--- that hangar discovers from the backends. Keys are logical tool names, by
--- category: `lsp`, `dap`, `linter`, `formatter`, `parser` and `package`.
--- `formatter_defaults` and `linter_defaults` set the default order by
--- filetype.
---
--- Annotate a registry table with `---@type Hangar.Registry`. |hangar.setup()|
--- rejects an unknown key, field or value with an error that names its path.
---@class Hangar.Registry
---@field lsp? table<string, Hangar.Definition>
---@field dap? table<string, Hangar.Definition>
---@field linter? table<string, Hangar.Definition>
---@field formatter? table<string, Hangar.Definition>
---@field parser? table<string, Hangar.Definition>
---@field ["package"]? table<string, Hangar.Definition>
---@field formatter_defaults? table<string, string[]> formatter order by filetype
---@field linter_defaults? table<string, string[]> linter order by filetype
-- LuaLS reads a bare `package` field name as the visibility keyword, so it is quoted.

---@tag hangar-definition
---@text
--- One registry entry.
---
--- - `ft`: filetypes that the tool supports.
--- - `mason`: Mason package that installs the tool.
--- - `runtime_name`: backend name, when it differs from the logical name.
--- - `note`: text that details show.
--- - `source`: who manages the tool (|Hangar.Source|).
--- - `plugin`: Lua module that starts this LSP client outside
---   `vim.lsp.config`, such as `"typescript-tools"`.
---@class Hangar.Definition
---@field ft? string[]
---@field mason? string
---@field runtime_name? string
---@field note? string
---@field source? Hangar.Source
---@field plugin? string

---@alias Hangar.Source "mason"|"external"|"treesitter"

local M = {}

M.categories = { "lsp", "dap", "linter", "formatter", "parser", "package" }

local orders = { "formatter_defaults", "linter_defaults" }

local sources = { mason = true, external = true, treesitter = true }

local scalar_fields = {
  mason = "string",
  runtime_name = "string",
  note = "string",
  plugin = "string",
}

---Raise a setup error that names the offending path.
---@param path string
---@param message string
local function fail(path, message)
  error("hangar.setup: " .. path .. " " .. message, 0)
end

---Render a key for a path, so that `markdownlint-cli2` stays readable.
---@param key any
---@return string
local function segment(key)
  if type(key) == "string" and key:match("^[%a_][%w_]*$") then
    return "." .. key
  end
  return "[" .. vim.inspect(key) .. "]"
end

---@param value any
---@param path string
local function check_string_list(value, path)
  if type(value) ~= "table" or not vim.islist(value) then
    fail(path, "must be a list of strings")
  end
  for index, item in ipairs(value) do
    if type(item) ~= "string" then
      fail(path .. "[" .. index .. "]", "must be a string")
    end
  end
end

---@param definition any
---@param path string
local function check_definition(definition, path)
  if type(definition) ~= "table" then
    fail(path, "must be a table")
  end
  for field, value in pairs(definition) do
    local field_path = path .. segment(field)
    if field == "ft" then
      check_string_list(value, field_path)
    elseif field == "source" then
      if not sources[value] then
        fail(field_path, 'must be "mason", "external" or "treesitter"')
      end
    elseif scalar_fields[field] then
      if type(value) ~= scalar_fields[field] then
        fail(field_path, "must be a " .. scalar_fields[field])
      end
    else
      fail(field_path, "is not a registry field")
    end
  end
end

---@param category string
---@param tools any
local function check_category(category, tools)
  local path = "registry." .. category
  if type(tools) ~= "table" then
    fail(path, "must be a table")
  end
  for name, definition in pairs(tools) do
    if type(name) ~= "string" then
      fail(path .. segment(name), "must use a string tool name")
    end
    check_definition(definition, path .. segment(name))
  end
end

---@param key string
---@param by_ft any
local function check_order(key, by_ft)
  local path = "registry." .. key
  if type(by_ft) ~= "table" then
    fail(path, "must be a table")
  end
  for ft, names in pairs(by_ft) do
    if type(ft) ~= "string" then
      fail(path .. segment(ft), "must use a string filetype")
    end
    check_string_list(names, path .. segment(ft))
  end
end

---Validate a registry against |Hangar.Registry| and complete it in place, so
---that every category and default-order table exists.
---@param registry any
---@return Hangar.Registry
function M.resolve(registry)
  if registry == nil then
    registry = {}
  end
  if type(registry) ~= "table" then
    fail("registry", "must be a table")
  end
  for key, value in pairs(registry) do
    if vim.tbl_contains(M.categories, key) then
      check_category(key, value)
    elseif vim.tbl_contains(orders, key) then
      check_order(key, value)
    else
      fail("registry" .. segment(key), "is not a registry category")
    end
  end
  for _, key in ipairs(M.categories) do
    registry[key] = registry[key] or {}
  end
  for _, key in ipairs(orders) do
    registry[key] = registry[key] or {}
  end
  return registry
end

return M
