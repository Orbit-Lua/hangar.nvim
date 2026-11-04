local Popup = require("nui.popup")
local Layout = require("nui.layout")
local manager = require("hangar.manager")
local render = require("hangar.ui.render")
local tree = require("hangar.ui.tree")
local details = require("hangar.ui.details")
local geometry = require("hangar.ui.geometry")
local actions = require("hangar.ui.actions")
local tool_config = require("hangar.config")

local function ui()
  return tool_config.get().ui
end

local View = {}
View.__index = View

---Keep the selected category valid after the categories change: follow its
---name, or select the first category when it is gone.
---@param state { category: integer, category_name: string? }
function View.normalize(state)
  local categories = ui().categories
  local index = state.category_name
      and (vim.fn.index(categories, state.category_name) + 1)
    or state.category
  if not categories[index] then
    index = 1
  end
  state.category, state.category_name = index, categories[index]
end

---@param index integer
function View:select_category(index)
  self.state.category = index
  self.state.category_name = ui().categories[index]
end

function View:category()
  return ui().categories[self.state.category]
end

---Bind the configured mappings and one numeric key per category, replacing
---the keys of the previous options.
function View:map_keys()
  for _, key in ipairs(self.mapped or {}) do
    pcall(self.body.unmap, self.body, "n", key)
  end
  self.mapped = {}
  for _, mapping in ipairs(ui().mappings) do
    for _, key in ipairs(mapping.keys) do
      self.body:map("n", key, function()
        self:action(mapping.action)
      end, { nowait = true, silent = true, desc = mapping.description })
      table.insert(self.mapped, key)
    end
  end
  for index = 1, #ui().categories do
    self.body:map("n", tostring(index), function()
      self:select_category(index)
      self:refresh(true)
    end, { nowait = true, silent = true })
    table.insert(self.mapped, tostring(index))
  end
end

function View:active()
  return not self.closed
    and self.body.winid
    and vim.api.nvim_win_is_valid(self.body.winid)
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
  local size, frame_position, space = geometry.frame()
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
      tree.render(self, snapshot)
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
  actions.run(self, action)
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

---Close the whole view when any of its windows or buffers goes away.
local function close_with_windows(self)
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
end

---Refresh the view when tools, diagnostics, layout or colors change.
local function refresh_on_events(self)
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
    callback = function(event)
      if event.match == "HangarChanged" then
        View.normalize(self.state)
        self:map_keys()
      end
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
end

function View.new(source, state, on_close)
  local self =
    setmetatable({ source = source, state = state, on_close = on_close }, View)
  local size, position, space = geometry.frame()
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
  self:map_keys()
  close_with_windows(self)
  refresh_on_events(self)
  self:refresh(true)
  return self
end

return View
