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

  it(
    "rejects formatter changes without injected activation and changes nothing",
    function()
      local conform = {
        formatters_by_ft = { lua = { "fixture_a", "fixture_b" } },
      }
      package.loaded.conform = conform
      require("hangar").setup({
        registry = {
          formatter = {
            fixture_a = { ft = { "lua" } },
            fixture_b = { ft = { "lua" } },
          },
        },
      })
      local manager = require("hangar.manager")
      local path = require("hangar.config").get().state_path()
      local before = read(path)

      local snapshot =
        manager.snapshot({ category = "formatter", scope = "states" })
      assert.equals("Activation not configured", snapshot.tools[1].status)
      for _, operation in ipairs({
        function(done)
          return manager.toggle(
            { category = "formatter", name = "fixture_a" },
            done
          )
        end,
        function(done)
          return manager.reorder({
            category = "formatter",
            name = "fixture_b",
            filetype = "lua",
            direction = -1,
          }, done)
        end,
      }) do
        local result
        assert.is_false(operation(function(success, err)
          result = { success, err }
        end))
        assert.is_false(result[1])
        assert.truthy(result[2]:find("adapters.activation", 1, true))
      end
      assert.equals(before, read(path))
      assert.same(
        { lua = { "fixture_a", "fixture_b" } },
        conform.formatters_by_ft
      )
    end
  )

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
