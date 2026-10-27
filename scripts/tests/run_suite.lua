package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path
local validate = require("scripts.tests.validate")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local ok, err = pcall(function()
  assert(arg[1], "provide a test suite or spec")
  local paths = {}
  local stat = assert(vim.uv.fs_stat(arg[1]), "missing test suite: " .. arg[1])
  if stat.type == "directory" then
    local scan = assert(vim.uv.fs_scandir(arg[1]))
    while true do
      local name, kind = vim.uv.fs_scandir_next(scan)
      if not name then
        break
      end
      if kind == "file" and name:match("_spec%.lua$") then
        paths[#paths + 1] = arg[1] .. "/" .. name
      end
    end
  else
    paths[1] = arg[1]
  end
  assert(#paths > 0, "test suite contains no specs: " .. arg[1])
  table.sort(paths)
  for index, path in ipairs(paths) do
    local completion = root .. "/" .. index .. ".json"
    local result = vim
      .system({
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
      }, { text = true })
      :wait(60000)
    io.stdout:write(result.stdout or "")
    io.stderr:write(result.stderr or "")
    assert(result.code == 0, path .. ": test process failed or timed out")
    assert(
      vim.fn.filereadable(completion) == 1,
      path .. ": missing execution result"
    )
    validate.check(
      vim.json.decode(table.concat(vim.fn.readfile(completion), "\n"))
    )
  end
end)
vim.fn.delete(root, "rf")
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
