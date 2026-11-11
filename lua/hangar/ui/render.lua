local Line = require("nui.line")
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
  for group, link in pairs({
    HangarColumnHeader = "Title",
    HangarContext = "Comment",
    HangarSeparator = "FloatBorder",
  }) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

---Report whether the tools of a category have an enabled state.
---@param category Hangar.Category
---@return boolean
function M.toggleable(category)
  local handler = require("hangar.category")[category]
  return handler ~= nil and handler.capabilities.toggle
end

---Prefix a line with the horizontal padding.
function M.pad(view, line)
  local padded = Line()
  padded:append(string.rep(" ", view.spacing.horizontal))
  padded:append(line)
  return padded
end

---Text width inside a window after horizontal padding on both sides.
function M.content_width(view, winid)
  return math.max(
    1,
    vim.api.nvim_win_get_width(winid) - 2 * view.spacing.horizontal
  )
end

---Widths of the tool, enabled and status columns.
---@param width integer content width
---@param column_gap integer
---@param available integer cells left after the row prefix
---@return { tool: integer, enabled: integer, status: integer }
function M.column_widths(width, column_gap, available)
  local enabled = math.min(10, math.max(7, math.floor(width * 0.14)))
  local tool = math.max(
    1,
    math.min(math.floor(width * 0.48), available - enabled - 2 * column_gap - 1)
  )
  local status = math.max(1, available - tool - enabled - 2 * column_gap)
  return { tool = tool, enabled = enabled, status = status }
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
    M.pad(view, line):render(buffer, popup.ns_id, top + index)
  end
  vim.bo[buffer].modifiable = false
end

local function separator(width)
  local line = Line()
  line:append(string.rep("─", width), "HangarSeparator")
  return line
end

---Category tabs: all labels, or only the current one in a narrow window.
local function tab_line(view, width)
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
    return tabs
  end

  for index, category in ipairs(ui().categories) do
    local selected = index == current
    tabs:append(
      " " .. index .. " " .. ui().labels[category] .. " ",
      selected and active_highlight or "HangarCategoryInactive"
    )
    tabs:append(" ", "Normal")
  end
  return tabs
end

---Scope, tool count, source buffer and attention count.
local function context_line(view, snapshot, width)
  local context = Line()
  local function add(text, highlight)
    context:append(
      str.trunc(text, math.max(0, width - context:width())),
      highlight
    )
  end

  local buffer_scope = view.state.scope == "buffer"
  add(buffer_scope and " Buffer" or " All", "Title")
  add(" · " .. #snapshot.tools .. " tools", "Normal")
  if buffer_scope then
    local source = view.source
    local filename = source.name == "" and "[No Name]"
      or vim.fs.basename(source.name)
    local filetype = source.filetype == "" and "no filetype" or source.filetype
    add(" · " .. filetype .. " · " .. filename, "HangarContext")
  end
  if snapshot.summary and (snapshot.summary.attention or 0) > 0 then
    add(
      " · " .. snapshot.summary.attention .. " need attention",
      "DiagnosticWarn"
    )
  end
  return context
end

---A hint names the first key of a configured action; an unbound action has
---no hint.
---@return { [1]: string, [2]: string }?
local function hint(action)
  for _, mapping in ipairs(ui().mappings) do
    if mapping.action == action and mapping.keys[1] then
      return { (mapping.keys[1]:gsub("^<(.*)>$", "%1")), action }
    end
  end
end

---Key hints of the current category that fit the width.
local function hint_line(view, width)
  local category = view:category()
  local wanted = width < 50 and { "help", "scope", "close" }
    or { "toggle", "install", "details", "scope", "help", "close" }
  if not M.toggleable(category) then
    wanted = vim.tbl_filter(function(action)
      return action ~= "toggle"
    end, wanted)
  end
  local actions = {}
  for _, action in ipairs(wanted) do
    table.insert(actions, hint(action))
  end
  local up, down = hint("up"), hint("down")
  if
    width >= 75
    and up
    and down
    and (category == "formatter" or category == "linter")
  then
    table.insert(actions, 1, { up[1] .. "/" .. down[1], "priority" })
  end

  local hints = Line()
  for _, action in ipairs(actions) do
    local text = " " .. action[1] .. " " .. action[2]
    if hints:width() + vim.fn.strdisplaywidth(text) > width then
      break
    end
    hints:append(" " .. action[1], "Special")
    hints:append(" " .. action[2], "Comment")
  end
  return hints
end

---Render the header and the footer of the view.
function M.chrome(view, snapshot)
  local width = M.content_width(view, view.header.winid)
  local header = { tab_line(view, width) }
  local function header_gap()
    for _ = 1, view.header_gap do
      table.insert(header, Line())
    end
  end
  header_gap()
  table.insert(header, context_line(view, snapshot, width))
  -- Normal height adds the column labels and a separator; compact keeps two rows.
  if vim.api.nvim_win_get_height(view.header.winid) > 2 then
    header_gap()
    table.insert(header, M.columns(width, view.spacing.column_gap))
    table.insert(header, separator(width))
  end
  write(view, view.header, header)

  local footer = {}
  if vim.api.nvim_win_get_height(view.footer.winid) > 1 then
    table.insert(footer, separator(width))
  end
  table.insert(footer, hint_line(view, width))
  write(view, view.footer, footer)
end

---Column labels aligned with tool rows, which start after a two-cell prefix.
---@param width integer
function M.columns(width, column_gap)
  local line = Line()
  local gap = string.rep(" ", column_gap)
  local widths = M.column_widths(width, column_gap, math.max(1, width - 2))
  line:append("  " .. str.rpad("Tool", widths.tool), "HangarColumnHeader")
  line:append(gap .. str.rpad("Enabled", widths.enabled), "HangarColumnHeader")
  line:append(gap .. str.trunc("Status", widths.status), "HangarColumnHeader")
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
  local width = M.content_width(view, view.body.winid)
  local lines = {}
  local function add(text, highlight)
    local line = Line()
    line:append(str.trunc(text, width), highlight)
    table.insert(lines, line)
  end
  add(" Hangar · Help", "Title")
  add("", "Normal")
  local labels = vim.tbl_map(function(category)
    return ui().labels[category] or category
  end, ui().categories)
  add(
    string.format(
      " %s  Select category (%s)",
      #labels == 1 and "1" or ("1–" .. #labels),
      table.concat(labels, ", ")
    ),
    "Normal"
  )
  for _, mapping in ipairs(ui().mappings) do
    add(
      " " .. table.concat(mapping.keys, " / ") .. "  " .. mapping.description,
      "Normal"
    )
  end
  add("", "Normal")
  add(" Packages can be installed; they cannot be toggled.", "Comment")
  add(" A disabled parser stops Tree-sitter for its language.", "Comment")
  add(" Formatter and linter priorities are saved per filetype.", "Comment")
  write(view, view.body, lines, view.spacing.vertical)
  view.tree = nil
end

return M
