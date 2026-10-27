describe("competing tool-state processes", function()
  it(
    "protects a live writer and merges the next process's unrelated choice",
    function()
      local test = require("tests.helpers")
      test.configure()
      local root = test.temp_dir("competing writers")
      local path, ready, release =
        root .. "/tools.json", root .. "/ready", root .. "/release"
      local script = root .. "/writer.lua"
      test.write_file(
        script,
        string.format(
          [[
vim.g.hangar_state_path = %q
require("hangar").setup({
  registry = require("tests.fixtures.registry"),
  state_path = function()
    return vim.g.hangar_state_path
  end,
})
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function(source, destination)
  if destination == vim.g.hangar_state_path then
    vim.fn.writefile({ "ready" }, %q)
    assert(vim.wait(15000, function() return vim.uv.fs_stat(%q) ~= nil end, 10))
  end
  return rename(source, destination)
end
assert(require("hangar.state").set_enabled("lsp", "lua_ls", false))
vim.cmd.qa()
]],
          path,
          ready,
          release
        )
      )
      local child = vim.system({
        vim.v.progpath,
        "--headless",
        "-i",
        "NONE",
        "-u",
        "scripts/tests/minimal.vim",
        "-c",
        "lua dofile(" .. vim.json.encode(script) .. ")",
      }, { text = true })
      local ok, err = xpcall(function()
        assert.is_true(vim.wait(10000, function()
          return vim.uv.fs_stat(ready) ~= nil
        end, 10))
        vim.g.hangar_state_path = path
        local state = require("hangar.state")
        assert(vim.uv.fs_utime(path .. ".lock", os.time() - 60, os.time() - 60))
        assert.is_false(state.set_enabled("lsp", "pyright", false))
      end, debug.traceback)
      test.write_file(release, "release")
      local result = child:wait(20000)
      assert(ok, err)
      assert.equals(0, result.code, result.stderr)
      local state = require("hangar.state")
      assert.is_true(state.set_enabled("lsp", "pyright", false))
      local saved = state.load()
      assert.is_false(saved.lsp.lua_ls)
      assert.is_false(saved.lsp.pyright)
      assert.is_nil(vim.uv.fs_stat(path .. ".lock"))
    end
  )
end)
