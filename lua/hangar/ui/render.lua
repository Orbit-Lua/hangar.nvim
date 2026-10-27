local Line = require("nui.line")
local Tree = require("nui.tree")
local str = require("hangar.util")
local tool_config = require("hangar.config")

local function ui()
  return tool_config.get().ui
end

local function icons()
  return tool_config.get().icons
end

local M = {}

---Highlight group of each status icon. Each links by default to a diagnostic
---or comment group, so a theme or the user can override it.
M.icon_highlights = {
  enabled = "HangarIconEnabled",
  idle = "HangarIconIdle",
  info = "HangarIconInfo",
  installing = "HangarIconInstalling",
  warning = "HangarIconWarning",
  error = "HangarIconError",
  unknown = "HangarIconUnknown",
  disabled = "HangarIconDisabled",
}

local icon_links = {
  enabled = "DiagnosticOk",
  idle = "Comment",
  info = "DiagnosticInfo",
  installing = "DiagnosticInfo",
  warning = "DiagnosticWarn",
  error = "DiagnosticError",
  unknown = "DiagnosticWarn",
  disabled = "Comment",
}

---Define the icon groups without replacing existing definitions. Call it again
---after a color scheme clears highlights.
function M.define_highlights()
  for state, group in pairs(M.icon_highlights) do
    vim.api.nvim_set_hl(0, group, { link = icon_links[state], default = true })
  end
  vim.api.nvim_set_hl(
    0,
    "HangarCategoryActive",
    { link = "TabLineSel", default = true }
  )
  vim.api.nvim_set_hl(
    0,
    "HangarCategoryInactive",
    { link = "TabLine", default = true }
  )
end

---Prefix a line with the horizontal padding.
local function pad(view, line)
  local padded = Line()
  padded:append(string.rep(" ", view.spacing.horizontal))
  padded:append(line)
  return padded
end

---Text width inside a window after horizontal padding on both sides.
local function content_width(view, winid)
  return math.max(
    1,
    vim.api.nvim_win_get_width(winid) - 2 * view.spacing.horizontal
  )
end

local function write(view, popup, lines, top)
  local buffer = popup.bufnr
  vim.bo[buffer].readonly = false
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_clear_namespace(buffer, popup.ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {})
  top = top or 0
  if top > 0 then
    vim.api.nvim_buf_set_lines(
      buffer,
      0,
      -1,
      false,
      vim.fn["repeat"]({ "" }, top)
    )
  end
  for index, line in ipairs(lines) do
    pad(view, line):render(buffer, popup.ns_id, top + index)
  end
  vim.bo[buffer].modifiable = false
end

