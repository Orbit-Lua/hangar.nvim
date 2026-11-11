local tool_config = require("hangar.config")

local function ui()
  return tool_config.get().ui
end

local M = {}

---@class Hangar.Spacing
---@field margin integer
---@field gap integer
---@field vertical integer
---@field horizontal integer
---@field column_gap integer

-- Minimum frame content: two-cell row prefix, tool, enabled and status columns.
local MIN_CONTENT_WIDTH = 23

---Share header allocation with the renderer, reserving useful body rows first.
---@param height integer
---@param space Hangar.Spacing
---@return { header: integer, footer: integer, header_gap: integer }
function M.sections(height, space)
  if height < 8 then
    return { header = 2, footer = 1, header_gap = 0 }
  end
  local gap = math.min(
    ui().layout.header_gap,
    math.max(0, math.floor((height - 7 - 2 * space.vertical) / 2))
  )
  return { header = 4 + 2 * gap, footer = 2, header_gap = gap }
end

---Effective spacing for the current editor. When the configured spacing does
---not fit, it shrinks in a fixed order, each value to its minimum before the
---next one shrinks; the settings keep their configured values.
---@return Hangar.Spacing
local function spacing()
  local layout = ui().layout
  local value = {
    margin = layout.margin,
    gap = layout.gap,
    vertical = layout.padding.vertical,
    horizontal = layout.padding.horizontal,
    column_gap = layout.column_gap,
  }
  local columns, rows = vim.o.columns, vim.o.lines - vim.o.cmdheight
  local function fits()
    local width = 2
      + 2 * value.horizontal
      + MIN_CONTENT_WIDTH
      + 2 * value.column_gap
    -- A normal frame needs header 4, body 1 and footer 2 rows. Compact frames
    -- appear only when even the minimum spacing cannot provide them.
    local height = 2 + 7 + 2 * value.vertical
    return columns >= width + 2 * value.margin
      and rows >= height + 2 * value.margin
  end
  for _, item in ipairs({
    { "margin", 0 },
    { "gap", 0 },
    { "vertical", 0 },
    { "horizontal", 0 },
    { "column_gap", 1 },
  }) do
    while not fits() and value[item[1]] > item[2] do
      value[item[1]] = value[item[1]] - 1
    end
  end
  return value
end

---Frame size and position for the current editor, with the spacing that fits.
---@return { width: integer, height: integer } size
---@return string|{ row: integer, col: integer } position
---@return Hangar.Spacing space
function M.frame()
  local space = spacing()
  local margin, gap = space.margin, space.gap
  local columns, rows = vim.o.columns, vim.o.lines - vim.o.cmdheight
  local size = {
    width = math.max(3, math.min(ui().width, columns - 2 * margin - 2)),
    height = math.max(5, math.min(ui().height, rows - 2 * margin - 2)),
  }
  local position = "50%"
  local tall = rows >= 22
  if tall and columns >= 150 then
    -- Frame and details sit side by side with `gap` cells between borders.
    local available = columns - 2 * margin - 4 - gap
    local details_width =
      math.min(ui().details.width, math.floor(available / 2))
    size.width = math.min(size.width, available - details_width)
    local total = size.width + details_width + 4 + gap
    position = {
      row = math.max(margin, math.floor((vim.o.lines - size.height) / 2) - 1),
      col = math.max(margin, math.floor((columns - total) / 2)),
    }
  elseif tall and columns >= 85 then
    size.height =
      math.min(size.height, math.floor((rows - 2 * margin - gap - 5) * 0.58))
    position = { row = margin, col = math.floor((columns - size.width) / 2) }
  end
  if size.height < 8 then
    -- Compact frames have no room for vertical padding.
    space.vertical = 0
  end
  return size, position, space
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

---Details size and placement: a pane to the right of or below the frame, or
---a centered popup when neither fits.
---@return integer width
---@return integer height
---@return "right"|"bottom"|"popup" placement
function M.details(view)
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

---Details window layout for its placement, clamped to the editor.
---@return { position: { row: integer, col: integer }, size: { width: integer, height: integer } }
function M.details_layout(view)
  local width, height, placement = M.details(view)
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
  return {
    position = { row = row, col = col },
    size = { width = width, height = height },
  }
end

return M
