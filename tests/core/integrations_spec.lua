describe("hangar.integrations", function()
  local test = require("tests.helpers")
  local integrations
  local applied

  local function count(target)
    local found = 0
    for _, loader in ipairs(package.loaders) do
      if loader == target then
        found = found + 1
      end
    end
    return found
  end

  before_each(function()
    applied = {}
    test.configure()
    integrations = require("hangar.integrations")
    integrations.targets.hangar_fixture_backend = {
      option = "conform",
      apply = function(module)
        table.insert(applied, module)
      end,
    }
    package.preload.hangar_fixture_backend = function()
      return { name = "backend" }
    end
  end)

  after_each(function()
    integrations.targets.hangar_fixture_backend = nil
    package.preload.hangar_fixture_backend = nil
    package.loaded.hangar_fixture_backend = nil
  end)

  it("applies a target when require returns it", function()
    local module = require("hangar_fixture_backend")
    assert.same({ module }, applied)
    assert.equals(module, package.loaded.hangar_fixture_backend)
  end)

  it("applies a loaded target at setup and installs one loader", function()
    local loader = package.loaders[1]
    local module = require("hangar_fixture_backend")
    test.configure()
    test.configure()
    assert.same({ module, module, module }, applied)
    assert.equals(1, count(loader))
  end)

  it(
    "reads the option per call, so a disabled integration does nothing",
    function()
      test.configure({ integrations = { conform = false } })
      require("hangar_fixture_backend")
      assert.same({}, applied)
      test.configure()
      assert.equals(1, #applied)
    end
  )

  it("reports a failing integration and still returns the module", function()
    local messages = {}
    local notify = vim.notify
    vim.notify = function(message)
      table.insert(messages, message)
    end
    integrations.targets.hangar_fixture_backend.apply = function()
      error("boom")
    end
    local ok, module = pcall(require, "hangar_fixture_backend")
    vim.notify = notify
    assert.is_true(ok)
    assert.same({ name = "backend" }, module)
    assert.is_truthy(
      messages[1]:find("hangar_fixture_backend integration failed", 1, true)
    )
  end)

  it("keeps the require error of a missing target module", function()
    package.preload.hangar_fixture_backend = nil
    local ok, err = pcall(require, "hangar_fixture_backend")
    assert.is_false(ok)
    assert.is_truthy(
      err:find("module 'hangar_fixture_backend' not found", 1, true)
    )
  end)

  it("rejects an unknown integration or a non-boolean value", function()
    local ok, err = pcall(test.configure, { integrations = { neotest = true } })
    assert.is_false(ok)
    assert.is_truthy(
      err:find("integrations.neotest is not an integration", 1, true)
    )
    ok, err = pcall(test.configure, { integrations = { lsp = "yes" } })
    assert.is_false(ok)
    assert.is_truthy(err:find("integrations.lsp must be a boolean", 1, true))
  end)
end)