function M.chrome(view, snapshot)
  local width = content_width(view, view.header.winid)
  local tabs = Line()
  local current = view.state.category
  local active_highlight = "HangarCategoryActive"
  if width < 75 then
    tabs:append(
      str.trunc(
        " " .. current .. " " .. ui().labels[view:category()] .. " ",
        width
      ),
      active_highlight
    )
    tabs:append(
      str.trunc(" · Tab switch", math.max(0, width - tabs:width())),
      "Comment"
    )
  else
    for index, category in ipairs(ui().categories) do
      local selected = index == current
      tabs:append(
        " " .. index .. " " .. ui().labels[category] .. " ",
        selected and active_highlight or "HangarCategoryInactive"
      )
      tabs:append(" ", "Normal")
    end
  end
  local context = Line()
  local buffer_scope = view.state.scope == "buffer"
  context:append(
    str.trunc(buffer_scope and " Buffer" or " All", width),
    "Title"
  )
  context:append(
    str.trunc(
      " · " .. #snapshot.tools .. " tools",
      math.max(0, width - context:width())
    ),
    "Normal"
  )
  if buffer_scope then
    local source = view.source
    local filename = source.name == "" and "[No Name]"
      or vim.fs.basename(source.name)
    local filetype = source.filetype == "" and "no filetype" or source.filetype
    context:append(
      str.trunc(
        " · " .. filetype .. " · " .. filename,
        math.max(0, width - context:width())
      ),
      "Comment"
    )
  end
  if snapshot.summary and (snapshot.summary.attention or 0) > 0 then
    context:append(
      str.trunc(
        " · " .. snapshot.summary.attention .. " need attention",
        math.max(0, width - context:width())
      ),
      "DiagnosticWarn"
    )
  end
  local function separator()
    local line = Line()
    line:append(string.rep("─", width), "FloatBorder")
    return line
  end
  local header = { tabs, context }
  -- Normal height adds the column labels and a separator; compact keeps two rows.
  if vim.api.nvim_win_get_height(view.header.winid) > 2 then
    table.insert(header, M.columns(width, view.spacing.column_gap))
    table.insert(header, separator())
  end
  write(view, view.header, header)
  local hints = Line()
  local category = view:category()
  local actions = width < 50
      and { { "?", "help" }, { "s", "scope" }, { "q", "close" } }
    or {
      { "Space", "toggle" },
      { "i", "install" },
      { "K", "details" },
      { "s", "scope" },
      { "?", "help" },
      { "q", "close" },
    }
  if category == "parser" or category == "package" then
    actions = vim.tbl_filter(function(action)
      return action[1] ~= "Space"
    end, actions)
  end
  if width >= 75 and (category == "formatter" or category == "linter") then
    table.insert(actions, 1, { "[/]", "priority" })
  end
  for _, action in ipairs(actions) do
    local text = " " .. action[1] .. " " .. action[2]
    if hints:width() + vim.fn.strdisplaywidth(text) > width then
      break
    end
    hints:append(" " .. action[1], "Special")
    hints:append(" " .. action[2], "Comment")
  end
  local footer = {}
  if vim.api.nvim_win_get_height(view.footer.winid) > 1 then
    table.insert(footer, separator())
  end
  table.insert(footer, hints)
  write(view, view.footer, footer)
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
  if node.kind == "group" then
    line:append(
      str.trunc(
        node.filetype .. " (" .. #node.names .. " tools)",
        math.max(1, width - line:width())
      ),
      "Title"
    )
  elseif node.kind == "detail" then
    line:append(
      str.trunc(node.text, math.max(1, width - line:width())),
      "Comment"
    )
  elseif node.kind == "empty" then
    line:append(
      str.trunc(node.text, math.max(1, width - line:width())),
      "Comment"
    )
  else
    local tool = node.tool
    local health = tool.health_status
    local status = health and health.label or tool.status or "Unknown"
    local severity = health and health.severity or tool.status_hl
    local state = tool.enabled and "enabled" or "disabled"
    if health and health.installation == "installing" then
      state = "installing"
    elseif
      health
      and health.enabled == false
      and severity ~= "DiagnosticError"
    then
      state = "disabled"
    elseif
      health
      and (
        health.installation == "unknown"
        or health.installation == "unavailable"
      )
    then
      state = "unknown"
    elseif severity == "DiagnosticError" then
      state = "error"
    elseif severity == "DiagnosticWarn" then
      state = "warning"
    elseif tool.enabled and health and health.runtime == "Idle" then
      state = "idle"
    elseif tool.enabled and severity == "DiagnosticInfo" then
      state = "info"
    end
    local icon, icon_highlight = icons()[state], M.icon_highlights[state]
    local name = node.rank and (node.rank .. ". " .. tool.name) or tool.name
    local enabled_text = (
      node.category == "parser" or node.category == "package"
    )
        and "N/A"
      or (tool.enabled and "On" or "Off")
    local enabled_width = math.min(10, math.max(7, math.floor(width * 0.14)))
    local available = math.max(1, width - line:width())
    local gap = string.rep(" ", column_gap)
    local tool_width = math.max(
      1,
      math.min(
        math.floor(width * 0.48),
        available - enabled_width - 2 * column_gap - 1
      )
    )
    local status_width =
      math.max(1, available - tool_width - enabled_width - 2 * column_gap)
    -- The icon is its own chunk, so its state highlight stays separate.
    local icon_text = icon .. " "
    local name_width =
      math.max(1, tool_width - vim.fn.strdisplaywidth(icon_text))
    line:append(icon_text, icon_highlight)
    line:append(
      str.rpad(str.trunc(name, name_width), name_width),
      tool.enabled and "Normal" or "Comment"
    )
    line:append(
      gap .. str.rpad(str.trunc(enabled_text, enabled_width), enabled_width),
      tool.enabled and "Normal" or "Comment"
    )
    line:append(gap .. str.trunc(status, status_width), severity)
  end
  return line
end

