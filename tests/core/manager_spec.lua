describe("hangar.manager", function()
  local test = require("tests.helpers")
  local manager
  local state
  local categories
  local mason
  local policy
  local prior_manager
  local prior_state
  local prior_order
  local prior_category
  local prior_formatter_category
  local prior_state_path
  local prior_conform
  local prior_package_status
  local prior_install
  local prior_policy
  local original_lsp_apply
  local original_formatter_apply

  before_each(function()
    prior_manager = package.loaded["hangar.manager"]
    prior_state = package.loaded["hangar.state"]
    prior_order = package.loaded["hangar.order"]
    prior_category = package.loaded["hangar.category"]
    prior_formatter_category = package.loaded["hangar.category.formatter"]
    prior_state_path = vim.g.hangar_state_path
    prior_conform = package.loaded.conform
    test.configure()
    package.loaded["hangar.state"] = nil
    package.loaded["hangar.manager"] = nil
    package.loaded["hangar.order"] = nil
    package.loaded["hangar.category"] = nil
    package.loaded["hangar.category.formatter"] = nil
    vim.g.hangar_state_path = test.temp_dir("tool-manager") .. "/tools.json"
    state = require("hangar.state")
    categories = require("hangar.category")
    mason = require("hangar.mason")
    prior_package_status = mason.package_status
    prior_install = mason.install
    policy = require("hangar.config").get().ui
    prior_policy = policy.missing_package_policy
    original_lsp_apply = categories.lsp.apply_runtime
    original_formatter_apply = categories.formatter.apply_runtime
    manager = require("hangar.manager")
  end)

  after_each(function()
    categories.lsp.apply_runtime = original_lsp_apply
    categories.formatter.apply_runtime = original_formatter_apply
    mason.package_status = prior_package_status
    mason.install = prior_install
    policy.missing_package_policy = prior_policy
    package.loaded.conform = prior_conform
    vim.g.hangar_state_path = prior_state_path
    package.loaded["hangar.state"] = prior_state
    package.loaded["hangar.manager"] = prior_manager
    package.loaded["hangar.order"] = prior_order
    package.loaded["hangar.category"] = prior_category
    package.loaded["hangar.category.formatter"] = prior_formatter_category
    test.cleanup_all()
  end)

  it("returns detached snapshots filtered by the requested source", function()
    local snapshot = manager.snapshot({
      category = "lsp",
      scope = "buffer",
      source = { filetype = "python", name = "sample.py" },
    })
    local names = {}
    for _, item in ipairs(snapshot.tools) do
      names[item.name] = true
      assert.is_not_nil(item.status)
      assert.is_not_nil(item.status_hl)
      assert.is_true(item.enabled)
    end
    assert.is_true(names.pyright)
    assert.is_true(names.ruff)
    assert.is_nil(names.lua_ls)
    snapshot.tools[1].meta.ft[1] = "changed"
    assert.is_not_equal(
      "changed",
      require("tests.fixtures.registry").lsp.pyright.ft[1]
    )
    assert.is_nil(manager.snapshot({ category = "formatter_defaults" }))
    assert.same(
      {},
      manager.snapshot({
        category = "lsp",
        scope = "buffer",
        source = { filetype = "" },
      }).groups
    )
  end)

  it(
    "persists a toggle and calls back even when no manager window exists",
    function()
      local applied
      categories.lsp.apply_runtime = function(opts)
        applied = opts.is_enabled
      end
      local calls = 0
      local success
      assert.is_true(
        manager.toggle({ category = "lsp", name = "lua_ls" }, function(ok)
          calls = calls + 1
          success = ok
        end)
      )
      assert.equals(1, calls)
      assert.is_true(success)
      assert.is_false(state.is_enabled("lsp", "lua_ls"))
      assert.is_false(applied)
    end
  )

  it("does not apply a toggle when state persistence fails", function()
    state.set_enabled("formatter", "prisma_fmt", false)
    local blocking_file = test.temp_dir("manager-state-destination") .. "/file"
    test.write_file(blocking_file, "not a directory")
    vim.g.hangar_state_path = blocking_file .. "/tools.json"
    local applied = false
    categories.formatter.apply_runtime = function()
      applied = true
    end
    local result

    assert.is_false(
      manager.toggle(
        { category = "formatter", name = "prisma_fmt" },
        function(ok, err)
          result = { ok, err }
        end
      )
    )

    assert.is_false(result[1])
    assert.is_truthy(result[2])
    assert.is_false(applied)
    assert.is_false(state.is_enabled("formatter", "prisma_fmt"))
  end)

  it(
    "keeps the newest toggle when an older installation finishes later",
    function()
      state.set_enabled("lsp", "lua_ls", false)
      policy.missing_package_policy = "auto"
      mason.package_status = function()
        return false
      end
      local install_callback
      mason.install = function(_, callback)
        install_callback = callback
        return true
      end
      local applied, first, second = {}, 0, 0
      categories.lsp.apply_runtime = function(opts)
        table.insert(applied, opts.is_enabled)
      end
      assert.is_true(
        manager.toggle({ category = "lsp", name = "lua_ls" }, function(ok)
          first = first + 1
          assert.is_false(ok)
        end)
      )
      assert.is_true(
        manager.toggle({ category = "lsp", name = "lua_ls" }, function(ok)
          second = second + 1
          assert.is_true(ok)
        end)
      )
      install_callback(true)
      install_callback(true)
      assert.same({ false }, applied)
      assert.is_false(state.load().lsp.lua_ls)
      assert.equals(1, first)
      assert.equals(1, second)
    end
  )

  it(
    "installs missing Mason packages before enabling and enables only on success",
    function()
      state.set_enabled("lsp", "lua_ls", false)
      policy.missing_package_policy = "auto"
      local package_callback
      local applied
      categories.lsp.apply_runtime = function(opts)
        applied = opts.is_enabled
      end
      mason.package_status = function()
        return false
      end
      mason.install = function(_, callback)
        package_callback = callback
        return true
      end

      local completed
      assert.is_true(
        manager.toggle({ category = "lsp", name = "lua_ls" }, function(ok, err)
          completed = { ok, err }
        end)
      )
      assert.is_nil(completed)
      assert.is_false(state.is_enabled("lsp", "lua_ls"))
      package_callback(false, "download failed")
      assert.same({ false, "download failed" }, completed)
      assert.is_false(state.is_enabled("lsp", "lua_ls"))
      assert.is_nil(applied)

      assert.is_true(
        manager.toggle({ category = "lsp", name = "lua_ls" }, function(ok)
          completed = { ok }
        end)
      )
      package_callback(true)
      assert.same({ true }, completed)
      assert.is_true(state.is_enabled("lsp", "lua_ls"))
      assert.is_true(applied)
    end
  )

  it(
    "honors manual policy and rejects unavailable registries without enabling",
    function()
      state.set_enabled("lsp", "lua_ls", false)
      local apply_count = 0
      categories.lsp.apply_runtime = function()
        apply_count = apply_count + 1
      end
      mason.package_status = function()
        return false
      end
      local install_count = 0
      mason.install = function()
        install_count = install_count + 1
        return true
      end
      -- The caller owns the ui table; hangar reads the policy per operation.
      policy.missing_package_policy = "manual"
      local manual
      assert.is_false(
        manager.toggle({ category = "lsp", name = "lua_ls" }, function(ok, err)
          manual = { ok, err }
        end)
      )
      assert.is_false(manual[1])
      assert.is_truthy(manual[2])
      assert.is_false(state.is_enabled("lsp", "lua_ls"))
      assert.equals(0, install_count)

      policy.missing_package_policy = "auto"
      mason.package_status = function()
        return nil, "mason registry is unavailable"
      end
      local unavailable
      assert.is_false(
        manager.toggle({ category = "lsp", name = "lua_ls" }, function(ok)
          unavailable = ok
        end)
      )
      assert.is_false(unavailable)
      assert.is_false(state.is_enabled("lsp", "lua_ls"))
      assert.equals(0, install_count)
      assert.equals(0, apply_count)
    end
  )

  it("toggles external tools without consulting Mason", function()
    local applied
    categories.formatter.apply_runtime = function(opts)
      applied = opts.is_enabled
    end
    mason.package_status = function()
      error("external tools have no Mason package")
    end
    state.set_enabled("formatter", "prisma_fmt", false)

    assert.is_true(
      manager.toggle({ category = "formatter", name = "prisma_fmt" })
    )
    assert.is_true(state.is_enabled("formatter", "prisma_fmt"))
    assert.is_true(applied)
  end)

  it(
    "reports runtime failures while retaining saved intent and clears them after success",
    function()
      categories.formatter.apply_runtime = function()
        error("backend refused the change")
      end
      local result
      local accepted = manager.toggle(
        { category = "formatter", name = "prisma_fmt" },
        function(ok, err)
          result = { ok, err }
        end
      )
      assert.is_false(accepted)
      assert.is_false(result[1])
      assert.is_truthy(result[2]:find("backend refused", 1, true))
      assert.is_false(state.is_enabled("formatter", "prisma_fmt"))
      local snapshot = manager.snapshot({
        category = "formatter",
        source = { filetype = "prisma" },
      })
      assert.is_true(snapshot.tools[1].health_status.attention)
      assert.is_truthy(
        snapshot.tools[1].health_status.reason:find("backend refused", 1, true)
      )
      categories.formatter.apply_runtime = function()
        return true
      end
      assert.is_true(
        manager.toggle({ category = "formatter", name = "prisma_fmt" })
      )
      snapshot = manager.snapshot({
        category = "formatter",
        source = { filetype = "prisma" },
      })
      assert.is_nil(snapshot.tools[1].health_status.reason)
    end
  )

  it(
    "rejects category capabilities without mutating persisted or runtime state",
    function()
      local called, succeeded
      assert.is_false(
        manager.toggle({ category = "parser", name = "lua" }, function(ok)
          called = true
          succeeded = ok
        end)
      )
      assert.is_true(called)
      assert.is_false(succeeded)
      assert.is_true(state.is_enabled("parser", "lua"))
    end
  )

  it(
    "reorders the full saved list but applies enabled tools and unknown runtime entries",
    function()
      local conform = {
        formatters_by_ft = {
          python = {
            "ruff_fix",
            "ruff_organize_imports",
            "ruff_format",
            "external_fmt",
          },
        },
      }
      package.loaded.conform = conform
      state.set_enabled("formatter", "ruff_organize_imports", false)

      assert.is_true(manager.reorder({
        category = "formatter",
        filetype = "python",
        name = "ruff_format",
        direction = -1,
      }))
      assert.same(
        { "ruff_fix", "ruff_format", "ruff_organize_imports" },
        state.get_order("formatter", "python")
      )
      assert.same(
        { "ruff_fix", "ruff_format", "external_fmt" },
        conform.formatters_by_ft.python
      )
    end
  )

  it("rejects invalid filetypes and boundary moves", function()
    assert.is_false(manager.reorder({
      category = "formatter",
      filetype = "javascript",
      name = "ruff_fix",
      direction = 1,
    }))
    assert.is_false(manager.reorder({
      category = "formatter",
      filetype = "python",
      name = "ruff_fix",
      direction = -1,
    }))
    assert.same(
      require("tests.fixtures.registry").formatter_defaults.python,
      state.get_order("formatter", "python")
    )
  end)
  it(
    "reorders configured formatters without activating other supported tools",
    function()
      package.loaded.conform = {
        formatters_by_ft = {
          markdown = { "markdownlint-cli2", "markdown-toc", "external_fmt" },
        },
      }
      assert.is_true(manager.reorder({
        category = "formatter",
        filetype = "markdown",
        name = "markdown-toc",
        direction = -1,
      }))
      assert.same(
        { "markdown-toc", "markdownlint-cli2", "external_fmt" },
        package.loaded.conform.formatters_by_ft.markdown
      )
      assert.same(
        { "markdown-toc", "markdownlint-cli2", "deno_fmt" },
        state.get_order("formatter", "markdown")
      )
    end
  )

  it(
    "reports an unavailable backend while retaining the saved choice",
    function()
      package.loaded.conform = nil
      package.preload.conform = function()
        error("formatter backend unavailable")
      end
      assert.is_true(state.set_enabled("formatter", "prisma_fmt", false))
      local result
      assert.is_false(
        manager.toggle(
          { category = "formatter", name = "prisma_fmt" },
          function(ok, err)
            result = { ok, err }
          end
        )
      )
      assert.is_false(result[1])
      assert.is_truthy(result[2]:find("unavailable", 1, true))
      assert.is_true(state.is_enabled("formatter", "prisma_fmt"))
    end
  )

  it("checks formatter availability in the captured source buffer", function()
    local source = vim.api.nvim_create_buf(true, false)
    vim.bo[source].filetype = "prisma"
    vim.api.nvim_buf_set_name(
      source,
      test.temp_dir("formatter-source") .. "/schema.prisma"
    )
    local popup = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(popup)
    local inspected
    package.loaded.conform = {
      formatters_by_ft = { prisma = { "prisma_fmt" } },
      get_formatter_info = function(_, buffer)
        inspected =
          { requested = buffer, current = vim.api.nvim_get_current_buf() }
        return { available = true }
      end,
    }
    local snapshot = manager.snapshot({
      category = "formatter",
      source = { bufnr = source, filetype = "prisma" },
    })
    assert.same({ requested = source, current = source }, inspected)
    assert.equals("Configured", snapshot.tools[1].health_status.runtime)
    assert.equals(popup, vim.api.nvim_get_current_buf())
  end)
  it(
    "installs a dependency by logical identity without changing toggle state",
    function()
      local selected, result
      local before = vim.deepcopy(state.get())
      mason.install = function(name, callback)
        selected = name
        callback(false, "installer offline")
        return true
      end
      assert.is_true(
        manager.install(
          { category = "package", name = "typescript-language-server" },
          function(ok, err)
            result = { ok, err }
          end
        )
      )
      assert.equals("typescript-language-server", selected)
      assert.same({ false, "installer offline" }, result)
      assert.is_false(manager.toggle({ category = "package", name = selected }))
      assert.same(before, state.get())
      assert.equals(0, vim.fn.filereadable(vim.g.hangar_state_path))
    end
  )
end)
