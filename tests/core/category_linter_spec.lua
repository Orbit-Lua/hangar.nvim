describe("hangar.category.linter", function()
  local test = require("tests.helpers")
  local linter
  local state
  local tools = require("tests.fixtures.registry")
  local prior = {}

  before_each(function()
    require("tests.helpers").configure()
    prior = {
      state_path = vim.g.hangar_state_path,
      state = package.loaded["hangar.state"],
      category = package.loaded["hangar.category.linter"],
      lint = package.loaded.lint,
    }
    vim.g.hangar_state_path = test.temp_dir("tool-category-linter")
      .. "/tools.json"
    package.loaded["hangar.category.linter"] = nil
    package.loaded["hangar.state"] = nil

    package.loaded.lint = {
      linters_by_ft = { lua = { "luacheck" } },
      linters = { luacheck = { cmd = vim.v.progpath } },
    }
    state = require("hangar.state")
    state.set_enabled("linter", "luacheck", true)
    state.set_enabled("linter", "eslint_d", true)
    linter = require("hangar.category.linter")
  end)

  after_each(function()
    state.set_enabled("linter", "luacheck", true)
    state.set_enabled("linter", "eslint_d", true)
    vim.g.hangar_state_path = prior.state_path
    package.loaded["hangar.state"] = prior.state
    package.loaded["hangar.category.linter"] = prior.category
    package.loaded.lint = prior.lint
    test.cleanup_all()
  end)

  it(
    "reports fully configured linters as ok when there are no diagnostics",
    function()
      local status, hl = linter.entry_status({
        name = "luacheck",
        meta = tools.linter.luacheck,
        installed = true,
      })

      assert.equals("ok", status)
      assert.equals("DiagnosticOk", hl)
    end
  )

  it("reports configured linters with a missing executable", function()
    package.loaded.lint.linters.luacheck.cmd = "__hangar_missing_linter_bin__"

    local status, hl = linter.entry_status({
      name = "luacheck",
      meta = tools.linter.luacheck,
      installed = true,
    })

    assert.equals("no binary", status)
    assert.equals("DiagnosticError", hl)
  end)

  it("reports a missing executable from a factory linter", function()
    package.loaded.lint.linters.luacheck = function()
      return { cmd = "__hangar_missing_linter_bin__" }
    end

    local status = linter.entry_status({
      name = "luacheck",
      meta = tools.linter.luacheck,
      installed = true,
    })

    assert.equals("no binary", status)
  end)

  it("reports linters missing from runtime filetype config", function()
    local status, hl = linter.entry_status({
      name = "eslint_d",
      meta = tools.linter.eslint_d,
      installed = true,
    })

    assert.equals("not configured", status)
    assert.equals("DiagnosticWarn", hl)
  end)

  it("reports partial runtime wiring across declared filetypes", function()
    package.loaded.lint.linters_by_ft.typescript = { "eslint_d" }

    local status, hl = linter.entry_status({
      name = "eslint_d",
      meta = tools.linter.eslint_d,
      installed = true,
    })

    assert.is_true(vim.tbl_contains(tools.linter.eslint_d.ft, "jsx"))
    assert.equals(
      string.format("partly configured 1/%d", #tools.linter.eslint_d.ft),
      status
    )
    assert.equals("DiagnosticWarn", hl)
  end)
end)
