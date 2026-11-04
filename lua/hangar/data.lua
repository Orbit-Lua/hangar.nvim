local M = {}

local catalog = require("hangar.catalog")
local order = require("hangar.order")
local mason = require("hangar.mason")
local state_mod = require("hangar.state")
local category_handlers = require("hangar.category")

---@param meta Hangar.Definition
---@param ft string?
---@return boolean
function M.supports_ft(meta, ft)
  if not ft or ft == "" then
    return false
  end
  return vim.tbl_contains(meta.ft or {}, ft)
end

---@param category Hangar.Category
---@param ft string?
---@return { name: string, meta: Hangar.Definition }[]
function M.tool_entries(category, ft)
  local flat = {}
  for name, meta in pairs(catalog.entries(category)) do
    if not ft or M.supports_ft(meta, ft) then
      table.insert(flat, { name = name, meta = meta })
    end
  end
  table.sort(flat, function(a, b)
    return a.name < b.name
  end)
  return flat
end

local runtime_labels = {
  ["no binary"] = "Missing executable",
  ["missing definition"] = "Missing definition",
  ["error"] = "Failed",
  ["ok"] = "Configured",
  ["no ft"] = "No filetypes",
}

local function runtime_label(value)
  if type(value) ~= "string" then
    return "Unknown"
  end
  return runtime_labels[value] or value:gsub("^%l", string.upper)
end

---@param category Hangar.Category
---@param name string
---@param meta Hangar.Definition
---@return string installation
---@return string? install_error
local function installation_status(category, name, meta)
  local managed = meta.mason or category == "package"
  local installed, install_error
  if category == "parser" then
    installed, install_error =
      category_handlers.parser.installation_status(name)
  elseif managed then
    installed, install_error = mason.package_status(meta.mason or name)
  end

  if managed and mason.is_installing(meta.mason or name) then
    return "installing", install_error
  elseif install_error then
    return "unavailable", install_error
  elseif installed == true then
    return "installed"
  elseif installed == false then
    return "missing"
  elseif category ~= "parser" and not managed then
    return "external"
  end
  return "unknown"
end

---Read the runtime state of a toggleable tool.
---@return string? runtime
---@return string text
---@return string severity
local function runtime_status(handler, opts)
  if not handler.capabilities.toggle then
    return nil, "Not applicable", "DiagnosticWarn"
  end

  local runtime, highlight, facts = handler.entry_status(opts)
  local text = runtime_label(runtime)
  if facts and facts.diagnostics then
    local diagnostics = facts.diagnostics
    text = string.format(
      "Diagnostics: %d errors, %d warnings",
      diagnostics.error_count,
      diagnostics.warn_count
    )
    return runtime, text, "DiagnosticInfo"
  elseif runtime == "no binary" then
    return runtime, text, "DiagnosticWarn"
  end
  return runtime, text, highlight or "DiagnosticWarn"
end

---Pick the primary label. Installation and saved state rank above runtime.
---@return string label
---@return string severity
local function primary_label(handler, opts, status)
  if status.installation == "installing" then
    return "Installing…", "DiagnosticInfo"
  elseif status.enabled == false then
    -- Conform still runs a tool listed under "*" or "_", which hangar leaves.
    local special = handler.special_listing
      and handler.special_listing({ name = opts.name, meta = opts.meta })
    if special then
      return string.format('Disabled, still listed under "%s"', special),
        "DiagnosticWarn"
    end
    return "Disabled", "Comment"
  elseif status.installation == "missing" then
    return "Not installed", "DiagnosticWarn"
  elseif
    status.installation == "unavailable" or status.installation == "unknown"
  then
    return "Unknown", "DiagnosticWarn"
  elseif not handler.capabilities.toggle then
    return "Installed", "Comment"
  elseif status.runtime == "disabled" then
    return "Not active", "DiagnosticWarn"
  elseif status.runtime == "idle" then
    return status.label, "Comment"
  end
  return status.label, status.severity
end

