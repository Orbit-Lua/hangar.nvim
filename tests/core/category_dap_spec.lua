describe("hangar.category.dap", function()
  local test = require("tests.helpers")
  local dap_category
  local calls

  ---A DAP owner that records delegated calls and reports a fixed status.
  local function owner()
    calls = {}
    return {
      runtime = function()
        return {
          apply_adapter = function(dap, name, enabled, options)
            table.insert(calls, { dap, name, enabled, options })
            return true
          end,
          adapter_status = function(_, name)
            return "status of " .. name, "DiagnosticOk"
          end,
        }
      end,
      options = function()
        return { fixture = true }
      end,
    }
  end

  before_each(function()
    package.loaded["hangar.category.dap"] = nil
    dap_category = require("hangar.category.dap")
  end)

  it("reports unavailable nvim-dap and refuses runtime changes", function()
    test.configure({ adapters = { dap = owner() } })
    package.loaded.dap = nil
    package.preload.dap = function()
      error("dap unavailable")
    end

    local status, hl = dap_category.entry_status({ name = "python" })

    assert.is_nil(status)
    assert.is_nil(hl)
    local ok, err =
      dap_category.apply_runtime({ name = "python", is_enabled = true })
    assert.is_false(ok)
    assert.matches("nvim%-dap is unavailable", err)
    assert.same({}, calls)
  end)

  it("delegates status and runtime changes to the injected owner", function()
    test.configure({ adapters = { dap = owner() } })
    local dap = { adapters = {}, configurations = {} }
    package.loaded.dap = dap

    assert.same(
      { "status of python", "DiagnosticOk" },
      { dap_category.entry_status({ name = "python" }) }
    )
    assert.is_true(
      dap_category.apply_runtime({ name = "python", is_enabled = false })
    )
    assert.same({ { dap, "python", false, { fixture = true } } }, calls)
    assert.is_nil(dap_category.unavailable())
  end)

  it("reports a missing owner and refuses runtime changes", function()
    test.configure()
    package.loaded.dap = { adapters = {}, configurations = {} }

    assert.matches("no DAP owner configured", dap_category.unavailable())
    assert.same(
      { "no DAP owner configured", "DiagnosticWarn" },
      { dap_category.entry_status({ name = "python" }) }
    )
    local ok, err =
      dap_category.apply_runtime({ name = "python", is_enabled = true })
    assert.is_false(ok)
    assert.matches("adapters%.dap", err)
  end)
end)
