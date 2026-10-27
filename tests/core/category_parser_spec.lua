describe("hangar.category.parser", function()
  local parser
  local original_parser
  local original_handler
  local notify, notifications

  before_each(function()
    notify, notifications = vim.notify, {}
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message = message, level = level }
    end
    original_parser = package.loaded["nvim-treesitter"]
    original_handler = package.loaded["hangar.category.parser"]
    package.loaded["hangar.category.parser"] = nil
    package.loaded["nvim-treesitter"] = {
      get_installed = function()
        return { "lua", "python" }
      end,
      install = function()
        return {
          await = function(_, callback)
            callback(nil, true)
          end,
        }
      end,
    }
    parser = require("hangar.category.parser")
  end)

  after_each(function()
    vim.notify = notify
    package.loaded["nvim-treesitter"] = original_parser
    package.loaded["hangar.category.parser"] = original_handler
  end)

  it(
    "reports success only when the async installer confirms installation",
    function()
      local results = {}
      assert.is_true(parser.install("lua", function(ok, err)
        table.insert(results, { ok, err })
      end))
      assert.is_true(vim.wait(1000, function()
        return #results == 1
      end))
      assert.same({ true }, results[1])
    end
  )

  it("propagates parser install failures and rejects missing tasks", function()
    package.loaded["nvim-treesitter"].install = function()
      return {
        await = function(_, callback)
          callback(nil, false)
        end,
      }
    end
    local failed
    assert.is_true(parser.install("python", function(ok, err)
      failed = { ok, err }
    end))
    assert.is_true(vim.wait(1000, function()
      return failed ~= nil
    end))
    assert.is_false(failed[1])
    assert.equals("installation failed", failed[2])
    assert.equals(vim.log.levels.ERROR, notifications[#notifications].level)

    package.loaded["nvim-treesitter"].install = function() end
    local missing
    assert.is_false(parser.install("lua", function(ok, err)
      missing = { ok, err }
    end))
    assert.is_false(missing[1])
    assert.is_truthy(missing[2])
    assert.equals(vim.log.levels.ERROR, notifications[#notifications].level)
  end)
end)
