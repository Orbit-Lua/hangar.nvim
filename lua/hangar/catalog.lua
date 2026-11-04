-- The tools that hangar shows: registry entries merged with the tools that the
-- backends report. A registry field wins over a discovered one. Discovery
-- never loads a backend plugin, except nvim-treesitter for installed parsers,
-- which the parser category already queries.
local M = {}

local config = require("hangar.config")

---@type table<string, table<string, boolean>>
local recorded = {}

---Remember a tool name that a backend no longer reports, such as an LSP
---server whose enable hangar dropped.
---@param category Hangar.Category
---@param name string
function M.record(category, name)
  recorded[category] = recorded[category] or {}
  recorded[category][name] = true
end

---@alias Hangar.Discovered table<string, string[]> filetypes by runtime name

---@param found Hangar.Discovered
---@param name string
---@param filetypes string[]?
local function add(found, name, filetypes)
  local list = found[name] or {}
  found[name] = list
  for _, ft in ipairs(filetypes or {}) do
    if not vim.tbl_contains(list, ft) then
      table.insert(list, ft)
    end
  end
end

---Enabled LSP configs, plus names that hangar disabled or recorded.
---@return Hangar.Discovered
local function discover_lsp()
  local found = {}
  local ok, configs = pcall(vim.lsp.get_configs, { enabled = true })
  for _, lsp_config in ipairs(ok and configs or {}) do
    add(found, lsp_config.name, lsp_config.filetypes)
  end

  local names = vim.tbl_keys(recorded.lsp or {})
  for name, enabled in pairs(require("hangar.state").get().lsp or {}) do
    if enabled == false then
      table.insert(names, name)
    end
  end
  for _, name in ipairs(names) do
    local resolved, lsp_config = pcall(function()
      return vim.lsp.config[name]
    end)
    if not found[name] and resolved and type(lsp_config) == "table" then
      add(found, name, lsp_config.filetypes)
    end
  end
  return found
end

---Formatter or linter names from the activation lists of a loaded backend.
---@param category "formatter"|"linter"
---@return Hangar.Discovered
local function discover_list(category)
  local found = {}
  for ft, names in pairs(require("hangar.activation").loaded(category) or {}) do
    for _, name in ipairs(names) do
      add(found, name, { ft })
    end
  end
  return found
end

---Adapter names of a loaded nvim-dap, with the filetypes of their
---configurations.
---@return Hangar.Discovered
local function discover_dap()
  local found = {}
  local dap = package.loaded.dap
  if type(dap) ~= "table" or type(dap.adapters) ~= "table" then
    return found
  end
  for name in pairs(dap.adapters) do
    add(found, name)
  end
  for ft, configurations in pairs(dap.configurations or {}) do
    for _, configuration in ipairs(configurations) do
      if type(configuration) == "table" and found[configuration.type] then
        add(found, configuration.type, { ft })
      end
    end
  end
  return found
end

---Installed parsers, with the filetypes that use each language.
---@return Hangar.Discovered
local function discover_parser()
  local found = {}
  for _, lang in ipairs(require("hangar.category.parser").installed() or {}) do
    add(found, lang, vim.treesitter.language.get_filetypes(lang))
  end
  return found
end

---@type table<string, fun(): Hangar.Discovered>
local discover = {
  lsp = discover_lsp,
  dap = discover_dap,
  parser = discover_parser,
  formatter = function()
    return discover_list("formatter")
  end,
  linter = function()
    return discover_list("linter")
  end,
}

---The definitions of a category by logical name.
---@param category Hangar.Category
---@return table<string, Hangar.Definition>
function M.entries(category)
  local registered = config.get().registry[category] or {}
  local entries, aliases = {}, {}
  for name, meta in pairs(registered) do
    entries[name] = vim.deepcopy(meta)
    aliases[meta.runtime_name or name] = name
  end

  local found = discover[category] and discover[category]() or {}
  for runtime_name, filetypes in pairs(found) do
    local name = aliases[runtime_name] or runtime_name
    local entry = entries[name] or {}
    entries[name] = entry
    if entry.ft == nil then
      table.sort(filetypes)
      entry.ft = filetypes
    end
  end
  return entries
end

---The definition of one tool, or nil when neither the registry nor a backend
---knows it.
---@param category Hangar.Category
---@param name string
---@return Hangar.Definition?
function M.get(category, name)
  return M.entries(category)[name]
end

return M
