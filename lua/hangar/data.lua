local M = {}

local config = require("hangar.config")
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
  for name, meta in pairs(config.get().registry[category] or {}) do
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

---Read installation and runtime independently; saved enablement only selects the
---primary label, never hides the underlying facts in details.
---@param category Hangar.Category
---@param name string
---@param meta Hangar.Definition
---@param filetype? string
---@return table
function M.health_status(category, name, meta, filetype, bufnr)
  local handler = category_handlers[category]
  local toggleable = handler.capabilities.toggle
  local enabled
  if toggleable then
    enabled = state_mod.is_enabled(category, name)
  end
  local source = category == "parser" and "Tree-sitter"
    or (meta.mason and "Mason")
    or meta.source
    or "External"
  local installed, install_error
  if category == "parser" then
    installed, install_error = handler.installation_status(name)
  elseif meta.mason or category == "package" then
    installed, install_error = mason.package_status(meta.mason or name)
  end
  local installing = (meta.mason or category == "package")
      and mason.is_installing(meta.mason or name)
    or false
  local installation
  if installing then
    installation = "installing"
  elseif install_error then
    installation = "unavailable"
  elseif installed == true then
    installation = "installed"
  elseif installed == false then
    installation = "missing"
  elseif category ~= "parser" and not meta.mason and category ~= "package" then
    installation = "external"
  else
    installation = "unknown"
  end

  local runtime, runtime_highlight, facts
  if toggleable then
    runtime, runtime_highlight, facts = handler.entry_status({
      name = name,
      meta = meta,
      filetype = filetype,
      bufnr = bufnr,
    })
  end
  local runtime_text = toggleable and runtime_label(runtime) or "Not applicable"
  local label, severity = runtime_text, runtime_highlight or "DiagnosticWarn"
  if facts and facts.diagnostics then
    local diagnostics = facts.diagnostics
    label = string.format(
      "Diagnostics: %d errors, %d warnings",
      diagnostics.error_count,
      diagnostics.warn_count
    )
    runtime_text = label
    severity = "DiagnosticInfo"
  elseif runtime == "no binary" then
    severity = "DiagnosticWarn"
  end
  if installing then
    label, severity = "Installing…", "DiagnosticInfo"
  elseif enabled == false then
    -- Conform still runs a tool listed under "*" or "_", which hangar leaves.
    local special = handler.special_listing
      and handler.special_listing({ name = name, meta = meta })
    if special then
      label = string.format('Disabled, still listed under "%s"', special)
      severity = "DiagnosticWarn"
    else
      label, severity = "Disabled", "Comment"
    end
  elseif installation == "missing" then
    label, severity = "Not installed", "DiagnosticWarn"
  elseif installation == "unavailable" or installation == "unknown" then
    label, severity = "Unknown", "DiagnosticWarn"
  elseif not toggleable then
    label, severity = "Installed", "Comment"
  elseif runtime == "disabled" then
    label, severity = "Not active", "DiagnosticWarn"
  elseif runtime == "idle" then
    severity = "Comment"
  end
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

return M
