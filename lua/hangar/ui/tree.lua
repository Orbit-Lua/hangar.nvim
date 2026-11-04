local Line = require("nui.line")
local Tree = require("nui.tree")
local str = require("hangar.util")
local tool_config = require("hangar.config")
local render = require("hangar.ui.render")

local M = {}

local function icons()
  return tool_config.get().icons
end

---Pick the status icon state of a tool row.
---@return string
local function icon_state(tool, severity)
  local health = tool.health_status
  if health and health.installation == "installing" then
    return "installing"
  elseif
    health
    and health.enabled == false
    and severity ~= "DiagnosticError"
  then
    return "disabled"
  elseif
    health
    and (
      health.installation == "unknown"
      or health.installation == "unavailable"
    )
  then
    return "unknown"
  elseif severity == "DiagnosticError" then
    return "error"
  elseif severity == "DiagnosticWarn" then
    return "warning"
  elseif tool.enabled and health and health.runtime == "Idle" then
    return "idle"
  elseif tool.enabled and severity == "DiagnosticInfo" then
    return "info"
  end
  return tool.enabled and "enabled" or "disabled"
end

---Append the icon, name, enabled and status columns of a tool row.
local function append_tool(line, node, width, column_gap)
  local tool = node.tool
  local health = tool.health_status
  local status = health and health.label or tool.status or "Unknown"
  local severity = health and health.severity or tool.status_hl
  local state = icon_state(tool, severity)
  local icon, icon_highlight = icons()[state], render.icon_highlights[state]
  local name = node.rank and (node.rank .. ". " .. tool.name) or tool.name
  local enabled_text = (node.category == "parser" or node.category == "package")
      and "N/A"
    or (tool.enabled and "On" or "Off")
  local widths =
    render.column_widths(width, column_gap, math.max(1, width - line:width()))
  local gap = string.rep(" ", column_gap)
  local text_highlight = tool.enabled and "Normal" or "Comment"

  -- The icon is its own chunk, so its state highlight stays separate.
  local icon_text = icon .. " "
  local name_width =
    math.max(1, widths.tool - vim.fn.strdisplaywidth(icon_text))
  line:append(icon_text, icon_highlight)
  line:append(str.rpad(str.trunc(name, name_width), name_width), text_highlight)
  line:append(
    gap .. str.rpad(str.trunc(enabled_text, widths.enabled), widths.enabled),
    text_highlight
  )
  line:append(gap .. str.trunc(status, widths.status), severity)
end

local function node_line(node, width, column_gap)
  local line = Line()
  local indent = string.rep("  ", node:get_depth() - 1)
  local arrow = node:has_children()
      and (node:is_expanded() and icons().expanded or icons().collapsed)
    or " "
  line:append(
    indent .. arrow .. " ",
    node.kind == "detail" and "Comment" or "Title"
  )

  local rest = math.max(1, width - line:width())
  if node.kind == "group" then
    line:append(
      str.trunc(node.filetype .. " (" .. #node.names .. " tools)", rest),
      "Title"
    )
  elseif node.kind == "detail" or node.kind == "empty" then
    line:append(str.trunc(node.text, rest), "Comment")
  else
    append_tool(line, node, width, column_gap)
  end
  return line
end

local function tool_node(view, category, tool, filetype, rank)
  local id = category
    .. ":"
    .. tool.name
    .. (filetype and ":" .. filetype or "")
  local node = Tree.Node({
    id = id,
    kind = "tool",
    category = category,
    tool = tool,
    filetype = filetype,
    rank = rank,
  })
  if view.state.expanded[id] then
    node:expand()
  end
  return node
end

---Tool nodes of one filetype group, in saved rank order.
local function ranked_nodes(view, category, group, by_name)
  local nodes = {}
  for rank, name in ipairs(group.names) do
    if by_name[name] then
      table.insert(
        nodes,
        tool_node(view, category, by_name[name], group.ft, rank)
      )
    end
  end
  return nodes
end

---Formatters and linters list by filetype: flat for one buffer, grouped
---for all states. Other categories list their tools.
local function build_nodes(view, snapshot)
  local category = snapshot.category
  local nodes = {}
  if category ~= "formatter" and category ~= "linter" then
    for _, tool in ipairs(snapshot.tools) do
      table.insert(nodes, tool_node(view, category, tool))
    end
    return nodes
  end

  local by_name = {}
  for _, tool in ipairs(snapshot.tools) do
    by_name[tool.name] = tool
  end
  for _, group in ipairs(snapshot.groups) do
    local children = ranked_nodes(view, category, group, by_name)
    if view.state.scope == "buffer" then
      vim.list_extend(nodes, children)
    else
      local id = category .. ":ft:" .. group.ft
      local node = Tree.Node({
        id = id,
        kind = "group",
        filetype = group.ft,
        names = group.names,
      }, children)
      if view.state.expanded[id] then
        node:expand()
      end
      table.insert(nodes, node)
    end
  end
  return nodes
end

local function blank_lines(bufnr, start, count)
  vim.api.nvim_buf_set_lines(
    bufnr,
    start,
    -1,
    false,
    vim.fn["repeat"]({ "" }, count)
  )
end

---Render the body tree of a snapshot.
function M.render(view, snapshot)
  local nodes = build_nodes(view, snapshot)
  if #snapshot.tools == 0 then
    local scope = view.state.scope == "buffer" and "buffer filetype."
      or "category."
    table.insert(
      nodes,
      Tree.Node({
        id = snapshot.category .. ":empty",
        kind = "empty",
        text = "No managed tools for this " .. scope,
      })
    )
  end

  local bufnr = view.body.bufnr
  vim.bo[bufnr].readonly = false
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_clear_namespace(bufnr, view.body.ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  local width = render.content_width(view, view.body.winid)
  local vertical = view.spacing.vertical
  if vertical > 0 then
    blank_lines(bufnr, 0, vertical)
  end
  view.tree = Tree({
    bufnr = bufnr,
    ns_id = view.body.ns_id,
    nodes = nodes,
    get_node_id = function(node)
      return node.id
    end,
    prepare_node = function(node)
      return render.pad(view, node_line(node, width, view.spacing.column_gap))
    end,
  })
  view.tree:render(vertical + 1)
  if vertical > 0 then
    -- Tree rendering restores the buffer's read-only state.
    vim.bo[bufnr].modifiable = true
    blank_lines(bufnr, -1, vertical)
  end
  vim.bo[bufnr].modifiable = false
end

return M
