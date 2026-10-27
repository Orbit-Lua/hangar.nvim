local Popup = require("nui.popup")
local Layout = require("nui.layout")
local manager = require("hangar.manager")
local render = require("hangar.ui.render")
local details = require("hangar.ui.details")
local tool_config = require("hangar.config")

local function ui()
  return tool_config.get().ui
end

local View = {}
View.__index = View

function View:category()
  return ui().categories[self.state.category]
end

function View:active()
  return not self.closed
    and self.body.winid
    and vim.api.nvim_win_is_valid(self.body.winid)
end

-- Minimum frame content: two-cell row prefix, tool, enabled and status columns.
local MIN_CONTENT_WIDTH = 23

---Effective spacing for the current editor. When the configured spacing does
---not fit, it shrinks in a fixed order, each value to its minimum before the
---next one shrinks; the settings keep their configured values.
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

local function dimensions()
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

local function sections(view, height)
  local compact = height < 8
  return Layout.Box({
    Layout.Box(view.header, { size = compact and 2 or 4 }),
    Layout.Box(view.body, { grow = 1 }),
    Layout.Box(view.footer, { size = compact and 1 or 2 }),
  }, { dir = "col" })
end

function View:current()
  if self.state.help or not self.tree or not self:active() then
    return nil
  end
  -- Return only the node; get_node also returns its line number.
  local node =
    self.tree:get_node(vim.api.nvim_win_get_cursor(self.body.winid)[1])
  return node
end

function View:refresh(first, identity)
  if not self:active() then
    return
  end
  -- Opening and ColorScheme both refresh; existing definitions stay.
  render.define_highlights()
  local selected = self:current()
  local selected_id = identity or selected and selected.id
  selected_id = selected_id or self.saved_selection
  local cursor_position = vim.api.nvim_win_get_cursor(self.body.winid)
  local previous_window = vim.api.nvim_get_current_win()
  local size, frame_position, space = dimensions()
  self.spacing = space
  self.frame_geometry = { size = size, position = frame_position }
  self.frame:update_layout({ size = size, position = frame_position })
  self.layout:update({}, sections(self, size.height))
  local snapshot = manager.snapshot({
    category = self:category(),
    scope = self.state.scope,
    source = self.source,
  })
  self.snapshot = snapshot
  -- Display-width calculations must use the unwrapped list window even when
  -- details currently has focus and linebreak enabled.
  vim.api.nvim_win_call(self.body.winid, function()
    render.chrome(self, snapshot)
    if self.state.help then
      render.help(self)
      details.preview(self, nil)
    else
      render.tree(self, snapshot)
      local selected_line
      if selected_id then
        local _, line = self.tree:get_node(selected_id)
        selected_line = line
      end
      local count = vim.api.nvim_buf_line_count(self.body.bufnr)
      local target_line = first and (self.spacing.vertical + 1)
        or selected_line
        or math.min(cursor_position[1], count)
      vim.api.nvim_win_set_cursor(
        self.body.winid,
        { math.min(target_line, count), 0 }
      )
      details.preview(self, self:current())
    end
    if self.details and previous_window == self.details.winid then
      vim.api.nvim_set_current_win(self.details.winid)
    end
  end)
end

function View:schedule_refresh(debounce)
  if self.closed then
    return
  end
  if debounce then
    if not self.timer then
      self.timer = vim.uv.new_timer()
    end
    self.timer:stop()
    self.timer:start(ui().refresh.debounce_ms, 0, function()
      vim.schedule(function()
        if not self.closed then
          self:refresh()
        end
      end)
    end)
  elseif not self.pending_refresh then
    self.pending_refresh = true
    vim.schedule(function()
      self.pending_refresh = false
      self:refresh()
    end)
  end
end

function View:close()
  if self.closed then
    return
  end
  self.closed = true
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
  if self.unsubscribe then
    self.unsubscribe()
    self.unsubscribe = nil
  end
  if self.group then
    vim.api.nvim_del_augroup_by_id(self.group)
    self.group = nil
  end
  details.close(self)
  self.layout:unmount()
  self.frame:unmount()
  self.on_close(self)
end

