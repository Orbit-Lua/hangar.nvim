local Popup = require("nui.popup")
local Line = require("nui.line")
local tool_config = require("hangar.config")

local function ui()
  return tool_config.get().ui
end

local M = {}

local installation_labels = {
  installed = "Installed",
  missing = "Not installed",
  installing = "Installing…",
  external = "Externally managed",
  unavailable = "Unknown",
  unknown = "Unknown",
}

local function health_lines(tool, category)
  local health = tool.health_status or {}
  local toggleable = category ~= "parser" and category ~= "package"
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

local function tool_content(view, tool, node)
  local lines = { { tool.name, "Title" } }
  for _, item in ipairs(health_lines(tool, view:category())) do
    table.insert(lines, item)
  end
  table.insert(lines, {
    "Filetypes: " .. table.concat(tool.meta.ft or {}, ", "),
    "Comment",
  })
  if view:category() ~= "parser" and view:category() ~= "package" then
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
    local diagnostics = facts.diagnostics
    for index, diagnostic in ipairs(diagnostics.messages) do
      if index > ui().details.max_messages then
        table.insert(lines, {
          "+"
            .. (#diagnostics.messages - ui().details.max_messages)
            .. " more diagnostics",
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
  return lines
end

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
  for _, entry in ipairs(require("hangar.ui.render").legend()) do
    table.insert(lines, {
      { { entry.icon, entry.highlight }, { "  " .. entry.label, "Normal" } },
    })
  end
  return lines
end

---Content for the node under the cursor; a missing node shows the overview.
local function content(view, node)
  if node.kind == "tool" then
    return tool_content(view, node.tool, node)
  elseif node.kind == "group" then
    return group_content(view, node)
  elseif node.kind == "empty" then
    return empty_content(view, node)
  end
  return overview_content(view)
end

-- Window positions are outer border coordinates; sizes exclude the border.
-- Use the frame geometry computed for this refresh: the frame window can still
-- report its previous layout while Nui applies the update.
local function frame_box(view)
  local geometry = view.frame_geometry
  if geometry and type(geometry.position) == "table" then
    return geometry.position.row,
      geometry.position.col,
      geometry.size.width,
      geometry.size.height
  end
  local position = vim.api.nvim_win_get_position(view.frame.winid)
  return position[1],
    position[2],
    vim.api.nvim_win_get_width(view.frame.winid),
    vim.api.nvim_win_get_height(view.frame.winid)
end

local function geometry(view)
  local margin, gap = view.spacing.margin, view.spacing.gap
  local columns = vim.o.columns
  local rows = vim.o.lines - vim.o.cmdheight - 2
  local width = math.max(
    1,
    math.min(
      math.max(20, math.min(ui().details.width, columns - 4)),
      columns - 2 * margin - 2
    )
  )
  local height = math.max(4, math.min(rows - 2, 22))
  if columns >= 150 and rows >= 20 then
    return width, height, "right"
  elseif columns >= 85 and rows >= 20 then
    local frame_row, _, _, frame_height = frame_box(view)
    local detail_row = frame_row + frame_height + 2 + gap
    local remaining = vim.o.lines - vim.o.cmdheight - detail_row - 2 - margin
    if remaining >= 4 then
      return width, math.min(height, 14, remaining), "bottom"
    end
  end
  return math.min(width, columns - 2),
    math.max(1, math.min(height, rows - 2 * margin)),
    "popup"
end

local function close_popup(view, expected)
  if view.details then
    local popup = view.details
    if expected and popup ~= expected then
      return
    end
    view.details = nil
    view.details_node = nil
    view.details_mode = nil
    popup:unmount()
  end
end

local function redraw(view)
  local popup = view.details
  if
    not popup
    or not popup.winid
    or not vim.api.nvim_win_is_valid(popup.winid)
  then
    return
  end
  local width, height, placement = geometry(view)
  local row, col
  local margin, gap = view.spacing.margin, view.spacing.gap
  if placement == "right" then
    row = math.max(margin, math.floor((vim.o.lines - height) / 2) - 1)
    local _, frame_col, frame_width = frame_box(view)
    col = frame_col + frame_width + 2 + gap
    width = math.max(1, math.min(width, vim.o.columns - col - 2 - margin))
  elseif placement == "bottom" then
    width = math.min(width, vim.o.columns - 2 * margin - 2)
    local frame_row, _, _, frame_height = frame_box(view)
    row = frame_row + frame_height + 2 + gap
    if row + height > vim.o.lines - vim.o.cmdheight - 2 - margin then
      row = vim.o.lines - vim.o.cmdheight - height - 2 - margin
    end
    col = math.floor((vim.o.columns - width) / 2)
  else
    width = math.min(width, vim.o.columns - 4)
    height = math.min(height, vim.o.lines - vim.o.cmdheight - 4)
    row = math.floor((vim.o.lines - height) / 2) - 1
    col = math.floor((vim.o.columns - width) / 2)
  end
  popup:update_layout({
    position = { row = row, col = col },
    size = { width = width, height = height },
  })
  vim.api.nvim_win_set_option(popup.winid, "wrap", true)
  vim.api.nvim_win_set_option(popup.winid, "linebreak", true)
  vim.bo[popup.bufnr].modifiable = true
  vim.api.nvim_buf_clear_namespace(popup.bufnr, popup.ns_id, 0, -1)
  local top = view.spacing.vertical
  vim.api.nvim_buf_set_lines(
    popup.bufnr,
    0,
    -1,
    false,
    vim.fn["repeat"]({ "" }, top)
  )
  local indent = string.rep(" ", view.spacing.horizontal)
  local linenr = top
  for _, item in ipairs(content(view, view.details_node)) do
    local line = Line()
    line:append(indent)
    -- An item is either { text, highlight } or { { { text, highlight }, ... } }.
    for _, segment in ipairs(type(item[1]) == "table" and item[1] or { item }) do
      -- Tool output such as a linter's error text can span several lines,
      -- and a buffer line cannot hold a newline.
      local parts = vim.split(segment[1], "\r?\n")
      for part_index, part in ipairs(parts) do
        if part_index > 1 then
          linenr = linenr + 1
          line:render(popup.bufnr, popup.ns_id, linenr)
          line = Line()
          line:append(indent)
        end
        line:append(part, segment[2])
      end
    end
    linenr = linenr + 1
    line:render(popup.bufnr, popup.ns_id, linenr)
  end
  vim.bo[popup.bufnr].modifiable = false
end

function M.close(view)
  close_popup(view)
end

---@param node? table tool, group or empty node; nil shows the category overview
function M.preview(view, node, force)
  node = node or { kind = "overview" }
  local _, _, placement = geometry(view)
  if placement == "popup" and not force and view.details_mode ~= "focused" then
    close_popup(view)
    return
  end
  view.details_node = node
  if not view.details then
    view.details_mode = view.details_mode or "preview"
    view.details = Popup({
      enter = false,
      relative = "editor",
      position = { row = 1, col = 1 },
      size = { width = 40, height = 10 },
      border = tool_config.get().border,
      zindex = 60,
      buf_options = { filetype = "HangarDetails", buflisted = false },
      win_options = { wrap = true, linebreak = true },
    })
    view.details:mount()
    local popup = view.details
    -- A mounted pane stays open and only returns focus; a popup closes.
    local function close()
      local _, _, current = geometry(view)
      if current == "popup" then
        close_popup(view, popup)
      else
        view.details_mode = "preview"
      end
      if view:active() then
        vim.api.nvim_set_current_win(view.body.winid)
      end
    end
    for _, key in ipairs({ "q", "<Esc>" }) do
      popup:map("n", key, close, { nowait = true, silent = true })
    end
    popup:on("BufWipeout", function()
      vim.schedule(function()
        if not view.closed then
          close_popup(view, popup)
        end
      end)
    end, { once = true })
    vim.api.nvim_create_autocmd("WinClosed", {
      group = view.group,
      pattern = tostring(popup.winid),
      once = true,
      callback = function()
        vim.schedule(function()
          if not view.closed then
            close_popup(view, popup)
          end
        end)
      end,
    })
  end
  redraw(view)
end

function M.show(view, node)
  view.details_mode = "focused"
  M.preview(view, node, true)
  if view.details and vim.api.nvim_win_is_valid(view.details.winid) then
    vim.api.nvim_set_current_win(view.details.winid)
  end
end

function M.resize(view)
  if view.details then
    local _, _, placement = geometry(view)
    if placement == "popup" and view.details_mode ~= "focused" then
      close_popup(view)
    else
      redraw(view)
    end
  end
end

return M
