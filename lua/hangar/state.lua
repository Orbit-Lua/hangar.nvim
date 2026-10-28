local M = {}

local _state = nil

local config = require("hangar.config")

local function state_path()
  return config.get().state_path()
end

local function build_defaults()
  local tools = config.get().registry
  local defaults = { formatter_order = {}, linter_order = {} }
  for _, cat in ipairs({ "lsp", "dap", "linter", "formatter" }) do
    defaults[cat] = {}
    for name in pairs(tools[cat] or {}) do
      defaults[cat][name] = true
    end
  end
  for ft, order in pairs(tools.formatter_defaults or {}) do
    defaults.formatter_order[ft] = vim.deepcopy(order)
  end
  for ft, order in pairs(tools.linter_defaults or {}) do
    defaults.linter_order[ft] = vim.deepcopy(order)
  end
  local configured = config.get().defaults()
  for _, category in ipairs({ "formatter", "linter" }) do
    for ft, order in pairs(configured[category] or {}) do
      defaults[category .. "_order"][ft] = vim.deepcopy(order)
    end
  end
  return defaults
end

local function is_string_list(value)
  if type(value) ~= "table" then
    return false
  end
  for _, item in ipairs(value) do
    if type(item) ~= "string" then
      return false
    end
  end
  return #value == vim.tbl_count(value)
end

---@param opts? { path: string? }
function M.load(opts)
  opts = opts or {}
  local file = io.open(opts.path or state_path(), "r")
  if not file then
    return build_defaults()
  end
  local raw = file:read("*a")
  file:close()
  local parse_ok, decoded = pcall(vim.json.decode, raw)
  if not parse_ok or type(decoded) ~= "table" then
    return build_defaults()
  end

  local state = build_defaults()
  for cat, val in pairs(decoded) do
    if type(val) == "table" then
      if cat == "formatter_order" or cat == "linter_order" then
        for ft, order in pairs(val) do
          if type(ft) == "string" and is_string_list(order) then
            local category = cat:gsub("_order$", "")
            local seen, normalized = {}, {}
            for _, name in ipairs(order) do
              local meta = config.get().registry[category][name]
              if
                meta
                and vim.tbl_contains(meta.ft or {}, ft)
                and not seen[name]
              then
                seen[name] = true
                table.insert(normalized, name)
              end
            end
            state[cat][ft] = normalized
          end
        end
      elseif state[cat] then
        for name, enabled in pairs(val) do
          if state[cat][name] ~= nil and type(enabled) == "boolean" then
            state[cat][name] = enabled
          end
        end
      end
    end
  end
  return state
end

---Forget the memoized state so the next read uses the current options.
function M.reset()
  _state = nil
end

function M.get()
  if not _state then
    _state = M.load()
  end
  return _state
end

-- A recovery guard serializes dead-owner reclamation with acquisition.
-- Uncertain ownership requires operator inspection, never age-based deletion.
local function owner(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local raw = file:read("*a")
  file:close()
  local ok, value = pcall(vim.json.decode, raw)
  if
    ok
    and type(value) == "table"
    and type(value.pid) == "number"
    and value.pid > 0
    and value.pid % 1 == 0
    and type(value.token) == "string"
    and value.token ~= ""
  then
    return value
  end
end

local function open_lock(path)
  local guard = path .. ".recovery"
  local guarded, guard_error = vim.uv.fs_mkdir(guard, 448)
  if not guarded then
    return nil, guard_error
  end
  local lock, err = vim.uv.fs_open(path, "wx", 384)
  if not lock then
    local previous = owner(path)
    if previous then
      local alive, _, code = vim.uv.kill(previous.pid, 0)
      if not alive and code == "ESRCH" then
        local removed, remove_error = vim.uv.fs_unlink(path)
        if removed then
          lock, err = vim.uv.fs_open(path, "wx", 384)
        else
          err = remove_error
        end
      end
    end
  end
  local token = tostring(vim.uv.os_getpid()) .. ":" .. tostring(vim.uv.hrtime())
  if lock then
    local payload = vim.json.encode({ pid = vim.uv.os_getpid(), token = token })
    local written, write_error = vim.uv.fs_write(lock, payload, 0)
    if written ~= #payload then
      write_error = write_error or "incomplete lock ownership record"
      vim.uv.fs_close(lock)
      vim.uv.fs_unlink(path)
      lock, err = nil, write_error
    end
  end
  local released, release_error = vim.uv.fs_rmdir(guard)
  if not released then
    if lock then
      vim.uv.fs_close(lock)
    end
    return nil,
      "recovery guard requires inspection: " .. tostring(release_error)
  end
  return lock, err, token
end

local function update(category, key, value)
  local path = state_path()
  local parent = vim.fn.fnamemodify(path, ":h")
  local made, mkdir_error = pcall(vim.fn.mkdir, parent, "p")
  if not made then
    return false, tostring(mkdir_error)
  end
  local lock_path = path .. ".lock"
  local lock, lock_error, token = open_lock(lock_path)
  if not lock then
    return false,
      "could not lock tool state; retry or inspect ownership before removing the lock: "
        .. tostring(lock_error)
  end
  local ok, saved, save_error = pcall(function()
    local latest = M.load()
    latest[category][key] = vim.deepcopy(value)
    local written, err =
      require("hangar.util").atomic_write(path, vim.json.encode(latest))
    if written then
      _state = latest
    end
    return written, err
  end)
  vim.uv.fs_close(lock)
  local current = owner(lock_path)
  local unlocked, unlock_error
  if current and current.token == token then
    unlocked, unlock_error = vim.uv.fs_unlink(lock_path)
  else
    unlock_error = "lock ownership changed"
  end
  if not ok then
    return false, tostring(saved)
  end
  if not unlocked then
    return false,
      "could not remove state lock: " .. tostring(unlock_error),
      ok and saved == true
  end
  return saved, save_error, saved == true
end

function M.is_enabled(cat, name)
  local state = M.get()
  if not state[cat] then
    return true
  end
  local v = state[cat][name]
  return v == nil or v == true
end

function M.set_enabled(cat, name, enabled)
  if not M.get()[cat] then
    return true
  end
  return update(cat, name, enabled)
end

---@param kind "formatter"|"linter"
function M.get_order(kind, ft)
  return M.get()[kind .. "_order"][ft]
end

---@param kind "formatter"|"linter"
function M.set_order(kind, ft, order)
  M.get()
  return update(kind .. "_order", ft, order)
end

return M
