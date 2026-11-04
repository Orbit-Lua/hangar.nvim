describe("hangar conform and lint integrations", function()
  local test = require("tests.helpers")
  local hangar
  local conform, lint
  local formatted, linted

  ---A conform module whose setup merges lists into a new table, as conform's
  ---own `setup` does.
  local function conform_module()
    local module = { formatters_by_ft = {} }
    function module.setup(opts)
      module.formatters_by_ft = vim.tbl_extend(
        "force",
        module.formatters_by_ft,
        opts.formatters_by_ft or {}
      )
    end
    function module.format()
      formatted = vim.deepcopy(module.formatters_by_ft.lua)
    end
    return module
  end

  ---@param opts? Hangar.Options
  local function configure(opts)
    local path = test.temp_dir("lists-state") .. "/tools.json"
    test.write_file(
      path,
      vim.json.encode({ formatter = { b = false }, linter = { l1 = false } })
    )
    hangar = require("hangar")
    hangar.setup(vim.tbl_extend("force", {
      registry = {
        formatter = { a = { ft = { "lua" } }, b = { ft = { "lua" } } },
        linter = { l1 = { ft = { "lua" } }, l2 = { ft = { "lua" } } },
      },
      state_path = function()
        return path
      end,
    }, opts or {}))
    require("hangar.state").reset()
  end

  local function toggle(category, name)
    local result
    require("hangar.manager").toggle(
      { category = category, name = name },
      function(ok, err)
        result = { ok, err }
      end
    )
    return result
  end

  before_each(function()
    formatted, linted = nil, nil
    package.preload.conform = conform_module
    package.preload.lint = function()
      local module = { linters_by_ft = {} }
      function module.try_lint()
        linted = vim.deepcopy(module.linters_by_ft.lua)
      end
      return module
    end
  end)

  after_each(function()
    package.preload.conform, package.preload.lint = nil, nil
    package.loaded.conform, package.loaded.lint = nil, nil
    test.cleanup_all()
  end)

  it("filters each table that conform.setup builds", function()
    configure()
    conform = require("conform")
    conform.setup({ formatters_by_ft = { lua = { "a", "b" } } })
    assert.same({ "a" }, conform.formatters_by_ft.lua)

    assert.same({ true }, toggle("formatter", "b"))
    assert.same({ "a", "b" }, conform.formatters_by_ft.lua)
    assert.same({ true }, toggle("formatter", "b"))

    -- A later setup copies the filtered lua list into a new table; hangar
    -- still restores what that list held before it was filtered.
    conform.setup({ formatters_by_ft = { python = { "a" } } })
    assert.same({ true }, toggle("formatter", "b"))
    assert.same({ "a", "b" }, conform.formatters_by_ft.lua)
  end)

  it("filters a table assigned after load before conform formats", function()
    configure()
    conform = require("conform")
    conform.formatters_by_ft = { lua = { "b", "a", lsp_format = "fallback" } }
    conform.format()
    assert.same({ "a", lsp_format = "fallback" }, formatted)
  end)

  it("filters nvim-lint lists before try_lint", function()
    configure()
    lint = require("lint")
    lint.linters_by_ft = { lua = { "l1", "l2" } }
    lint.try_lint()
    assert.same({ "l2" }, linted)
    assert.same({ true }, toggle("linter", "l1"))
    assert.same({ "l1", "l2" }, lint.linters_by_ft.lua)
  end)

  it("gates a backend that loaded before setup", function()
    package.loaded.conform = conform_module()
    conform = package.loaded.conform
    conform.formatters_by_ft = { lua = { "a", "b" } }
    configure()
    configure()
    assert.same({ "a" }, conform.formatters_by_ft.lua)
  end)

  it("leaves conform alone when the integration is off", function()
    configure({ integrations = { conform = false } })
    conform = require("conform")
    conform.setup({ formatters_by_ft = { lua = { "a", "b" } } })
    conform.format()
    assert.same({ "a", "b" }, formatted)
    assert.same(
      { lua = { "a" } },
      hangar.filter("formatter", { lua = { "a", "b" } })
    )
  end)

  it("does not filter twice when filter output reaches conform", function()
    configure()
    conform = require("conform")
    conform.setup({
      formatters_by_ft = hangar.filter("formatter", { lua = { "a", "b" } }),
    })
    assert.same({ "a" }, conform.formatters_by_ft.lua)
    assert.same({ true }, toggle("formatter", "b"))
    assert.same({ "a", "b" }, conform.formatters_by_ft.lua)
  end)
end)
