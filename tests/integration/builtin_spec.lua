describe("hangar built-in integrations", function()
  local test = require("tests.helpers")

  local tools = { "lsp", "plugin_lsp", "formatter", "linter", "dap", "parser" }

  ---Saved state that disables every fixture tool.
  local disabled = vim.json.encode({
    lsp = { fixture_ls = false, plugin_ls = false },
    formatter = { fixture_fmt = false },
    linter = { fixture_lint = false },
    dap = { fixture_dbg = false },
    parser = { lua = false },
  })

  ---Registry entries for the tools that discovery cannot find: a plugin LSP
  ---client and a parser without nvim-treesitter.
  local registry = {
    lsp = { plugin_ls = { plugin = "fixture_plugin", ft = { "lua" } } },
    parser = { lua = { ft = { "lua" } } },
  }

  ---@class HangarSpecChild
  ---@field options? Hangar.Options options for `hangar.setup`; nil calls it bare
  ---@field state? string saved state to seed before setup
  ---@field toggle? boolean toggle each tool after the first probe

  ---Run the consumer fixture in a child Neovim with private XDG directories.
  ---@param home string directory that keeps the child's data across runs
  ---@param child HangarSpecChild
  ---@return { before: table<string, boolean>, after?: table<string, boolean> }
  local function run(home, child)
    local work = test.temp_dir("builtin-work")
    test.write_file(work .. "/sample.lua", "local x = 1")
    local out = work .. "/result.json"
    local result = vim
      .system({
        vim.v.progpath,
        "--headless",
        "--clean",
        "-i",
        "NONE",
        "-c",
        "luafile "
          .. vim.fn.fnameescape(
            vim.fn.getcwd() .. "/tests/fixtures/builtin_child.lua"
          ),
      }, {
        text = true,
        env = {
          XDG_CONFIG_HOME = home .. "/config",
          XDG_DATA_HOME = home .. "/data",
          XDG_STATE_HOME = home .. "/state",
          XDG_CACHE_HOME = home .. "/cache",
          HANGAR_SPEC_ROOT = vim.fn.getcwd(),
          HANGAR_SPEC_WORK = work,
          HANGAR_SPEC_OUT = out,
          HANGAR_SPEC_OPTIONS = child.options and vim.json.encode(
            child.options
          ) or nil,
          HANGAR_SPEC_STATE = child.state,
          HANGAR_SPEC_TOGGLE = child.toggle and "1" or nil,
        },
      })
      :wait(60000)
    assert.equals(0, result.code, result.stderr)
    assert.equals(1, vim.fn.filereadable(out), result.stderr)
    local decoded = vim.json.decode(table.concat(vim.fn.readfile(out), "\n"))
    assert(decoded.error == nil, decoded.error)
    return decoded
  end

  ---@param value boolean
  ---@param except? string the one tool with the opposite value
  ---@return table<string, boolean>
  local function all(value, except)
    local expected = {}
    for _, tool in ipairs(tools) do
      expected[tool] = value
    end
    if except then
      expected[except] = not value
    end
    return expected
  end

  before_each(function()
    for _, name in ipairs({ "conform.nvim", "nvim-lint", "nvim-dap" }) do
      assert(
        vim.fn.isdirectory(test.plugin_path(name)) == 1,
        name .. " is missing; run just deps"
      )
    end
  end)

  it("gates each tool from saved state with no options", function()
    local home = test.temp_dir("builtin-bare")
    local expected = all(false)
    expected.plugin_lsp = nil
    local results = run(home, { state = disabled })
    results.before.plugin_lsp = nil
    assert.same(expected, results.before)
  end)

  it("applies toggles at runtime and keeps them after a restart", function()
    local home = test.temp_dir("builtin-restart")
    local options = { registry = registry }

    local first =
      run(home, { options = options, state = disabled, toggle = true })
    assert.same(all(false), first.before)
    assert.same(all(true), first.after)

    local second = run(home, { options = options, toggle = true })
    assert.same(all(true), second.before)
    assert.same(all(false), second.after)

    local third = run(home, { options = options })
    assert.same(all(false), third.before)
  end)

  for _, case in ipairs({
    { option = "lsp", tool = "lsp" },
    { option = "conform", tool = "formatter" },
    { option = "lint", tool = "linter" },
    { option = "dap", tool = "dap" },
    { option = "treesitter", tool = "parser" },
  }) do
    it(
      "runs the disabled tool with integrations." .. case.option .. " = false",
      function()
        local home = test.temp_dir("builtin-off-" .. case.option)
        local results = run(home, {
          options = {
            registry = registry,
            integrations = { [case.option] = false },
          },
          state = disabled,
        })
        local expected = all(false, case.tool)
        if case.option == "lsp" then
          expected.plugin_lsp = true
        end
        assert.same(expected, results.before)
      end
    )
  end
end)
