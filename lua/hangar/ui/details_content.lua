local tool_config = require("hangar.config")
local render = require("hangar.ui.render")

local function ui()
  return tool_config.get().ui
end

local M = {}

---@alias Hangar.DetailsItem { [1]: string, [2]: string }|{ [1]: { [1]: string, [2]: string }[] }

local installation_labels = {
  installed = "Installed",
  missing = "Not installed",
  broken = "Broken install",
  installing = "Installing…",
  external = "Externally managed",
  unavailable = "Unknown",
  unknown = "Unknown",
}

---@return Hangar.DetailsItem[]
local function health_lines(tool, category)
  local health = tool.health_status or {}
  local toggleable = render.toggleable(category)
  local enabled = "N/A"
  if toggleable then
    local value = health.enabled
    if value == nil then
      value = tool.enabled
    end
    enabled = value and "On" or "Off"
  end
  local source = health.source
    or tool.meta.source
    or (category == "parser" and "Tree-sitter")
    or (tool.meta.mason and "Mason")
    or "External"
  local lines = {
    { "Enabled: " .. enabled, "Normal" },
    {
      "Installation: "
        .. (
          installation_labels[health.installation]
          or health.installation
          or tool.status
          or "Unknown"
        ),
      "Normal",
    },
    { "Source: " .. source, "Normal" },
    {
      "Runtime: "
        .. (health.runtime or (toggleable and tool.status) or "Not applicable"),
      "Normal",
    },
  }
  if health.reason then
    table.insert(lines, { health.reason, "DiagnosticWarn" })
  end
  return lines
end

---Linter logs and diagnostics, capped at `details.max_messages` diagnostics.
---@param lines Hangar.DetailsItem[]
local function append_linter_facts(lines, tool)
  local facts = require("hangar.manager").details({
    category = "linter",
    name = tool.name,
  })
  for _, entry in ipairs(facts.logs) do
    table.insert(lines, {
      entry.level .. " " .. entry.message,
      entry.level == "ERROR" and "DiagnosticError" or "DiagnosticWarn",
    })
  end

  local messages = facts.diagnostics.messages
  local max = ui().details.max_messages
  for index, diagnostic in ipairs(messages) do
    if index > max then
      table.insert(lines, {
        "+" .. (#messages - max) .. " more diagnostics",
        "Comment",
      })
      break
    end
    table.insert(lines, {
      string.format(
        "%s:%d %s",
        diagnostic.file,
        diagnostic.lnum,
        diagnostic.message
      ),
      diagnostic.severity == vim.diagnostic.severity.ERROR
          and "DiagnosticError"
        or "DiagnosticWarn",
    })
  end
end

---@return Hangar.DetailsItem[]
local function tool_content(view, tool, node)
  local lines = { { tool.name, "Title" } }
  vim.list_extend(lines, health_lines(tool, view:category()))
  table.insert(lines, {
    "Filetypes: " .. table.concat(tool.meta.ft or {}, ", "),
    "Comment",
  })
  if render.toggleable(view:category()) then
    table.insert(lines, { "Enablement: Global", "Comment" })
  end
  if node and node.rank then
    table.insert(
      lines,
      { string.format("Priority: %s #%d", node.filetype, node.rank), "Comment" }
    )
  end
  if tool.meta.runtime_name then
    table.insert(lines, { "Backend: " .. tool.meta.runtime_name, "Comment" })
  end
  if tool.meta.mason then
    table.insert(lines, { "Mason package: " .. tool.meta.mason, "Comment" })
  end
  if tool.meta.note then
    table.insert(lines, { "", "Normal" })
    table.insert(lines, { tool.meta.note, "Comment" })
  end
  if view:category() == "linter" and tool.enabled then
    append_linter_facts(lines, tool)
  end
  return lines
end

---@return Hangar.DetailsItem[]
local function group_content(view, node)
  local by_name = {}
  for _, tool in ipairs(view.snapshot and view.snapshot.tools or {}) do
    by_name[tool.name] = tool
  end
  local lines = {
    { node.filetype, "Title" },
    { "Priority order for this filetype:", "Comment" },
  }
  for rank, name in ipairs(node.names or {}) do
    local tool = by_name[name]
    local enabled = tool and (tool.enabled and "On" or "Off") or ""
    table.insert(lines, {
      string.format("%d. %s  %s", rank, name, enabled),
      tool and not tool.enabled and "Comment" or "Normal",
    })
  end
  table.insert(lines, { "", "Normal" })
  table.insert(lines, {
    "Expand the group and use [ / ] on a tool to change its priority.",
    "Comment",
  })
  return lines
end

---@return Hangar.DetailsItem[]
local function empty_content(view, node)
  local lines = { { "No tools", "Title" }, { node.text, "Normal" } }
  if view.state.scope == "buffer" then
    table.insert(
      lines,
      { "Press s to list every registered tool in this category.", "Comment" }
    )
  end
  return lines
end

---Category counts and the status icon legend, shown when no row is selected.
---@return Hangar.DetailsItem[]
local function overview_content(view)
  local summary = view.snapshot and view.snapshot.summary or {}
  local function count(label, value, highlight)
    return { string.format("%s: %d", label, value or 0), highlight or "Normal" }
  end
  local lines = {
    { ui().labels[view:category()] .. " overview", "Title" },
    count("Tools", summary.total),
    count("Enabled", summary.enabled),
    count("Disabled", summary.disabled, "Comment"),
    count("Installed", summary.installed),
    count("Missing", summary.missing, "DiagnosticWarn"),
    count("Need attention", summary.attention, "DiagnosticWarn"),
    { "", "Normal" },
    { "Legend", "Title" },
  }
  for _, entry in ipairs(render.legend()) do
    table.insert(lines, {
      { { entry.icon, entry.highlight }, { "  " .. entry.label, "Normal" } },
    })
  end
  return lines
end

---Content for the node under the cursor; an overview node shows the category
---overview. An item is either `{ text, highlight }` or a list of segments.
---@return Hangar.DetailsItem[]
function M.lines(view, node)
  if node.kind == "tool" then
    return tool_content(view, node.tool, node)
  elseif node.kind == "group" then
    return group_content(view, node)
  elseif node.kind == "empty" then
    return empty_content(view, node)
  end
  return overview_content(view)
end

return M
