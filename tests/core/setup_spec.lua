describe("Hangar setup", function()
  local test = require("tests.helpers")

  ---Fresh Hangar modules, so the configuration starts empty.
  local function reset_modules()
    for name in pairs(package.loaded) do
      if name == "hangar" or name:match("^hangar%.") then
        package.loaded[name] = nil
      end
    end
  end

  local function read_json(path)
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end

  ---Options with a fixture registry that shares no tool with the test registry.
  local function fixture(root, overrides)
    local runtime = { enabled = {}, calls = {}, result = true }
    runtime.module = {
      apply_adapter = function(_, name, enabled, options)
        table.insert(runtime.calls, { name, enabled, options })
        if runtime.result ~= true then
          return false, runtime.result
        end
        runtime.enabled[name] = enabled
        return true
      end,
      adapter_status = function(_, name)
        return runtime.enabled[name] == false and "disabled" or "registered",
          "DiagnosticOk"
      end,
    }
    local options = {
      registry = {
        lsp = {},
        dap = {
          fixture_dbg = { mason = "fixture-dbg-pkg", ft = { "fixturelang" } },
        },
        linter = {},
        formatter = { fixture_fmt = { ft = { "fixturelang", "otherlang" } } },
        parser = { fixture_parser = {} },
        package = { ["fixture-pkg"] = {} },
        formatter_defaults = {},
        linter_defaults = {},
      },
      defaults = function()
        return { formatter = {}, linter = {} }
      end,
      state_path = function()
        return root .. "/tools.json"
      end,
      legacy_state_path = function()
        return nil
      end,
      border = "single",
      adapters = {
        dap = {
          runtime = function()
            return runtime.module
          end,
          options = function()
            return { fixture = true }
          end,
        },
        activation = {
          formatter = function()
            return { fixturelang = { "fixture_fmt" } }
          end,
          linter = function()
            return {}
          end,
        },
      },
    }
    return vim.tbl_extend("force", options, overrides or {}), runtime
  end

  ---A Mason registry whose installs finish only when the test closes them.
  local function fake_mason()
    local handles = {}
    local packages = {}
    package.loaded["mason-registry"] = {
      get_package = function(name)
        packages[name] = packages[name]
          or {
            installed = false,
            is_installed = function(self)
              return self.installed
            end,
            is_installing = function()
              return false
            end,
            install = function(self)
              local handle = {}
              function handle.once(_, _, callback)
                handles[name] = function(success)
                  self.installed = success
                  callback()
                end
              end
              return handle
            end,
          }
        return packages[name]
      end,
    }
    return handles
  end

  ---An nvim-treesitter whose install task calls back when the test asks.
  local function fake_treesitter(await)
    local task = {}
    package.loaded["nvim-treesitter"] = {
      get_installed = function()
        return {}
      end,
      install = function()
        return {
          await = function(_, callback)
            if await then
              await()
            end
            task.finish = callback
          end,
        }
      end,
    }
    return task
  end

  local function body_lines()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_loaded(buffer)
        and vim.bo[buffer].filetype == "Hangar"
      then
        return table.concat(
          vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
          "\n"
        ),
          buffer
      end
    end
  end

  local function press(buffer, key)
    local mapping = vim.api.nvim_buf_call(buffer, function()
      return vim.fn.maparg(key, "n", false, true)
    end)
    mapping.callback()
  end

  local function setup(options)
    require("hangar").setup(options)
  end

  before_each(function()
    vim.opt.runtimepath:append(test.plugin_path("nui.nvim"))
    reset_modules()
    package.loaded.dap = { adapters = {}, configurations = {} }
    package.loaded.conform = { formatters_by_ft = {} }
    vim.notify = function() end
  end)

  it(
    "rejects use before setup with an error that names hangar.setup",
    function()
      local ok, err = pcall(function()
        return require("hangar.state").get()
      end)
      assert.is_false(ok)
      assert.truthy(tostring(err):find("hangar.setup", 1, true))
    end
  )

  it("runs views, state and adapters from injected options only", function()
    local root = test.temp_dir("tool-setup-injected")
    local options, runtime = fixture(root)
    setup(options)
    local manager = require("hangar.manager")

    local snapshot = manager.snapshot({ category = "dap", scope = "states" })
    assert.same(
      { "fixture_dbg" },
      vim.tbl_map(function(tool)
        return tool.name
      end, snapshot.tools)
    )

    local source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(source)
    vim.bo[source].filetype = "fixturelang"
    require("hangar").open()
    local _, body = body_lines()
    press(body, "2")
    local lines = body_lines()
    assert.truthy(lines:find("fixture_dbg", 1, true))
    assert.is_nil(lines:find("coreclr", 1, true))
    require("hangar").close()

    local results = {}
    local function record(success, err)
      table.insert(results, { success, err })
    end
    assert.is_true(
      manager.toggle({ category = "dap", name = "fixture_dbg" }, record)
    )
    assert.same({ "fixture_dbg", false, { fixture = true } }, runtime.calls[1])
    assert.is_false(runtime.enabled.fixture_dbg)

    -- Activation comes from the injected provider, not the backend list.
    manager.toggle({ category = "formatter", name = "fixture_fmt" }, record)
    manager.toggle({ category = "formatter", name = "fixture_fmt" }, record)
    assert.same(
      { fixturelang = { "fixture_fmt" } },
      package.loaded.conform.formatters_by_ft
    )

    local saved = read_json(root .. "/tools.json")
    assert.same({ fixture_dbg = false }, saved.dap)
    assert.same({ fixture_fmt = true }, saved.formatter)
    assert.same({}, saved.lsp)

    -- A failing owner reports the error and keeps the saved intent.
    fake_mason()
    package.loaded["mason-registry"].get_package("fixture-dbg-pkg").installed =
      true
    runtime.result = "adapter boom"
    assert.is_false(
      manager.toggle({ category = "dap", name = "fixture_dbg" }, record)
    )
    assert.is_false(results[#results][1])
    assert.truthy(results[#results][2]:find("adapter boom", 1, true))
    assert.same({ fixture_dbg = true }, read_json(root .. "/tools.json").dap)
  end)

  it(
    "replaces options, failures, cached state and the open view on a repeated setup",
    function()
      local first = test.temp_dir("tool-setup-first")
      local second = test.temp_dir("tool-setup-second")
      local options, runtime = fixture(first)
      setup(options)
      runtime.result = "adapter boom"
      local manager = require("hangar.manager")
      manager.toggle({ category = "dap", name = "fixture_dbg" })
      local before = manager.snapshot({ category = "dap", scope = "states" })
      assert.equals("Apply failed", before.tools[1].status)
      require("hangar").open()
      assert.is_not_nil(body_lines())

      local replacement = fixture(second)
      replacement.registry.dap = { other_dbg = { ft = { "fixturelang" } } }
      setup(replacement)
      assert.is_nil(body_lines())
      local after = manager.snapshot({ category = "dap", scope = "states" })
      assert.same({ "other_dbg" }, { after.tools[1].name })
      assert.are_not.equals("Apply failed", after.tools[1].status)
      manager.toggle({ category = "dap", name = "other_dbg" })
      assert.same({ other_dbg = false }, read_json(second .. "/tools.json").dap)
    end
  )

  it("rejects replacement while a toggle or an installation runs", function()
    local root = test.temp_dir("tool-setup-busy")
    local other = test.temp_dir("tool-setup-busy-other")
    local handles = fake_mason()
    local task = fake_treesitter()
    local options = fixture(root)
    setup(options)
    local manager = require("hangar.manager")
    local config = require("hangar.config")
    local function rejected()
      local ok, err = pcall(setup, (fixture(other)))
      return not ok
        and tostring(err):find("in flight", 1, true) ~= nil
        and config.get().registry == options.registry
    end

    -- A pending toggle waits for its Mason install, then writes the old path.
    manager.toggle({ category = "dap", name = "fixture_dbg" })
    manager.toggle({ category = "dap", name = "fixture_dbg" })
    assert.is_true(rejected())
    handles["fixture-dbg-pkg"](true)
    assert.is_true(vim.wait(1000, function()
      return not manager.busy()
    end, 10))
    assert.same({ fixture_dbg = true }, read_json(root .. "/tools.json").dap)
    assert.equals(0, vim.fn.filereadable(other .. "/tools.json"))

    -- A superseded toggle leaves its install running.
    manager.toggle({ category = "dap", name = "fixture_dbg" })
    package.loaded["mason-registry"].get_package("fixture-dbg-pkg").installed =
      false
    manager.toggle({ category = "dap", name = "fixture_dbg" })
    manager.toggle({ category = "dap", name = "fixture_dbg" })
    assert.is_true(rejected())
    handles["fixture-dbg-pkg"](true)
    assert.is_true(vim.wait(1000, function()
      return not manager.busy()
    end, 10))

    -- A manual Mason install.
    manager.install({ category = "package", name = "fixture-pkg" })
    assert.is_true(rejected())
    handles["fixture-pkg"](true)
    assert.is_true(vim.wait(1000, function()
      return not manager.busy()
    end, 10))

    -- A category install such as a parser build.
    manager.install({ category = "parser", name = "fixture_parser" })
    assert.is_true(rejected())
    task.finish(nil, true)
    assert.is_true(vim.wait(1000, function()
      return not manager.busy()
    end, 10))
    setup(fixture(other))
    assert.are_not.equals(options.registry, config.get().registry)
  end)

  it(
    "releases an install that throws before it registers its callback",
    function()
      local root = test.temp_dir("tool-setup-throw")
      fake_treesitter(function()
        error("await failed")
      end)
      setup((fixture(root)))
      local manager = require("hangar.manager")
      local result
      assert.is_false(
        manager.install(
          { category = "parser", name = "fixture_parser" },
          function(success, err)
            result = { success, err }
          end
        )
      )
      assert.is_false(result[1])
      assert.truthy(result[2]:find("await failed", 1, true))
      assert.is_false(manager.busy())
      setup((fixture(test.temp_dir("tool-setup-throw-next"))))
    end
  )
end)
