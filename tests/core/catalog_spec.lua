describe("hangar.catalog", function()
  local test = require("tests.helpers")
  local catalog, manager, state

  ---Configure hangar with only the given registry, so that every other
  ---entry comes from discovery.
  ---@param registry? Hangar.Registry
  local function configure(registry)
    vim.g.hangar_state_path = test.temp_dir("catalog-state") .. "/tools.json"
    require("hangar").setup({
      registry = registry,
      state_path = function()
        return vim.g.hangar_state_path
      end,
    })
    catalog = require("hangar.catalog")
    manager = require("hangar.manager")
    state = require("hangar.state")
    state.reset()
  end

  after_each(function()
    test.cleanup_all()
  end)

  it("lists enabled LSP configs and keeps registry fields over them", function()
    vim.lsp.config(
      "catalog_ls",
      { cmd = { "catalog-ls" }, filetypes = { "lua" } }
    )
    vim.lsp.config("catalog_alias", { cmd = { "alias" }, filetypes = { "c" } })
    vim.lsp.config("catalog_idle", { cmd = { "idle" }, filetypes = { "go" } })
    vim.lsp.enable({ "catalog_ls", "catalog_alias" })
    configure({
      lsp = {
        catalog_ls = { note = "from registry", ft = { "luau" } },
        logical = { runtime_name = "catalog_alias", mason = "alias-ls" },
      },
    })

    local entries = catalog.entries("lsp")
    assert.same({ note = "from registry", ft = { "luau" } }, entries.catalog_ls)
    assert.same(
      { runtime_name = "catalog_alias", mason = "alias-ls", ft = { "c" } },
      entries.logical
    )
    assert.is_nil(entries.catalog_alias)
    assert.is_nil(entries.catalog_idle)
  end)

  it("keeps an LSP server that state or hangar disabled", function()
    vim.lsp.config("catalog_off", { cmd = { "off" }, filetypes = { "sh" } })
    vim.lsp.config("catalog_kept", { cmd = { "kept" }, filetypes = { "zsh" } })
    configure()
    assert.is_true(state.set_enabled("lsp", "catalog_off", false))
    catalog.record("lsp", "catalog_kept")

    local entries = catalog.entries("lsp")
    assert.same({ ft = { "sh" } }, entries.catalog_off)
    assert.same({ ft = { "zsh" } }, entries.catalog_kept)
  end)

  it("reads formatter lists only from a loaded conform", function()
    package.preload.conform = function()
      error("discovery must not load conform")
    end
    configure()
    assert.same({}, catalog.entries("formatter"))

    package.loaded.conform = {
      formatters_by_ft = {
        lua = { "stylua" },
        luau = { "stylua", stop_after_first = true },
        ["*"] = { "trim_whitespace" },
        python = function() end,
      },
    }
    assert.same(
      { stylua = { ft = { "lua", "luau" } } },
      catalog.entries("formatter")
    )
  end)

  it("reads linters from a loaded nvim-lint", function()
    configure()
    package.loaded.lint = { linters_by_ft = { sh = { "shellcheck" } } }
    assert.same({ shellcheck = { ft = { "sh" } } }, catalog.entries("linter"))
  end)

  it("lists DAP adapters with the filetypes of their configurations", function()
    configure()
    package.loaded.dap = {
      adapters = { codelldb = {}, python = function() end },
      configurations = {
        rust = { { type = "codelldb" } },
        cpp = { { type = "codelldb" }, { type = "unknown" } },
      },
    }
    assert.same({
      codelldb = { ft = { "cpp", "rust" } },
      python = { ft = {} },
    }, catalog.entries("dap"))
  end)

  it("lists installed parsers with the filetypes of their language", function()
    package.loaded["nvim-treesitter"] = {
      get_installed = function()
        return { "lua", "markdown" }
      end,
    }
    configure()
    local entries = catalog.entries("parser")
    assert.same({ "lua" }, entries.lua.ft)
    assert.is_true(vim.tbl_contains(entries.markdown.ft, "markdown"))
  end)

  it("reports a missing install mapping for a discovered tool", function()
    vim.lsp.config("catalog_bare", { cmd = { "bare" }, filetypes = { "lua" } })
    vim.lsp.enable("catalog_bare")
    configure()

    local result
    assert.is_false(
      manager.install({ category = "lsp", name = "catalog_bare" }, function(...)
        result = { ... }
      end)
    )
    assert.same({ false, "no install mapping for catalog_bare" }, result)
    local snapshot = manager.snapshot({
      category = "lsp",
      source = { filetype = "lua" },
    })
    assert.equals("catalog_bare", snapshot.tools[1].name)
  end)
end)
