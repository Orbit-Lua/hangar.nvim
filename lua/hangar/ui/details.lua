local Popup = require("nui.popup")
local Line = require("nui.line")
local tool_config = require("hangar.config")
local geometry = require("hangar.ui.geometry")
local details_content = require("hangar.ui.details_content")

local M = {}

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

---Write the details items below the vertical padding.
local function write_lines(view, popup)
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
  for _, item in ipairs(details_content.lines(view, view.details_node)) do
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

local function redraw(view)
  local popup = view.details
  if
    not popup
    or not popup.winid
    or not vim.api.nvim_win_is_valid(popup.winid)
  then
    return
  end
  popup:update_layout(geometry.details_layout(view))
  vim.api.nvim_win_set_option(popup.winid, "wrap", true)
  vim.api.nvim_win_set_option(popup.winid, "linebreak", true)
  write_lines(view, popup)
end

---Mount the details window and bind its close keys and cleanup.
local function open_popup(view)
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
    local _, _, current = geometry.details(view)
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

  local function forget()
    vim.schedule(function()
      if not view.closed then
        close_popup(view, popup)
      end
    end)
  end
  popup:on("BufWipeout", forget, { once = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = view.group,
    pattern = tostring(popup.winid),
    once = true,
    callback = forget,
  })
end

function M.close(view)
  close_popup(view)
end

---@param node? table tool, group or empty node; nil shows the category overview
function M.preview(view, node, force)
  node = node or { kind = "overview" }
  local _, _, placement = geometry.details(view)
  if placement == "popup" and not force and view.details_mode ~= "focused" then
    close_popup(view)
    return
  end
  view.details_node = node
  if not view.details then
    open_popup(view)
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
    local _, _, placement = geometry.details(view)
    if placement == "popup" and view.details_mode ~= "focused" then
      close_popup(view)
    else
      redraw(view)
    end
  end
end

return M
