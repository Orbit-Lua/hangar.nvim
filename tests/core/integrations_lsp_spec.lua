describe("hangar LSP integration", function()
  local test = require("tests.helpers")
  local manager
  -- Load the LSP client modules outside the per-test isolation, which would
  -- otherwise drop them and leave Neovim with two client tables.
  for _, name in ipairs({
    "vim.lsp",
    "vim.lsp.client",
    "vim.lsp.rpc",
    "vim.lsp.log",
  }) do
    require(name)
  end

  ---An in-process server that answers initialize and shutdown.
  local function server()
    return function(dispatchers)
      local closing = false
      return {
        request = function(method, _, callback)
          if method == "initialize" then
            callback(nil, { capabilities = {} })
          elseif method == "shutdown" then
            callback(nil, nil)
          end
          return true, 1
        end,
        notify = function(method)
          if method == "exit" then
            closing = true
            dispatchers.on_exit(0, 15)
          end
          return true
        end,
        is_closing = function()
          return closing
        end,
        terminate = function()
          closing = true
        end,
      }
    end
  end

  ---@param saved table<string, boolean> saved LSP enablement
  ---@param opts? Hangar.Options
  local function configure(saved, opts)
    local path = test.temp_dir("lsp-state") .. "/tools.json"
    test.write_file(path, vim.json.encode({ lsp = saved }))
    require("hangar").setup(vim.tbl_extend("force", {
      registry = {
        lsp = {
          logical_ls = { runtime_name = "aliased_ls" },
          plugin_ls = { plugin = "fixture_plugin" },
        },
      },
      state_path = function()
        return path
      end,
    }, opts or {}))
    require("hangar.state").reset()
    manager = require("hangar.manager")
  end

  local function toggle(name)
    local result
    manager.toggle({ category = "lsp", name = name }, function(ok, err)
      result = { ok, err }
    end)
    return result
  end

  before_each(function()
    vim.notify = function() end
    for _, name in ipairs({ "gated_ls", "open_ls", "aliased_ls" }) do
      vim.lsp.config(name, { cmd = server(), filetypes = { "lua" } })
    end
  end)

  after_each(function()
    for _, client in ipairs(vim.lsp.get_clients()) do
      client:stop(true)
    end
    vim.lsp.enable({ "gated_ls", "open_ls", "aliased_ls" }, false)
    test.cleanup_all()
  end)

  it("drops an enable of a disabled server and replays it on toggle", function()
    configure({ gated_ls = false })
    vim.lsp.enable({ "gated_ls", "open_ls" })
    assert.is_false(vim.lsp.is_enabled("gated_ls"))
    assert.is_true(vim.lsp.is_enabled("open_ls"))
    assert.is_not_nil(require("hangar.catalog").get("lsp", "gated_ls"))

    assert.same({ true }, toggle("gated_ls"))
    assert.is_true(vim.lsp.is_enabled("gated_ls"))
    assert.same({ true }, toggle("gated_ls"))
    assert.is_false(vim.lsp.is_enabled("gated_ls"))
  end)

  it("never enables a server that the consumer did not enable", function()
    configure({ gated_ls = false })
    assert.same({ true }, toggle("gated_ls"))
    assert.is_false(vim.lsp.is_enabled("gated_ls"))
  end)

  it(
    "disables an enabled server at setup and replays it when turned off",
    function()
      vim.lsp.enable("aliased_ls")
      configure({ logical_ls = false })
      assert.is_false(vim.lsp.is_enabled("aliased_ls"))

      configure({ logical_ls = false }, { integrations = { lsp = false } })
      assert.is_true(vim.lsp.is_enabled("aliased_ls"))
      vim.lsp.enable("gated_ls")
      assert.is_true(vim.lsp.is_enabled("gated_ls"))
    end
  )

  it("stops a disabled plugin client when it attaches", function()
    configure({ plugin_ls = false })
    local buffer = vim.api.nvim_create_buf(true, false)
    local id = vim.lsp.start(
      { name = "plugin_ls", cmd = server(), root_dir = vim.uv.cwd() },
      { bufnr = buffer }
    )
    assert.is_truthy(id)
    assert.is_true(vim.wait(2000, function()
      return #vim.lsp.get_clients({ name = "plugin_ls" }) == 0
    end))

    configure({ plugin_ls = true })
    vim.lsp.start(
      { name = "plugin_ls", cmd = server(), root_dir = vim.uv.cwd() },
      { bufnr = buffer }
    )
    vim.wait(200)
    local snapshot = manager.snapshot({ category = "lsp", scope = "states" })
    local status
    for _, tool in ipairs(snapshot.tools) do
      if tool.name == "plugin_ls" then
        status = tool.health_status.runtime
      end
    end
    assert.equals("Running 1", status)
  end)
end)
