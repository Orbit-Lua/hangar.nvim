describe("hangar.data", function()
  local data = require("hangar.data")
  local tools = require("tests.fixtures.registry")

  local mason = require("hangar.mason")
  local state = require("hangar.state")
  local prior_conform, prior_status, prior_formatter, prior_lint, diagnostic_buffer
  before_each(function()
    require("tests.helpers").configure()
    prior_conform = package.loaded.conform
    prior_lint = package.loaded.lint
    prior_status = mason.package_status
    prior_formatter = vim.deepcopy(state.get().formatter)
  end)

  after_each(function()
    tools.formatter._test_default_a = nil
    tools.formatter._test_default_b = nil
    tools.formatter_defaults._test_default_order = nil
    package.loaded.conform = prior_conform
    package.loaded.lint = prior_lint
    if diagnostic_buffer and vim.api.nvim_buf_is_valid(diagnostic_buffer) then
      vim.api.nvim_buf_delete(diagnostic_buffer, { force = true })
    end
    diagnostic_buffer = nil
    mason.package_status = prior_status
    state.get().formatter = prior_formatter
  end)

  it(
    "builds sorted, complete filetype groups for ordered categories",
    function()
      for _, category in ipairs({ "formatter", "linter" }) do
        local groups = data.build_ft_groups(category)
        local by_ft = {}
        local filetypes = {}

        for _, group in ipairs(groups) do
          assert.is_true(group.ft ~= "")
          assert.is_true(#group.names > 0)
          by_ft[group.ft] = group.names
          table.insert(filetypes, group.ft)
        end

        local sorted = vim.deepcopy(filetypes)
        table.sort(sorted)
        assert.same(sorted, filetypes, category .. " filetypes")

        for name, definition in pairs(tools[category]) do
          for _, ft in ipairs(definition.ft) do
            assert.is_true(
              vim.tbl_contains(by_ft[ft], name),
              category .. "." .. name .. " missing from " .. ft
            )
          end
        end
      end
    end
  )

  it("uses canonical defaults when no saved order exists", function()
    tools.formatter._test_default_a = {
      mason = nil,
      ft = { "_test_default_order" },
    }
    tools.formatter._test_default_b = {
      mason = nil,
      ft = { "_test_default_order" },
    }
    tools.formatter_defaults._test_default_order = {
      "_test_default_b",
      "_test_default_a",
    }

    local groups = data.build_ft_groups("formatter", "_test_default_order")

    assert.equals(1, #groups)
    assert.same({ "_test_default_b", "_test_default_a" }, groups[1].names)
  end)

  it("filters groups and entries by filetype", function()
    local groups = data.build_ft_groups("formatter", "python")
    assert.equals(1, #groups)
    assert.equals("python", groups[1].ft)

    local entries = data.tool_entries("lsp", "lua")
    assert.is_true(#entries > 0)
    for _, entry in ipairs(entries) do
      assert.is_true(vim.tbl_contains(entry.meta.ft, "lua"))
    end
    assert.same({}, data.tool_entries("lsp", ""))
  end)

  it("returns tool entries in deterministic name order", function()
    local entries = data.tool_entries("lsp")
    local names = vim.tbl_map(function(entry)
      return entry.name
    end, entries)
    local sorted = vim.deepcopy(names)
    table.sort(sorted)
    assert.same(sorted, names)
  end)

  it("keeps external installation separate from configured runtime", function()
    package.loaded.conform =
      { formatters_by_ft = { prisma = { "prisma_fmt" } } }
    local health =
      data.health_status("formatter", "prisma_fmt", tools.formatter.prisma_fmt)
    assert.equals("external", health.installation)
    assert.equals("Configured", health.runtime)
    assert.equals("Configured", health.label)
    assert.is_false(health.attention)
  end)

  it(
    "prioritizes installation blockers without losing runtime or saved enablement",
    function()
      package.loaded.conform = { formatters_by_ft = { lua = { "stylua" } } }
      for _, case in ipairs({
        {
          installed = true,
          enabled = true,
          label = "Configured",
          installation = "installed",
          attention = false,
        },
        {
          installed = false,
          enabled = true,
          label = "Not installed",
          installation = "missing",
          attention = true,
        },
        {
          enabled = true,
          label = "Unknown",
          installation = "unknown",
          attention = true,
        },
        {
          installed = false,
          enabled = false,
          label = "Disabled",
          installation = "missing",
          attention = false,
        },
        {
          error = "registry unavailable",
          enabled = true,
          label = "Unknown",
          installation = "unavailable",
          attention = true,
        },
      }) do
        mason.package_status = function()
          return case.installed, case.error
        end
        state.get().formatter.stylua = case.enabled
        local health =
          data.health_status("formatter", "stylua", tools.formatter.stylua)
        assert.equals(case.label, health.label)
        assert.equals(case.installation, health.installation)
        assert.equals(case.enabled, health.enabled)
        assert.equals(case.attention, health.attention)
        assert.equals("Configured", health.runtime)
      end
    end
  )

  it("reports runtime wiring for the requested scope", function()
    local activation = package.loaded["tests.fixtures.activation"]
    package.loaded["tests.fixtures.activation"] = {
      formatters_by_ft = { lua = { "stylua" }, python = { "stylua" } },
    }
    package.loaded.conform = { formatters_by_ft = { lua = { "stylua" } } }
    mason.package_status = function()
      return true
    end
    local meta = { mason = "stylua", ft = { "lua", "python", "go" } }
    local labels = {}
    for _, filetype in ipairs({ "lua", "python", "go", false }) do
      labels[#labels + 1] =
        data.health_status("formatter", "stylua", meta, filetype or nil).label
    end
    package.loaded["tests.fixtures.activation"] = activation
    assert.same({
      "Configured",
      "Not configured",
      "Not configured",
      "Partly configured 1/2",
    }, labels)
  end)
  it("keeps source diagnostics distinct from a failed linter", function()
    package.loaded.lint = {
      linters_by_ft = { lua = { "luacheck" } },
      linters = { luacheck = { cmd = vim.v.progpath } },
    }
    mason.package_status = function()
      return true
    end
    diagnostic_buffer = vim.api.nvim_create_buf(false, false)
    local namespace = vim.api.nvim_create_namespace("luacheck")
    vim.diagnostic.set(namespace, diagnostic_buffer, {
      {
        lnum = 0,
        col = 0,
        message = "Source error",
        severity = vim.diagnostic.severity.ERROR,
      },
    })
    local health =
      data.health_status("linter", "luacheck", tools.linter.luacheck)
    assert.equals("Diagnostics: 1 errors, 0 warnings", health.label)
    assert.is_false(health.attention)
    package.loaded.lint.linters.luacheck.cmd = "__hangar_missing_linter__"
    health = data.health_status("linter", "luacheck", tools.linter.luacheck)
    assert.equals("Missing executable", health.label)
    assert.is_true(health.attention)
  end)
end)
