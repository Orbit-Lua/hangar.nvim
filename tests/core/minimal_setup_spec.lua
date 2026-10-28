describe("hangar with minimal options", function()
  local test = require("tests.helpers")

  local function reset_modules()
    for name in pairs(package.loaded) do
      if name == "hangar" or name:match("^hangar%.") then
        package.loaded[name] = nil
      end
    end
  end

  local function body()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_loaded(buffer)
        and vim.bo[buffer].filetype == "Hangar"
      then
        return buffer
      end
    end
  end

  local function press(key)
    local mapping = vim.api.nvim_buf_call(body(), function()
      return vim.fn.maparg(key, "n", false, true)
    end)
    mapping.callback()
  end

  local function read(path)
    if vim.fn.filereadable(path) == 0 then
      return nil
    end
    return table.concat(vim.fn.readfile(path), "\n")
  end

  before_each(function()
    vim.opt.runtimepath:append(test.plugin_path("nui.nvim"))
    reset_modules()
    vim.notify = function() end
    -- Specs here use the default state path, so each starts without state.
    vim.fn.delete(vim.fn.stdpath("data") .. "/hangar.json")
  end)

  it("browses every category and toggles LSP with only a registry", function()
    local enabled = {}
    local original =
      { enable = vim.lsp.enable, is_enabled = vim.lsp.is_enabled }
    vim.lsp.enable = function(name, value)
      enabled[name] = value ~= false
    end
    vim.lsp.is_enabled = function(name)
      return enabled[name] ~= false
    end
    local ok, err = pcall(function()
      require("hangar").setup({
        registry = { lsp = { fixture_ls = { ft = { "lua" } } } },
      })
      local config = require("hangar.config").get()
      assert.equals(
        vim.fn.stdpath("data") .. "/hangar.json",
        config.state_path()
      )
      assert.equals(2, config.ui.layout.margin)
      assert.is_true(#config.icons.enabled > 0)

      require("hangar").open()
      for index = 1, 6 do
        press(tostring(index))
      end
      require("hangar").close()

      local result
      require("hangar.manager").toggle(
        { category = "lsp", name = "fixture_ls" },
        function(success)
          result = success
        end
      )
      assert.is_true(result)
      assert.is_false(enabled.fixture_ls)
      assert.same(
        { fixture_ls = false },
        vim.json.decode(read(config.state_path())).lsp
      )
    end)
    vim.lsp.enable, vim.lsp.is_enabled = original.enable, original.is_enabled
    assert(ok, err)
  end)

  ---Run a manager operation and return its callback result.
  local function run(operation, selection)
    local result
    require("hangar.manager")[operation](selection, function(success, err)
      result = { success, err }
    end)
    return result
  end

  local function toggle(name)
    return run("toggle", { category = "formatter", name = name })
  end

  local function registry(names)
    local formatter = {}
    for _, name in ipairs(names) do
      formatter[name] = { ft = { "lua" } }
    end
    return { formatter = formatter }
  end

  it(
    "restores registry-only formatters from the captured backend lists",
    function()
      local conform = {
        formatters_by_ft = {
          lua = { "a", "b", stop_after_first = true },
          python = { "external" },
          ["*"] = { "b" },
          json = function()
            return { "a" }
          end,
        },
      }
      package.loaded.conform = conform
      local hangar = require("hangar")
      local options = { registry = registry({ "a", "b", "c" }) }
      options.registry.formatter.a.ft = { "lua", "json" }
      hangar.setup(options)
      local state = require("hangar.state")

      assert.is_true(toggle("a")[1])
      assert.same(
        { "b", stop_after_first = true },
        conform.formatters_by_ft.lua
      )
      assert.is_true(toggle("a")[1])
      -- Without a saved order, the captured order keeps "a" first.
      assert.same(
        { "a", "b", stop_after_first = true },
        conform.formatters_by_ft.lua
      )
      assert.is_true(state.is_enabled("formatter", "a"))
      assert.same({ "external" }, conform.formatters_by_ft.python)
      assert.same({ "b" }, conform.formatters_by_ft["*"])
      assert.equals("function", type(conform.formatters_by_ft.json))

      -- A repeated setup keeps the session list, so "a" is still restorable.
      assert.is_true(toggle("a")[1])
      hangar.setup(options)
      assert.is_true(toggle("a")[1])
      assert.same(
        { "a", "b", stop_after_first = true },
        conform.formatters_by_ft.lua
      )

      -- A name that the live backend gains joins the captured list.
      table.insert(conform.formatters_by_ft.lua, "c")
      assert.is_true(toggle("c")[1])
      assert.is_true(toggle("c")[1])
      assert.same(
        { "a", "b", "c", stop_after_first = true },
        conform.formatters_by_ft.lua
      )

      -- Conform still runs "b" through "*", so status warns.
      assert.is_true(toggle("b")[1])
      local snapshot = require("hangar.manager").snapshot({
        category = "formatter",
        scope = "states",
      })
      local status
      for _, tool in ipairs(snapshot.tools) do
        if tool.name == "b" then
          status = tool.status
        end
      end
      assert.equals('Disabled, still listed under "*"', status)
    end
  )

  it("reorders a registry-only formatter before any other read", function()
    local conform = { formatters_by_ft = { lua = { "b", "a" } } }
    package.loaded.conform = conform
    require("hangar").setup({ registry = registry({ "a", "b" }) })
    local result = run("reorder", {
      category = "formatter",
      name = "a",
      filetype = "lua",
      direction = -1,
    })
    assert.is_true(result[1], result[2])
    assert.same({ "a", "b" }, conform.formatters_by_ft.lua)
  end)

  it("keeps the last injected activation after a setup without it", function()
    local conform = { formatters_by_ft = { lua = { "a", "b" } } }
    package.loaded.conform = conform
    local hangar = require("hangar")
    hangar.setup({
      registry = registry({ "a", "b" }),
      adapters = {
        activation = {
          formatter = function()
            return { lua = { "a", "b" } }
          end,
        },
      },
    })
    assert.is_true(toggle("a")[1])
    hangar.setup({ registry = registry({ "a", "b" }) })
    assert.is_true(toggle("a")[1])
    assert.same({ "a", "b" }, conform.formatters_by_ft.lua)
  end)

  it("prefers injected activation over a filter record", function()
    local conform = { formatters_by_ft = { lua = { "b" } } }
    package.loaded.conform = conform
    local hangar = require("hangar")
    hangar.setup({
      registry = registry({ "a", "b" }),
      adapters = {
        activation = {
          formatter = function()
            return { lua = { "b" } }
          end,
        },
      },
    })
    hangar.filter("formatter", { lua = { "a", "b" } })
    assert.is_true(toggle("a")[1])
    assert.is_true(toggle("a")[1])
    assert.same({ "b" }, conform.formatters_by_ft.lua)
  end)

  it(
    "applies saved intent through filter and restores from its record",
    function()
      local hangar = require("hangar")
      hangar.setup({ registry = registry({ "a", "b", "c" }) })
      local state = require("hangar.state")
      state.set_enabled("formatter", "b", false)
      state.set_order("formatter", "lua", { "c", "a", "b" })
      local by_ft = { lua = { "a", "b", "c", "x", lsp_format = "fallback" } }
      local filtered = hangar.filter("formatter", by_ft)
      assert.same(
        { lua = { "c", "a", "x", lsp_format = "fallback" } },
        filtered
      )
      assert.same({ "a", "b", "c", "x", lsp_format = "fallback" }, by_ft.lua)

      -- The backend can still hold the replaced lists before the caller assigns
      -- the result; the record, not the live list, decides what returns.
      package.loaded.conform = { formatters_by_ft = { lua = { "a", "b" } } }
      hangar.filter("formatter", { lua = { "a" } })
      state.set_enabled("formatter", "b", true)
      assert.is_true(toggle("b")[1])
      assert.is_true(toggle("b")[1])
      assert.same({ "a" }, package.loaded.conform.formatters_by_ft.lua)
      state.set_enabled("formatter", "b", false)

      hangar.filter("formatter", by_ft)
      package.loaded.conform.formatters_by_ft = filtered
      hangar.setup({ registry = registry({ "a", "b", "c" }) })
      assert.is_true(toggle("b")[1])
      assert.same(
        { "c", "a", "b", "x", lsp_format = "fallback" },
        package.loaded.conform.formatters_by_ft.lua
      )
    end
  )

  it("filters linters the same way", function()
    local hangar = require("hangar")
    hangar.setup({
      registry = {
        linter = { l1 = { ft = { "lua" } }, l2 = { ft = { "lua" } } },
      },
    })
    require("hangar.state").set_enabled("linter", "l1", false)
    local filtered = hangar.filter("linter", { lua = { "l1", "l2" } })
    assert.same({ lua = { "l2" } }, filtered)
    package.loaded.lint = { linters_by_ft = filtered, linters = {} }
    assert.is_true(run("toggle", { category = "linter", name = "l1" })[1])
    assert.same({ "l1", "l2" }, package.loaded.lint.linters_by_ft.lua)
  end)

  it("rejects filter misuse", function()
    local ok, err = pcall(require("hangar").filter, "formatter", {})
    assert.is_false(ok)
    assert.truthy(err:find("hangar.setup", 1, true))
    require("hangar").setup({ registry = {} })
    assert.is_false(pcall(require("hangar").filter, "lsp", {}))
  end)

  it("rejects formatter changes without any activation source", function()
    package.loaded.conform = nil
    package.preload.conform = function()
      error("conform is not installed")
    end
    require("hangar").setup({ registry = registry({ "a" }) })
    local path = require("hangar.config").get().state_path()
    local before = read(path)
    local result = toggle("a")
    package.preload.conform = nil
    assert.is_false(result[1])
    assert.truthy(result[2]:find("adapters.activation", 1, true))
    assert.equals(before, read(path))
  end)

  it("keeps a caller's ui table and fills only its missing keys", function()
    local ui = { width = 77, layout = { gap = 5 } }
    require("hangar").setup({ registry = {}, ui = ui })
    local resolved = require("hangar.config").get().ui
    assert.equals(ui, resolved)
    assert.equals(77, ui.width)
    assert.equals(5, ui.layout.gap)
    assert.equals(2, ui.layout.margin)
    assert.equals(40, ui.height)
  end)

  it("reports injected linter logs through status and details", function()
    local entries = {
      { level = "ERROR", message = "boom", tags = { kind = "run" } },
    }
    package.loaded.lint = {
      linters_by_ft = { lua = { "fixture_lint" } },
      linters = { fixture_lint = { cmd = vim.v.progpath } },
    }
    require("hangar").setup({
      registry = { linter = { fixture_lint = { ft = { "lua" } } } },
      adapters = {
        activation = {
          linter = function()
            return { lua = { "fixture_lint" } }
          end,
        },
        linter = {
          logs = function(name)
            return name == "fixture_lint" and entries or {}
          end,
        },
      },
    })
    local manager = require("hangar.manager")

    local snapshot = manager.snapshot({ category = "linter", scope = "states" })
    assert.equals("Failed", snapshot.tools[1].status)
    assert.same(
      entries,
      manager.details({ category = "linter", name = "fixture_lint" }).logs
    )
  end)
end)
