local M = {}

function M.install(path)
  local busted = require("plenary.busted")
  local runtime_errors = {}
  vim.ui_attach(
    vim.api.nvim_create_namespace("hangar_test_errors"),
    { ext_messages = true },
    function(event, kind, content)
      if
        event == "msg_show"
        and (kind == "emsg" or kind == "lua_error" or kind == "echoerr")
      then
        local parts = {}
        for _, chunk in ipairs(content) do
          parts[#parts + 1] = chunk[2]
        end
        runtime_errors[#runtime_errors + 1] = table.concat(parts)
      end
    end
  )
  local original = busted.format_results
  busted.format_results = function(results)
    local summary = {
      passed = #results.pass,
      failed = #results.fail,
      errors = #results.errs,
      runtime_errors = runtime_errors,
    }
    assert(vim.fn.writefile({ vim.json.encode(summary) }, path) == 0)
    original(results)
  end
  busted.pending = function()
    error("skipped tests are not allowed", 0)
  end
  _G.pending = busted.pending
end

function M.check(result)
  assert(result.passed > 0, "test spec executed no tests")
  assert(result.failed == 0 and result.errors == 0, "test spec failed")
  assert(
    not result.runtime_errors or #result.runtime_errors == 0,
    table.concat(result.runtime_errors or {}, "\n")
  )
end

return M
