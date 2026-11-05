describe("hangar.mason", function()
  local previous_registry
  local previous_mason
  local mason

  before_each(function()
    previous_registry = package.loaded["mason-registry"]
    previous_mason = package.loaded["hangar.mason"]
    package.loaded["hangar.mason"] = nil
    mason = require("hangar.mason")
  end)

  after_each(function()
    package.loaded["mason-registry"] = previous_registry
    package.loaded["hangar.mason"] = previous_mason
  end)

  it("returns package installation status through mason-registry", function()
    package.loaded["mason-registry"] = {
      get_package = function(name)
        assert.equals("stylua", name)
        return {
          is_installed = function()
            return true
          end,
        }
      end,
    }

    local installed, err = mason.package_status("stylua")

    assert.is_nil(err)
    assert.is_true(installed)
  end)

  it("normalizes missing package lookup errors", function()
    package.loaded["mason-registry"] = {
      get_package = function()
        error("unknown package")
      end,
    }

    local pkg, err = mason.get_package("_missing_")

    assert.is_nil(pkg)
    assert.equals("mason package not found: _missing_", err)
  end)

  it("shares one pending package install and completes every waiter", function()
    local installed = false
    local close_callback
    local install_count = 0
    package.loaded["mason-registry"] = {
      get_package = function()
        return {
          is_installed = function()
            return installed
          end,
          install = function()
            install_count = install_count + 1
            return {
              once = function(_, event, callback)
                assert.equals("closed", event)
                close_callback = callback
              end,
            }
          end,
        }
      end,
    }
    local results = {}
    assert.is_true(mason.install("shared-tool", function(ok)
      table.insert(results, ok)
    end))
    assert.is_true(mason.install("shared-tool", function(ok)
      table.insert(results, ok)
    end))
    assert.equals(1, install_count)

    installed = true
    close_callback()
    assert.is_true(vim.wait(1000, function()
      return #results == 2
    end))
    assert.same({ true, true }, results)
  end)

  ---A package stub whose install handle stays open until `close()` runs.
  local function stub_package(state)
    local pkg = { install_calls = 0 }
    function pkg.is_installed()
      return state.installed
    end
    function pkg.get_receipt()
      return {
        is_present = function()
          return state.receipt
        end,
      }
    end
    function pkg.install()
      pkg.install_calls = pkg.install_calls + 1
      return {
        once = function(_, event, callback)
          assert.equals("closed", event)
          pkg.close = callback
        end,
      }
    end
    return pkg
  end

  it("refreshes an empty registry once before it installs", function()
    local packages = {}
    local refreshes = 0
    local state = { installed = false, receipt = false }
    local pkg = stub_package(state)
    package.loaded["mason-registry"] = {
      get_package = function(name)
        return packages[name] or error("unknown package")
      end,
      refresh = function(callback)
        refreshes = refreshes + 1
        packages["lua-language-server"] = pkg
        callback(true, {})
      end,
    }
    local result
    assert.is_true(mason.install("lua-language-server", function(ok, err)
      result = { ok, err }
    end))
    assert.is_true(vim.wait(1000, function()
      return pkg.install_calls == 1
    end))
    assert.equals(1, refreshes)
    assert.is_true(mason.is_installing("lua-language-server"))

    state.installed, state.receipt = true, true
    pkg.close()
    assert.is_true(vim.wait(1000, function()
      return result ~= nil
    end))
    assert.same({ true }, result)
  end)

  it("reports a missing package after one registry refresh", function()
    local refreshes = 0
    package.loaded["mason-registry"] = {
      get_package = function()
        error("unknown package")
      end,
      refresh = function(callback)
        refreshes = refreshes + 1
        callback(true, {})
      end,
    }
    local result
    mason.install("_missing_", function(ok, err)
      result = { ok, err }
    end)
    assert.is_true(vim.wait(1000, function()
      return result ~= nil
    end))
    assert.equals(1, refreshes)
    assert.same({ false, "mason package not found: _missing_" }, result)
    assert.is_false(mason.is_installing("_missing_"))
  end)

  it("reports and reinstalls a package directory without a receipt", function()
    local state = { installed = true, receipt = false }
    local pkg = stub_package(state)
    package.loaded["mason-registry"] = {
      get_package = function()
        return pkg
      end,
    }

    local installed, err, broken = mason.package_status("lua-language-server")
    assert.is_false(installed)
    assert.is_nil(err)
    assert.is_true(broken)

    local result
    assert.is_true(mason.install("lua-language-server", function(ok)
      result = ok
    end))
    assert.equals(1, pkg.install_calls)
    state.receipt = true
    pkg.close()
    assert.is_true(vim.wait(1000, function()
      return result ~= nil
    end))
    assert.is_true(result)
    assert.same(
      { true, nil, nil },
      { mason.package_status("lua-language-server") }
    )
  end)

  it("removes every registry listener when observation is disposed", function()
    local listeners = {}
    package.loaded["mason-registry"] = {
      on = function(_, event, callback)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], callback)
      end,
      off = function(_, event, callback)
        listeners[event] = vim.tbl_filter(function(listener)
          return listener ~= callback
        end, listeners[event] or {})
      end,
    }
    local calls = 0
    local callback = function()
      calls = calls + 1
    end
    local dispose = mason.observe(callback)
    local function emit(event)
      for _, listener in ipairs(listeners[event] or {}) do
        listener()
      end
    end
    emit("package:install:failed")
    emit("package:uninstall:success")
    assert.equals(2, calls)

    dispose()
    for event, callbacks in pairs(listeners) do
      assert.same({}, callbacks, event)
      emit(event)
    end
    assert.equals(2, calls)
  end)
end)