function View:action(action)
  if action == "close" then
    self:close()
    return
  end
  if action == "help" then
    local selected = self:current()
    if selected then
      self.saved_selection = selected.id
    end
    self.state.help = not self.state.help
    self:refresh()
    return
  end
  if action == "scope" then
    self.state.scope = self.state.scope == "buffer" and "states" or "buffer"
    self:refresh(true)
    return
  end
  if action == "next" or action == "previous" then
    self.state.category = (
      (self.state.category - 1 + (action == "next" and 1 or -1))
      % #ui().categories
    ) + 1
    self:refresh(true)
    return
  end
  local node = self:current()
  if not node then
    return
  end
  if action == "expand" then
    while not node:has_children() and node:get_parent_id() do
      node = self.tree:get_node(node:get_parent_id())
    end
    if node:has_children() then
      self.state.expanded[node.id] = not node:is_expanded()
      self.saved_selection = node.id
      self:refresh(false, node.id)
    end
    return
  end
  if action == "details" then
    details.show(self, node)
    return
  end
  if not node.tool then
    return
  end
  local selection = {
    category = self:category(),
    name = node.tool.name,
    filetype = node.filetype,
  }
  local function completed(success, err)
    if success == false and err then
      vim.notify("Hangar: " .. err, vim.log.levels.WARN)
    end
    -- The operation outlives the view; this callback only updates its own session.
    self:schedule_refresh()
  end
  if action == "toggle" then
    manager.toggle(selection, completed)
  elseif action == "install" then
    manager.install(selection, completed)
  elseif action == "up" or action == "down" then
    selection.direction = action == "up" and -1 or 1
    manager.reorder(selection, completed)
  end
  self:refresh()
end

local function popup(filetype, border)
  return Popup({
    border = border or "none",
    focusable = filetype == "Hangar",
    buf_options = { filetype = filetype, buflisted = false },
    win_options = {
      wrap = false,
      linebreak = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
    },
  })
end

function View.new(source, state, on_close)
  local self =
    setmetatable({ source = source, state = state, on_close = on_close }, View)
  local size, position, space = dimensions()
  self.spacing = space
  self.frame_geometry = { size = size, position = position }
  self.frame = Popup({
    relative = "editor",
    position = position,
    size = size,
    border = tool_config.get().border,
    focusable = false,
    zindex = 49,
    buf_options = { filetype = "HangarFrame", buflisted = false },
    win_options = { wrap = false },
  })
  self.header = popup("HangarNavigation")
  self.body = popup("Hangar")
  self.footer = popup("HangarStatus")
  self.layout = Layout(self.frame, sections(self, size.height))
  self.layout:mount()
  -- Native title keeps the frame a single window, including external-close cleanup.
  vim.api.nvim_win_set_config(self.frame.winid, {
    title = " Hangar ",
    title_pos = "center",
  })
  vim.wo[self.body.winid].cursorline = true
  vim.api.nvim_set_current_win(self.body.winid)
  self.group = vim.api.nvim_create_augroup(
    "HangarView" .. self.body.bufnr,
    { clear = true }
  )
  self.unsubscribe = require("hangar.mason").observe(function()
    self:schedule_refresh()
  end)
  for _, mapping in ipairs(ui().mappings) do
    for _, key in ipairs(mapping.keys) do
      self.body:map("n", key, function()
        self:action(mapping.action)
      end, { nowait = true, silent = true, desc = mapping.description })
    end
  end
  for index = 1, #ui().categories do
    self.body:map("n", tostring(index), function()
      self.state.category = index
      self:refresh(true)
    end, { nowait = true, silent = true })
  end
  for _, component in ipairs({ self.frame, self.header, self.body, self.footer }) do
    vim.api.nvim_create_autocmd("WinClosed", {
      group = self.group,
      pattern = tostring(component.winid),
      once = true,
      callback = function()
        vim.schedule(function()
          self:close()
        end)
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = self.group,
      buffer = component.bufnr,
      once = true,
      callback = function()
        vim.schedule(function()
          self:close()
        end)
      end,
    })
  end
  vim.api.nvim_create_autocmd(
    { "LspAttach", "LspDetach", "VimResized", "ColorScheme" },
    {
      group = self.group,
      callback = function(event)
        if event.event == "VimResized" then
          details.resize(self)
        end
        self:schedule_refresh()
      end,
    }
  )
  vim.api.nvim_create_autocmd("User", {
    group = self.group,
    pattern = { "TSUpdate", "HangarChanged" },
    callback = function()
      self:schedule_refresh()
    end,
  })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = self.group,
    callback = function()
      if self:category() == "linter" then
        self:schedule_refresh(true)
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = self.group,
    pattern = "NvimLintRunPost",
    callback = function()
      if self:category() == "linter" then
        self:schedule_refresh(true)
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = self.group,
    buffer = self.body.bufnr,
    callback = function()
      details.preview(self, self:current())
    end,
  })
  self:refresh(true)
  return self
end

return View
