-- A consumer Neovim for `tests/integration/builtin_spec.lua`. It sets up
-- Hangar before real conform.nvim, nvim-lint and nvim-dap, opens a Lua buffer
-- and probes whether each tool runs. With `HANGAR_SPEC_TOGGLE`, it toggles each
-- tool through the manager and probes again. It writes the results as JSON to
-- `HANGAR_SPEC_OUT`.
local root = vim.env.HANGAR_SPEC_ROOT
local deps = root .. "/.deps"
vim.opt.runtimepath:prepend(table.concat({
  root,
  deps .. "/conform.nvim",
  deps .. "/nvim-lint",
  deps .. "/nvim-dap",
}, ","))
vim.opt.runtimepath:append(
  vim.fn.fnamemodify(vim.v.progpath, ":h:h") .. "/lib/nvim"
)

local work = vim.env.HANGAR_SPEC_WORK
local notices = {}
vim.notify = function(message)
  table.insert(notices, message)
end

---An in-process server that answers initialize and shutdown.
local function server(dispatchers)
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

---@param condition fun(): boolean
---@param timeout? integer
---@return boolean
local function wait(condition, timeout)
  return vim.wait(timeout or 3000, condition, 10) == true
end

local function setup()
  -- Seed the default state file, which a restarted child reads as it is.
  if vim.env.HANGAR_SPEC_STATE then
    local path = vim.fn.stdpath("data") .. "/hangar.json"
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile({ vim.env.HANGAR_SPEC_STATE }, path)
  end
  local options = vim.json.decode(vim.env.HANGAR_SPEC_OPTIONS or "null")
  if options == vim.NIL then
    require("hangar").setup()
  else
    require("hangar").setup(options)
  end

  vim.lsp.config("fixture_ls", { cmd = server, filetypes = { "lua" } })
  vim.lsp.enable("fixture_ls")

  require("conform").setup({
    formatters_by_ft = { lua = { "fixture_fmt" } },
    formatters = {
      fixture_fmt = {
        format = function(_, _, lines, callback)
          callback(nil, vim.tbl_map(string.upper, lines))
        end,
      },
    },
  })

  local lint = require("lint")
  local script = work .. "/lint.lua"
  vim.fn.writefile({ 'io.write("fixture")' }, script)
  lint.linters.fixture_lint = {
    cmd = vim.v.progpath,
    args = { "--clean", "--headless", "-l", script },
    stdin = false,
    append_fname = false,
    ignore_exitcode = true,
    parser = function(output)
      return {
        {
          lnum = 0,
          col = 0,
          message = output,
          severity = vim.diagnostic.severity.WARN,
        },
      }
    end,
  }
  lint.linters_by_ft = { lua = { "fixture_lint" } }

  require("dap").adapters.fixture_dbg = function()
    vim.g.hangar_spec_adapter = true
  end

  -- The consumer's Tree-sitter owner.
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "lua",
    callback = function(args)
      pcall(vim.treesitter.start, args.buf, "lua")
    end,
  })
end

---@param buf integer
---@return boolean
local function probe_lsp(buf)
  local function running()
    for _, client in
      ipairs(vim.lsp.get_clients({ bufnr = buf, name = "fixture_ls" }))
    do
      if not client:is_stopped() then
        return true
      end
    end
    return false
  end
  if not wait(running, 1000) then
    return false
  end
  -- A runtime disable stops the client asynchronously.
  vim.wait(200)
  return running()
end

---Start a client outside `vim.lsp.config`, as a plugin does, and report
---whether it stays attached.
---@param buf integer
---@return boolean
local function probe_plugin_lsp(buf)
  local id =
    vim.lsp.start({ name = "plugin_ls", cmd = server, root_dir = work })
  assert(id, "plugin_ls did not start")
  assert(wait(function()
    return vim.lsp.buf_is_attached(buf, id)
  end))
  vim.wait(100)
  local client = vim.lsp.get_client_by_id(id)
  local running = client ~= nil and not client:is_stopped()
  if client then
    client:stop(true)
  end
  return running
end

---@param buf integer
---@return boolean
local function probe_formatter(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = 1" })
  require("conform").format({ bufnr = buf, async = false })
  return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "LOCAL X = 1"
end

---@param buf integer
---@return boolean
local function probe_linter(buf)
  local lint = require("lint")
  vim.diagnostic.reset(nil, buf)
  lint.try_lint()
  if #lint.get_running(buf) == 0 then
    return false
  end
  return wait(function()
    return #vim.diagnostic.get(buf) > 0
  end, 10000)
end

---@return boolean
local function probe_dap()
  vim.g.hangar_spec_adapter = false
  notices = {}
  require("dap").run({
    type = "fixture_dbg",
    request = "launch",
    name = "Fixture",
  })
  assert(wait(function()
    return vim.g.hangar_spec_adapter or #notices > 0
  end))
  return vim.g.hangar_spec_adapter == true
end

---@param buf integer
---@return boolean
local function probe_parser(buf)
  vim.wait(50)
  return vim.treesitter.highlighter.active[buf] ~= nil
end

---@param buf integer
---@return table<string, boolean>
local function probe(buf)
  return {
    lsp = probe_lsp(buf),
    plugin_lsp = probe_plugin_lsp(buf),
    formatter = probe_formatter(buf),
    linter = probe_linter(buf),
    dap = probe_dap(),
    parser = probe_parser(buf),
  }
end

local function toggle_all()
  for _, tool in ipairs({
    { category = "lsp", name = "fixture_ls" },
    { category = "lsp", name = "plugin_ls" },
    { category = "formatter", name = "fixture_fmt" },
    { category = "linter", name = "fixture_lint" },
    { category = "dap", name = "fixture_dbg" },
    { category = "parser", name = "lua" },
  }) do
    local result
    require("hangar.manager").toggle(tool, function(ok, err)
      result = { ok = ok, err = err }
    end)
    assert(
      wait(function()
        return result ~= nil
      end),
      "toggle did not finish: " .. tool.name
    )
    assert(result.ok, tool.name .. ": " .. tostring(result.err))
  end
end

-- Probe after startup: `vim.lsp.enable` reattaches open buffers only after
-- `VimEnter`, and a real toggle happens then.
setup()
vim.schedule(function()
  local ok, result = xpcall(function()
    vim.cmd.edit(vim.fn.fnameescape(work .. "/sample.lua"))
    local buf = vim.api.nvim_get_current_buf()
    local results = { before = probe(buf) }
    if vim.env.HANGAR_SPEC_TOGGLE then
      toggle_all()
      results.after = probe(buf)
    end
    return results
  end, debug.traceback)
  vim.fn.writefile({
    vim.json.encode(ok and result or { error = result }),
  }, vim.env.HANGAR_SPEC_OUT)
  vim.cmd("qa!")
end)
