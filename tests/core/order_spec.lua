describe("hangar.order", function()
  local order
  local state
  local previous_lua_order
  local previous_stylua_enabled
  local original_state_path
  local original_state_module
  local original_order_module

  before_each(function()
    require("tests.helpers").configure()
    original_state_path = vim.g.hangar_state_path
    original_state_module = package.loaded["hangar.state"]
    original_order_module = package.loaded["hangar.order"]
    vim.g.hangar_state_path = require("tests.helpers").temp_dir("tool-order")
      .. "/tools.json"
    package.loaded["hangar.order"] = nil
    package.loaded["hangar.state"] = nil
    state = require("hangar.state")
    order = require("hangar.order")
    previous_lua_order = vim.deepcopy(state.get().formatter_order.lua)
    previous_stylua_enabled = state.is_enabled("formatter", "stylua")
  end)

  after_each(function()
    state.set_order("formatter", "_test_ft_order_", nil)
    state.set_order("formatter", "lua", previous_lua_order)
    state.set_enabled("formatter", "stylua", previous_stylua_enabled)
    vim.g.hangar_state_path = original_state_path
    package.loaded["hangar.state"] = original_state_module
    package.loaded["hangar.order"] = original_order_module
    require("tests.helpers").cleanup_all()
  end)

  it(
    "applies saved order while discarding stale and duplicate entries",
    function()
      state.set_order(
        "formatter",
        "_test_ft_order_",
        { "removed", "a", "b", "a" }
      )

      assert.same(
        { "a", "b", "z" },
        order.names_for_ft("formatter", "_test_ft_order_", { "b", "z", "a" })
      )
    end
  )

  it(
    "filters disabled managed tools but preserves unknown runtime entries",
    function()
      state.set_order("formatter", "lua", { "stylua" })
      state.set_enabled("formatter", "stylua", false)

      assert.same(
        { "external_formatter" },
        order.enabled_names_for_ft(
          "formatter",
          "lua",
          { "stylua", "external_formatter" }
        )
      )
    end
  )
end)