---Read installation and runtime independently; saved enablement only selects the
---primary label, never hides the underlying facts in details.
---@param category Hangar.Category
---@param name string
---@param meta Hangar.Definition
---@param filetype? string
---@return table
function M.health_status(category, name, meta, filetype, bufnr)
  local handler = category_handlers[category]
  local enabled
  if handler.capabilities.toggle then
    enabled = state_mod.is_enabled(category, name)
  end
  local source = category == "parser" and "Tree-sitter"
    or (meta.mason and "Mason")
    or meta.source
    or "External"
  local installation, install_error = installation_status(category, name, meta)

  local opts = { name = name, meta = meta, filetype = filetype, bufnr = bufnr }
  local runtime, runtime_text, runtime_severity = runtime_status(handler, opts)
  local label, severity = primary_label(handler, opts, {
    installation = installation,
    enabled = enabled,
    runtime = runtime,
    label = runtime_text,
    severity = runtime_severity,
  })
  return {
    label = label,
    severity = severity,
    enabled = enabled,
    installation = installation,
    source = source,
    runtime = runtime_text,
    reason = install_error,
    attention = severity == "DiagnosticError" or severity == "DiagnosticWarn",
  }
end

---@param category Hangar.Category
---@param ft? string
---@return Hangar.FtGroup[]
function M.build_ft_groups(category, ft)
  local groups = order.build_ft_groups(category)
  if not ft or ft == "" then
    return groups
  end

  return vim.tbl_filter(function(group)
    return group.ft == ft
  end, groups)
end

---Count one tool status into the snapshot summary.
local function count(summary, health_status)
  local function add(key)
    summary[key] = summary[key] + 1
  end

  if health_status.attention then
    add("attention")
  end
  if health_status.enabled == true then
    add("enabled")
  elseif health_status.enabled == false then
    add("disabled")
  end
  if health_status.installation == "installed" then
    add("installed")
  elseif health_status.installation == "missing" then
    add("missing")
  end
end

---Build one snapshot row. A cached runtime failure overrides the label.
---@param failure? string
local function tool_row(category, entry, ft, bufnr, failure)
  local health_status =
    M.health_status(category, entry.name, entry.meta, ft, bufnr)
  if failure then
    health_status.reason = failure
    health_status.label = "Apply failed"
    health_status.severity = "DiagnosticError"
    health_status.attention = true
  end
  return {
    name = entry.name,
    meta = vim.deepcopy(entry.meta),
    status = health_status.label,
    status_hl = health_status.severity,
    enabled = state_mod.is_enabled(category, entry.name),
    health_status = health_status,
  }
end

---Build the rows, groups and summary of one category. The buffer scope lists
---only tools of the source filetype.
---@param opts Hangar.SnapshotOptions with a valid category
---@param failures table<string, string> runtime failure by `category:name`
---@return table
function M.snapshot(opts, failures)
  local category = opts.category
  local source = opts.source or {}
  local bufnr = source.bufnr or vim.api.nvim_get_current_buf()
  local ft = source.filetype
  if ft == nil and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    ft = vim.bo[bufnr].filetype
  end
  local states = opts.scope == "states"
  local entries, groups = {}, {}
  if states then
    entries = M.tool_entries(category)
    groups = M.build_ft_groups(category)
  elseif ft ~= nil and ft ~= "" then
    entries = M.tool_entries(category, ft)
    groups = M.build_ft_groups(category, ft)
  end

  local snapshot = {
    category = category,
    tools = {},
    groups = groups,
    summary = {
      total = #entries,
      enabled = 0,
      disabled = 0,
      installed = 0,
      missing = 0,
      attention = 0,
    },
  }
  local row_ft = (not states) and ft or nil
  for _, entry in ipairs(entries) do
    local failure = failures[category .. ":" .. entry.name]
    local row = tool_row(category, entry, row_ft, bufnr, failure)
    table.insert(snapshot.tools, row)
    count(snapshot.summary, row.health_status)
  end
  return snapshot
end

return M
