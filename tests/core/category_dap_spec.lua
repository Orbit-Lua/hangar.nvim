describe("hangar dap integration", function()
  local test = require("tests.helpers")
  local dap
  local notices

  ---@param opts? Hangar.Options
  local function configure(opts)
    local path = test.temp_dir("dap-state") .. "/tools.json"
    test.write_file(path, vim.json.encode({ dap = { codelldb = false } }))
    require("hangar").setup(vim.tbl_extend("force", {
      registry = {
        dap = { codelldb = { ft = { "c" } }, python = { ft = { "python" } } },
      },
      state_path = function()
        return path
      end,
    }, opts or {}))
    require("hangar.state").reset()
  end

  ---Run each `on_config` listener, as nvim-dap does at session start, and
  ---report whether a listener aborted the session.
  ---@param run_config table
  ---@return boolean aborted
  local function start(run_config)
    for _, listener in pairs(dap.listeners.on_config) do
      run_config = listener(run_config)
    end
    for _, value in pairs(run_config) do
      if value == dap.ABORT then
        return true
      end
    end
    return false
  end

  local function toggle(name)
    local result
    require("hangar.manager").toggle(
      { category = "dap", name = name },
      function(ok, err)
        result = { ok, err }
      end
    )
    return result
  end

  before_each(function()
    notices = {}
    vim.notify = function(message, level)
      table.insert(notices, { message, level })
    end
    package.preload.dap = function()
      return {
        ABORT = {},
        adapters = { codelldb = {}, python = {} },
        configurations = {
          c = { { type = "codelldb", name = "Launch" } },
          python = {},
        },
        listeners = { on_config = {} },
      }
    end
  end)

  after_each(function()
    package.preload.dap, package.loaded.dap = nil, nil
    test.cleanup_all()
  end)

  it("aborts a session of a disabled adapter type and says why", function()
    configure()
    dap = require("dap")

    assert.is_true(start({ type = "codelldb", name = "Launch" }))
    assert.same({
      {
        "Hangar: debug adapter codelldb is disabled in Hangar",
        vim.log.levels.ERROR,
      },
    }, notices)
    assert.is_false(start({ type = "python", name = "Launch" }))
  end)

  it("applies a toggle to the next session without an owner", function()
    configure()
    dap = require("dap")

    assert.same({ true }, toggle("codelldb"))
    assert.is_false(start({ type = "codelldb", name = "Launch" }))
    assert.same({ true }, toggle("python"))
    assert.is_true(start({ type = "python", name = "Launch" }))
  end)

  it("reports registration and configurations in the status", function()
    configure()
    dap = require("dap")
    local handler = require("hangar.category.dap")

    assert.same(
      { "disabled", "DiagnosticError" },
      { handler.entry_status({ name = "codelldb", meta = {} }) }
    )
    assert.same(
      { "registered 0 cfg", "DiagnosticWarn" },
      { handler.entry_status({ name = "python", meta = {} }) }
    )
    dap.adapters.python = nil
    assert.same(
      { "not registered 0 cfg", "DiagnosticError" },
      { handler.entry_status({ name = "python", meta = {} }) }
    )
  end)

  it("leaves sessions alone and refuses toggles when it is off", function()
    configure()
    dap = require("dap")
    configure({ integrations = { dap = false } })

    assert.is_false(start({ type = "codelldb", name = "Launch" }))
    local result = toggle("python")
    assert.is_false(result[1])
    assert.matches("integrations%.dap = false", result[2])
  end)

  it("rejects the removed adapters.dap option", function()
    local ok, err = pcall(require("hangar").setup, { adapters = { dap = {} } })
    assert.is_false(ok)
    assert.matches("adapters%.dap was removed", err)
  end)
end)
