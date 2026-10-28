local M = {}

local cleanup_paths = {}
local mapping_modes = { "n", "v", "x", "s", "o", "i", "l", "c", "t" }

local function restore_mappings(previous, buffer)
  for mode, mappings in pairs(previous) do
    local current = buffer and vim.api.nvim_buf_get_keymap(buffer, mode)
      or vim.api.nvim_get_keymap(mode)
    for _, mapping in ipairs(current) do
      if buffer then
        pcall(vim.api.nvim_buf_del_keymap, buffer, mode, mapping.lhs)
      else
        pcall(vim.api.nvim_del_keymap, mode, mapping.lhs)
      end
    end
    for _, mapping in ipairs(mappings) do
      vim.fn.mapset(mode, false, mapping)
    end
  end
end

local function fixture_path(path)
  local root = vim.fs
    .normalize(vim.fn.fnamemodify(vim.g.hangar_test_root, ":p"))
    :gsub("/$", "")
  local resolved =
    vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
  local compared_root, compared_path = root, resolved
  if package.config:sub(1, 1) == "\\" then
    compared_root, compared_path = root:lower(), resolved:lower()
  end
  assert(
    compared_path:sub(1, #compared_root + 1) == compared_root .. "/",
    "fixture escapes test root: " .. path
  )
  return resolved
end

---Run all hooks inside an isolated Neovim context, including failed assertions.
function M.run_isolated(run)
  local loaded = vim.tbl_extend("force", {}, package.loaded)
  local preload = vim.tbl_extend("force", {}, package.preload)
  local outer_paths = cleanup_paths
  cleanup_paths = {}
  local globals = vim.fn.eval("g:")
  local options, buffers, windows, timers, autocmds, mappings =
    {}, {}, {}, {}, {}, {}
  local buffer_mappings = {}
  local current = vim.api.nvim_get_current_win()
  for name, info in pairs(vim.api.nvim_get_all_options_info()) do
    if not info.immutable then
      local ok, value =
        pcall(vim.api.nvim_get_option_value, name, { scope = "global" })
      if ok then
        options[name] = value
      end
    end
  end
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    buffers[buffer] = {}
    buffer_mappings[buffer] = {}
    for _, mode in ipairs(mapping_modes) do
      buffer_mappings[buffer][mode] = vim.api.nvim_buf_get_keymap(buffer, mode)
    end
    for name, info in pairs(vim.api.nvim_get_all_options_info()) do
      if info.scope == "buf" then
        buffers[buffer][name] =
          vim.api.nvim_get_option_value(name, { buf = buffer })
      end
    end
  end
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    windows[window] =
      { buffer = vim.api.nvim_win_get_buf(window), options = {} }
    for name, info in pairs(vim.api.nvim_get_all_options_info()) do
      if info.scope == "win" then
        windows[window].options[name] =
          vim.api.nvim_get_option_value(name, { win = window })
      end
    end
  end
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
    if autocmd.id then
      autocmds[autocmd.id] = true
    end
  end
  vim.uv.walk(function(handle)
    timers[handle] = true
  end)
  for _, mode in ipairs(mapping_modes) do
    mappings[mode] = vim.api.nvim_get_keymap(mode)
  end
  local ok, err = xpcall(run, debug.traceback)
  vim.uv.walk(function(handle)
    if
      not timers[handle]
      and not handle:is_closing()
      and handle:get_type() == "timer"
    then
      handle:stop()
      handle:close()
    end
  end)
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
    if autocmd.id and not autocmds[autocmd.id] then
      pcall(vim.api.nvim_del_autocmd, autocmd.id)
    end
  end
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if not windows[window] then
      pcall(vim.api.nvim_win_close, window, true)
    end
  end
  if vim.api.nvim_win_is_valid(current) then
    vim.api.nvim_set_current_win(current)
  end
  for window, previous in pairs(windows) do
    if vim.api.nvim_win_is_valid(window) then
      if vim.api.nvim_buf_is_valid(previous.buffer) then
        vim.api.nvim_win_set_buf(window, previous.buffer)
      end
      for name, value in pairs(previous.options) do
        if vim.api.nvim_get_option_value(name, { win = window }) ~= value then
          pcall(vim.api.nvim_set_option_value, name, value, { win = window })
        end
      end
    end
  end
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if not buffers[buffer] then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
  end
  restore_mappings(mappings)
  for buffer, previous in pairs(buffer_mappings) do
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_call(buffer, function()
        restore_mappings(previous, buffer)
      end)
    end
  end
  for name, value in pairs(options) do
    if vim.api.nvim_get_option_value(name, { scope = "global" }) ~= value then
      pcall(vim.api.nvim_set_option_value, name, value, { scope = "global" })
    end
  end
  for buffer, previous in pairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      for name, value in pairs(previous) do
        if vim.api.nvim_get_option_value(name, { buf = buffer }) ~= value then
          pcall(vim.api.nvim_set_option_value, name, value, { buf = buffer })
        end
      end
    end
  end
  for name in pairs(vim.fn.eval("g:")) do
    if globals[name] == nil then
      vim.g[name] = nil
    end
  end
  for name, value in pairs(globals) do
    if not vim.deep_equal(value, vim.g[name]) then
      vim.g[name] = value
    end
  end
  for name in pairs(package.loaded) do
    package.loaded[name] = loaded[name]
  end
  for name, value in pairs(loaded) do
    package.loaded[name] = value
  end
  for name in pairs(package.preload) do
    package.preload[name] = preload[name]
  end
  for name, value in pairs(preload) do
    package.preload[name] = value
  end
  M.cleanup_all()
  cleanup_paths = outer_paths
  if not ok then
    error(err, 0)
  end
end

function M.setup()
  local busted = require("plenary.busted")
  local run = busted.it
  busted.it = function(description, callback)
    M.run_isolated(function()
      run(description, callback)
    end)
  end
  _G.it = busted.it
end

-- Compare filesystem identity without requiring platform-specific separators.
function M.assert_path(expected, actual, message)
  assert.equals(vim.fs.normalize(expected), vim.fs.normalize(actual), message)
end

local function test_root()
  local root = vim.g.hangar_test_root
  assert(type(root) == "string" and root ~= "", "test bootstrap is not loaded")
  return root
end

---@param name string
---@return string
function M.plugin_path(name)
  local deps = vim.g.hangar_test_deps_path
  assert(
    type(deps) == "string" and deps ~= "",
    "test dependency path is unavailable; run just deps"
  )
  return deps .. "/" .. name
end

---@param suffix? string
---@return string
function M.temp_dir(suffix)
  local path = fixture_path(
    test_root() .. "/tmp/" .. (suffix or tostring(#cleanup_paths + 1))
  )
  assert(vim.fn.mkdir(path, "p") == 1 or vim.fn.isdirectory(path) == 1)
  table.insert(cleanup_paths, path)
  return path
end

---@param path string
---@param content string|string[]
function M.write_file(path, content)
  path = fixture_path(path)
  local parent = vim.fn.fnamemodify(path, ":h")
  assert(vim.fn.mkdir(parent, "p") == 1 or vim.fn.isdirectory(parent) == 1)
  local lines = type(content) == "table" and content
    or vim.split(content, "\n", { plain = true })
  assert.equals(0, vim.fn.writefile(lines, path))
end

local logs = {}

---Record linter run errors that the fixture `adapters.linter.logs` returns.
---@param name string
---@param entries table[]
function M.set_logs(name, entries)
  logs[name] = entries
end

---Fixture options: the extracted registry, its activation, the test state
---path and the recorded linter logs.
---@return Hangar.Options
function M.options()
  return {
    registry = require("tests.fixtures.registry"),
    state_path = function()
      return vim.g.hangar_state_path
    end,
    adapters = {
      activation = {
        formatter = function()
          return require("tests.fixtures.activation").formatters_by_ft
        end,
        linter = function()
          return require("tests.fixtures.activation").linters_by_ft
        end,
      },
      linter = {
        logs = function(name)
          return logs[name] or {}
        end,
      },
    },
  }
end

---Configure hangar with the fixture options, replacing top-level options.
---Call it again after resetting `hangar.*` modules.
---@param overrides? table
function M.configure(overrides)
  require("hangar").setup(vim.tbl_extend("force", M.options(), overrides or {}))
end

function M.cleanup_all()
  logs = {}
  for _, path in ipairs(cleanup_paths) do
    if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
      vim.fn.delete(fixture_path(path), "rf")
    end
  end
  cleanup_paths = {}
end

return M
