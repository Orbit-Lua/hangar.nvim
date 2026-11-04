-- Run each spec of a suite or one spec in its own Neovim process through
-- telemetry.nvim. Each child validates its own results and exits nonzero on a
-- failure; the parent checks only that the child reached its results.
local cwd = vim.fn.getcwd()
local telemetry_path = cwd .. "/.deps/telemetry.nvim"
if vim.fn.isdirectory(telemetry_path) == 0 then
  io.stderr:write("telemetry.nvim is missing; run just deps\n")
  vim.cmd("cquit 1")
end
package.path = table.concat({
  cwd .. "/?.lua",
  telemetry_path .. "/lua/?.lua",
  telemetry_path .. "/lua/?/init.lua",
  package.path,
}, ";")
local telemetry = require("telemetry")

---@param target string a spec file or a directory of `*_spec.lua` files
---@return string[]
local function discover(target)
  local stat = assert(vim.uv.fs_stat(target), "missing test suite: " .. target)
  if stat.type ~= "directory" then
    return { target }
  end

  local paths = {}
  for name, kind in vim.fs.dir(target) do
    if kind == "file" and name:match("_spec%.lua$") then
      paths[#paths + 1] = target .. "/" .. name
    end
  end
  assert(#paths > 0, "test suite contains no specs: " .. target)
  table.sort(paths)
  return paths
end

---@param root string
---@param index integer
---@param path string
---@return Telemetry.Suite
local function suite(root, index, path)
  local completion = root .. "/" .. index .. ".json"
  return {
    name = path,
    argv = {
      vim.v.progpath,
      "--headless",
      "--noplugin",
      "-i",
      "NONE",
      "-u",
      "scripts/tests/minimal.vim",
      "-l",
      "scripts/tests/run_spec.lua",
      path,
      completion,
    },
    timeout = 60000,
    check = function()
      if vim.fn.filereadable(completion) == 0 then
        return path .. ": missing execution result"
      end
    end,
  }
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local ok, result = pcall(function()
  local target = assert(arg[1], "provide a test suite or spec")
  local suites = {}
  for index, path in ipairs(discover(target)) do
    suites[index] = suite(root, index, path)
  end
  return telemetry.run({ title = target, suites = suites })
end)
vim.fn.delete(root, "rf")
if not ok then
  io.stderr:write(tostring(result) .. "\n")
  vim.cmd("cquit 1")
end
telemetry.exit(result)
