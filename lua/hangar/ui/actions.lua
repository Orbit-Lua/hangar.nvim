local manager = require("hangar.manager")
local details = require("hangar.ui.details")
local tool_config = require("hangar.config")

local function ui()
  return tool_config.get().ui
end

local M = {}

---Actions that act on the view, not on the selected node.
---@type table<string, fun(self: table)>
local view_actions = {}

function view_actions.close(self)
  self:close()
end

function view_actions.help(self)
  local selected = self:current()
  if selected then
    self.saved_selection = selected.id
  end
  self.state.help = not self.state.help
  self:refresh()
end

function view_actions.scope(self)
  self.state.scope = self.state.scope == "buffer" and "states" or "buffer"
  self:refresh(true)
end

local function step_category(self, step)
  local count = #ui().categories
  self:select_category(((self.state.category - 1 + step) % count) + 1)
  self:refresh(true)
end

function view_actions.next(self)
  step_category(self, 1)
end

function view_actions.previous(self)
  step_category(self, -1)
end

function view_actions.details(self)
  details.show(self, self:current())
end

function view_actions.back(self)
  details.back(self)
end

---Toggle the nearest group at or above the node.
local function expand(self, node)
  while not node:has_children() and node:get_parent_id() do
    node = self.tree:get_node(node:get_parent_id())
  end
  if node:has_children() then
    self.state.expanded[node.id] = not node:is_expanded()
    self.saved_selection = node.id
    self:refresh(false, node.id)
  end
end

---Send a tool action to the manager and refresh when it completes.
local function tool_action(self, action, node)
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

---Run a configured mapping action on the view.
function M.run(self, action)
  if view_actions[action] then
    view_actions[action](self)
    return
  end

  local node = self:current()
  if not node then
    return
  end
  if action == "expand" then
    expand(self, node)
  elseif node.tool then
    tool_action(self, action, node)
  end
end

return M
