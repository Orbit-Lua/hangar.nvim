describe("hangar.state", function()
  local test = require("tests.helpers")
  local state
  local state_path
  local original_state_path
  local original_rename
  local original_state_module

  local function reload()
    package.loaded["hangar.state"] = nil
    state = require("hangar.state")
  end

  before_each(function()
    original_rename = vim.uv.fs_rename
    original_state_path = vim.g.hangar_state_path
    original_state_module = package.loaded["hangar.state"]
    state_path = test.temp_dir("tool-state") .. "/tools.json"
    vim.g.hangar_state_path = state_path
    reload()
  end)

  after_each(function()
    vim.uv.fs_rename = original_rename
    vim.g.hangar_state_path = original_state_path
    package.loaded["hangar.state"] = original_state_module
    test.cleanup_all()
  end)

  -- Registered after the spec's own hook, so setup follows any module reset.
  before_each(function()
    require("tests.helpers").configure()
  end)

  it(
    "falls back to legacy service state when the current file is absent",
    function()
      local legacy_path = test.temp_dir("legacy-state") .. "/service.json"
      test.write_file(
        legacy_path,
        vim.json.encode({ lsp = { lua_ls = false } })
      )

      local loaded = state.load({
        path = state_path .. ".missing",
        legacy_path = legacy_path,
      })

      assert.is_false(loaded.lsp.lua_ls)
      assert.is_true(loaded.lsp.pyright)
    end
  )

  it("falls back safely for malformed persisted state", function()
    for index, content in ipairs({ "{broken", "null", "[]" }) do
      local path = test.temp_dir("invalid-state-" .. index) .. "/tools.json"
      test.write_file(path, content)
      assert.same(
        state.load({ path = state_path .. ".missing" }),
        state.load({
          path = path,
          legacy_path = path .. ".missing",
        })
      )
    end
  end)

  it("accepts only known tools, booleans, and valid order lists", function()
    test.write_file(
      state_path,
      vim.json.encode({
        lsp = {
          lua_ls = false,
          pyright = "disabled",
          removed_server = false,
        },
        formatter_order = {
          python = { "ruff_format", "removed_formatter" },
          lua = { [1] = "stylua", named = "invalid" },
          invalid = "stylua",
        },
        removed_category = { anything = false },
      })
    )

    local loaded = state.load()
    assert.is_false(loaded.lsp.lua_ls)
    assert.is_true(loaded.lsp.pyright)
    assert.is_nil(loaded.lsp.removed_server)
    assert.same({ "ruff_format" }, loaded.formatter_order.python)
    assert.is_nil(loaded.formatter_order.lua)
    assert.is_nil(loaded.formatter_order.invalid)
    assert.is_nil(loaded.removed_category)
  end)

  it("memoizes state and enables unknown tools by default", function()
    assert.equals(state.get(), state.get())
    assert.is_true(state.is_enabled("lsp", "removed_server"))
    assert.is_true(state.is_enabled("removed_category", "anything"))
  end)

  it(
    "merges independent cached writers without losing another instance's choice",
    function()
      local first = state
      first.get()
      reload()
      state.get()
      assert.is_true(first.set_enabled("formatter", "yaml", false))
      assert.is_true(state.set_enabled("formatter", "prisma_fmt", false))
      local persisted = state.load()
      assert.is_false(persisted.formatter.yaml)
      assert.is_false(persisted.formatter.prisma_fmt)
      assert.is_false(state.is_enabled("formatter", "yaml"))
    end
  )

  it(
    "refuses a concurrent writer without changing cached or persisted choices",
    function()
      assert.is_true(state.set_enabled("lsp", "lua_ls", false))
      local before = table.concat(vim.fn.readfile(state_path), "\n")
      test.write_file(state_path .. ".lock", "another writer")
      local ok, err = state.set_enabled("lsp", "lua_ls", true)
      assert.is_false(ok)
      assert.is_truthy(err)
      assert.is_false(state.is_enabled("lsp", "lua_ls"))
      assert.equals(before, table.concat(vim.fn.readfile(state_path), "\n"))
    end
  )

  it("replaces a lock left by a writer that exited mid-write", function()
    local lock_path = state_path .. ".lock"
    test.write_file(
      lock_path,
      vim.json.encode({ pid = 2147483647, token = "dead-fixture" })
    )
    local abandoned = os.time() - 60
    assert(vim.uv.fs_utime(lock_path, abandoned, abandoned))

    assert.is_true(state.set_enabled("lsp", "lua_ls", false))
    assert.is_false(state.load().lsp.lua_ls)
    assert.is_nil(vim.uv.fs_stat(lock_path))
  end)

  it("does not reclaim an old lock from a live writer", function()
    local path = state_path .. ".lock"
    test.write_file(
      path,
      vim.json.encode({ pid = vim.uv.os_getpid(), token = "live" })
    )
    assert(vim.uv.fs_utime(path, os.time() - 60, os.time() - 60))
    assert.is_false(state.set_enabled("lsp", "lua_ls", false))
    assert.equals(
      "live",
      vim.json.decode(table.concat(vim.fn.readfile(path))).token
    )
  end)

  it("reports committed intent when lock cleanup fails", function()
    local unlink = vim.uv.fs_unlink
    vim.uv.fs_unlink = function(path)
      if path == state_path .. ".lock" then
        return nil, "cleanup refused"
      end
      return unlink(path)
    end
    local ok, err, committed = state.set_enabled("lsp", "lua_ls", false)
    vim.uv.fs_unlink = unlink
    assert.is_false(ok)
    assert.is_truthy(err)
    assert.is_true(committed)
    assert.is_false(state.load().lsp.lua_ls)
  end)

  it(
    "persists enablement and ordering changes through the public interface",
    function()
      state.set_enabled("lsp", "lua_ls", false)
      state.set_order("formatter", "lua", { "stylua" })

      reload()
      assert.is_false(state.is_enabled("lsp", "lua_ls"))
      assert.same({ "stylua" }, state.get_order("formatter", "lua"))

      local persisted =
        vim.json.decode(table.concat(vim.fn.readfile(state_path)))
      assert.is_false(persisted.lsp.lua_ls)
      assert.same({ "stylua" }, persisted.formatter_order.lua)
    end
  )

  it("rolls back memory when an atomic state replacement fails", function()
    local destination = test.temp_dir("state-destination")
    vim.g.hangar_state_path = destination
    local before = state.is_enabled("lsp", "lua_ls")

    local saved, err = state.set_enabled("lsp", "lua_ls", not before)

    assert.is_false(saved)
    assert.is_truthy(err)
    assert.equals(before, state.is_enabled("lsp", "lua_ls"))
  end)
  it(
    "preserves existing JSON and cached values when replacement is refused",
    function()
      assert.is_true(state.set_enabled("lsp", "lua_ls", false))
      local before = table.concat(vim.fn.readfile(state_path), "\n")
      vim.uv.fs_rename = function()
        return nil, "replacement refused"
      end
      local saved = state.set_enabled("lsp", "lua_ls", true)
      assert.is_false(saved)
      assert.is_false(state.is_enabled("lsp", "lua_ls"))
      assert.equals(before, table.concat(vim.fn.readfile(state_path), "\n"))
      assert.same({}, vim.fn.glob(state_path .. ".hangar-*", false, true))
    end
  )
end)