function M.tree(view, snapshot)
  local by_name = {}
  for _, tool in ipairs(snapshot.tools) do
    by_name[tool.name] = tool
  end
  local nodes = {}
  local category = snapshot.category
  local function tool_node(tool, filetype, rank)
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
  if category == "formatter" or category == "linter" then
    if view.state.scope == "buffer" then
      for _, group in ipairs(snapshot.groups) do
        for rank, name in ipairs(group.names) do
          if by_name[name] then
            table.insert(nodes, tool_node(by_name[name], group.ft, rank))
          end
        end
      end
    else
      for _, group in ipairs(snapshot.groups) do
        local children = {}
        for rank, name in ipairs(group.names) do
          if by_name[name] then
            table.insert(children, tool_node(by_name[name], group.ft, rank))
          end
        end
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
  else
    for _, tool in ipairs(snapshot.tools) do
      table.insert(nodes, tool_node(tool))
    end
  end
  if #snapshot.tools == 0 then
    table.insert(
      nodes,
      Tree.Node({
        id = category .. ":empty",
        kind = "empty",
        text = "No managed tools for this "
          .. (
            view.state.scope == "buffer" and "buffer filetype." or "category."
          ),
      })
    )
  end
  vim.bo[view.body.bufnr].readonly = false
  vim.bo[view.body.bufnr].modifiable = true
  vim.api.nvim_buf_clear_namespace(view.body.bufnr, view.body.ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(view.body.bufnr, 0, -1, false, {})
  local width = content_width(view, view.body.winid)
  local vertical = view.spacing.vertical
  if vertical > 0 then
    vim.api.nvim_buf_set_lines(
      view.body.bufnr,
      0,
      -1,
      false,
      vim.fn["repeat"]({ "" }, vertical)
    )
  end
  view.tree = Tree({
    bufnr = view.body.bufnr,
    ns_id = view.body.ns_id,
    nodes = nodes,
    get_node_id = function(node)
      return node.id
    end,
    prepare_node = function(node)
      return pad(view, node_line(node, width, view.spacing.column_gap))
    end,
  })
  view.tree:render(vertical + 1)
  if vertical > 0 then
    -- Tree rendering restores the buffer's read-only state.
    vim.bo[view.body.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(
      view.body.bufnr,
      -1,
      -1,
      false,
      vim.fn["repeat"]({ "" }, vertical)
    )
  end
  vim.bo[view.body.bufnr].modifiable = false
end

---Column labels aligned with tool rows, which start after a two-cell prefix.
---@param width integer
function M.columns(width, column_gap)
  local line = Line()
  local gap = string.rep(" ", column_gap)
  local enabled_width = math.min(10, math.max(7, math.floor(width * 0.14)))
  local available = math.max(1, width - 2)
  local tool_width = math.max(
    1,
    math.min(
      math.floor(width * 0.48),
      available - enabled_width - 2 * column_gap - 1
    )
  )
  local status_width =
    math.max(1, available - tool_width - enabled_width - 2 * column_gap)
  line:append("  " .. str.rpad("Tool", tool_width), "Title")
  line:append(gap .. str.rpad("Enabled", enabled_width), "Title")
  line:append(gap .. str.trunc("Status", status_width), "Title")
  return line
end

---Status icons in display order, with the meaning shown in the overview legend.
function M.legend()
  local glyphs = icons()
  local entries = {
    { state = "enabled", label = "Enabled and active" },
    { state = "idle", label = "Enabled, idle" },
    { state = "info", label = "Enabled, with information" },
    { state = "installing", label = "Installing" },
    { state = "warning", label = "Needs attention" },
    { state = "error", label = "Failed or missing executable" },
    { state = "unknown", label = "Availability unknown" },
    { state = "disabled", label = "Disabled" },
  }
  for _, entry in ipairs(entries) do
    entry.icon = glyphs[entry.state]
    entry.highlight = M.icon_highlights[entry.state]
  end
  return entries
end

function M.help(view)
  local width = content_width(view, view.body.winid)
  local lines = {}
  local function add(text, highlight)
    local line = Line()
    line:append(str.trunc(text, width), highlight)
    table.insert(lines, line)
  end
  add(" Hangar · Help", "Title")
  add("", "Normal")
  add(
    " 1–6  Select category (LSP, DAP, Linter, Formatter, Parser, Package)",
    "Normal"
  )
  for _, mapping in ipairs(ui().mappings) do
    add(
      " " .. table.concat(mapping.keys, " / ") .. "  " .. mapping.description,
      "Normal"
    )
  end
  add("", "Normal")
  add(
    " Parsers and packages can be installed; they cannot be toggled.",
    "Comment"
  )
  add(" Formatter and linter priorities are saved per filetype.", "Comment")
  write(view, view.body, lines, view.spacing.vertical)
  view.tree = nil
end

return M
