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

describe("hangar treesitter integration", function()
  local test = require("tests.helpers")
  local CONSUMER = "HangarSpecConsumerTreesitter"
  local buffers

  ---@param opts? Hangar.Options
  local function configure(opts)
    local path = test.temp_dir("parser-state") .. "/tools.json"
    test.write_file(path, vim.json.encode({ parser = { lua = false } }))
    require("hangar").setup(vim.tbl_extend("force", {
      registry = { parser = { lua = { ft = { "lua" } } } },
      state_path = function()
        return path
      end,
    }, opts or {}))
    require("hangar.state").reset()
  end

  ---A Lua buffer. The consumer's own `FileType` handler starts Tree-sitter
  ---when `start` is true and stops it otherwise, after Neovim's Lua ftplugin
  ---has started it.
  ---@param start boolean
  ---@return integer
  local function lua_buffer(start)
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(buffers, buf)
    vim.b[buf].spec_start = start
    vim.bo[buf].filetype = "lua"
    vim.wait(20)
    return buf
  end

  ---@param buf integer
  ---@return boolean
  local function highlighted(buf)
    return vim.treesitter.highlighter.active[buf] ~= nil
  end

  local function toggle()
    local result
    require("hangar.manager").toggle(
      { category = "parser", name = "lua" },
      function(ok, err)
        result = { ok, err }
      end
    )
    return result
  end

  before_each(function()
    buffers = {}
    vim.notify = function() end
    -- The test runtimepath omits the directory of Neovim's bundled parsers.
    local bundled = vim.fn.fnamemodify(vim.v.progpath, ":h:h") .. "/lib/nvim"
    vim.opt.runtimepath:append(bundled)
    assert(vim.treesitter.language.add("lua"), "bundled Lua parser missing")
    package.loaded["nvim-treesitter"] = {
      get_installed = function()
        return { "lua" }
      end,
    }
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup(CONSUMER, { clear = true }),
      pattern = "lua",
      callback = function(args)
        if vim.b[args.buf].spec_start then
          vim.treesitter.start(args.buf, "lua")
        else
          vim.treesitter.stop(args.buf)
        end
      end,
    })
  end)

  after_each(function()
    vim.api.nvim_del_augroup_by_name(CONSUMER)
    pcall(vim.api.nvim_del_augroup_by_name, "HangarTreesitter")
    for _, buf in ipairs(buffers) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    package.loaded["nvim-treesitter"] = nil
    test.cleanup_all()
  end)

  it(
    "stops Tree-sitter after the consumer starts it for a disabled parser",
    function()
      configure()
      local buf = lua_buffer(true)

      assert.is_false(highlighted(buf))
    end
  )

  it("restarts only the buffers that it stopped", function()
    configure()
    local stopped = lua_buffer(true)
    local untouched = lua_buffer(false)

    assert.same({ true }, toggle())
    assert.is_true(highlighted(stopped))
    assert.is_false(highlighted(untouched))

    assert.same({ true }, toggle())
    assert.is_false(highlighted(stopped))
  end)

  it("reports highlighted buffers in the parser snapshot", function()
    configure()
    local function label()
      local snapshot = require("hangar.manager").snapshot({
        category = "parser",
        scope = "states",
      })
      for _, tool in ipairs(snapshot.tools) do
        if tool.name == "lua" then
          return tool.health_status.label, tool.health_status.runtime
        end
      end
    end
    lua_buffer(true)
    assert.same({ "Disabled", "Idle" }, { label() })

    assert.same({ true }, toggle())
    assert.same({ "Active in 1 buffer", "Active in 1 buffer" }, { label() })
    lua_buffer(true)
    assert.equals("Active in 2 buffers", label())
  end)

  it("leaves Tree-sitter alone and refuses toggles when it is off", function()
    configure({ integrations = { treesitter = false } })
    local buf = lua_buffer(true)

    assert.is_true(highlighted(buf))
    local result = toggle()
    assert.is_false(result[1])
    assert.matches("integrations%.treesitter = false", result[2])
  end)

  it("counts parsed injected languages once per highlighted buffer", function()
    configure({ integrations = { treesitter = false } })
    assert(
      vim.treesitter.language.add("vimdoc"),
      "bundled Vimdoc parser missing"
    )
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(buffers, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "-- first documentation region",
      "-- second documentation region",
    })
    local tree = vim.treesitter.get_parser(buf, "lua", {
      injections = {
        lua = '((comment) @injection.content (#set! injection.language "vimdoc"))',
        vimdoc = "",
      },
    })
    tree:parse(true)
    assert.is_not_nil(tree:children().vimdoc)
    assert.equals(2, #tree:children().vimdoc:trees())
    vim.treesitter.start(buf, "lua")
    local parser = require("hangar.category.parser")
    assert.equals(
      "active in 1 buffer",
      parser.entry_status({ name = "vimdoc" })
    )
    assert.equals("active in 1 buffer", parser.entry_status({ name = "lua" }))
    vim.treesitter.stop(buf)
    assert.equals("idle", parser.entry_status({ name = "vimdoc" }))
  end)

  it(
    "reports nested injections without parsing new regions for status",
    function()
      configure({ integrations = { treesitter = false } })
      local buf = vim.api.nvim_create_buf(true, false)
      table.insert(buffers, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "local docs = [=[",
        ">vim",
        "let g:probe = 1",
        "<",
        "]=]",
      })
      local tree = vim.treesitter.get_parser(buf, "lua", {
        injections = {
          lua = '((string_content) @injection.content (#set! injection.language "vimdoc"))',
        },
      })
      tree:parse(true)
      assert.is_not_nil(tree:children().vimdoc:children().vim)
      vim.treesitter.start(buf, "lua")
      local parser = require("hangar.category.parser")
      assert.equals("active in 1 buffer", parser.entry_status({ name = "vim" }))
      -- A newly added child has no parsed trees and must not become active just
      -- because the status UI inspected the highlighter.
      local unparsed = tree:add_child("query")
      assert.equals("idle", parser.entry_status({ name = "query" }))
      assert.same({}, unparsed:trees())
      vim.treesitter.stop(buf)
    end
  )
end)
