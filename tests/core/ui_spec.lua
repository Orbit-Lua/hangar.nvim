describe("Hangar Nui sessions", function()
  local tool
  local source
  local original_window
  local original_runtimepath
  local original_notify
  local original_columns
  local original_lines
  local saved_modules
  local callbacks
  local operations
  local snapshots
  local order
  local logger
  local linter
  local original_entries
  local original_diagnostics

  local function buffer_for(filetype)
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_loaded(buffer)
        and vim.bo[buffer].filetype == filetype
      then
        return buffer
      end
    end
  end

  local function body()
    local buffer = assert(buffer_for("Hangar"))
    return buffer
  end

  local function lines(buffer)
    return table.concat(
      vim.api.nvim_buf_get_lines(buffer or body(), 0, -1, false),
      "\n"
    )
  end

  local function press(key, buffer)
    local mapping = vim.api.nvim_buf_call(buffer or body(), function()
      return vim.fn.maparg(key, "n", false, true)
    end)
    assert(mapping.callback, "missing mapping: " .. key)()
  end

  local function select(text)
    local window = vim.fn.bufwinid(body())
    for index, line in ipairs(vim.api.nvim_buf_get_lines(body(), 0, -1, false)) do
      if line:find(text, 1, true) then
        vim.api.nvim_win_set_cursor(window, { index, 0 })
        return index
      end
    end
    error("missing entry: " .. text)
  end

  local function line_for(text)
    for index, line in ipairs(vim.api.nvim_buf_get_lines(body(), 0, -1, false)) do
      if line:find(text, 1, true) then
        return index
      end
    end
    error("missing row: " .. text)
  end

  before_each(function()
    original_runtimepath = vim.o.runtimepath
    original_window = vim.api.nvim_get_current_win()
    original_columns, original_lines = vim.o.columns, vim.o.lines
    original_notify = vim.notify
    vim.notify = function() end
    local nui = require("tests.helpers").plugin_path("nui.nvim")
    assert.equals(
      1,
      vim.fn.isdirectory(nui),
      "nui.nvim is required for UI specs"
    )
    vim.opt.runtimepath:append(nui)
    saved_modules = {}
    for name, value in pairs(package.loaded) do
      if
        name == "hangar"
        or name:match("^hangar%.")
        or name:match("^nui[%.]?")
      then
        saved_modules[name] = value
      end
    end
    for name in pairs(saved_modules) do
      package.loaded[name] = nil
    end
    -- The manager is a fake here, so its log source is a plain table.
    logger = {
      get_entries = function()
        return {}
      end,
    }
    linter = require("hangar.category").linter
    original_entries = logger.get_entries
    original_diagnostics = linter.get_linter_diagnostics
    source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(original_window, source)
    vim.bo[source].filetype = "python"
    vim.api.nvim_buf_set_name(
      source,
      require("tests.helpers").temp_dir("ui-source") .. "/sample.py"
    )
    callbacks, operations, snapshots = {}, {}, {}
    order = { "ruff_fix", "ruff_format" }
    package.loaded["hangar.manager"] = {
      details = function(selection)
        return {
          logs = logger.get_entries("linter", selection.name),
          diagnostics = linter.get_linter_diagnostics(selection.name),
        }
      end,
      snapshot = function(opts)
        table.insert(snapshots, vim.deepcopy(opts))
        local names = opts.category == "formatter" and order
          or { "pyright", "ruff" }
        local tools = {}
        for _, name in ipairs(names) do
          table.insert(tools, {
            name = name,
            meta = { ft = { "python", "lua" }, source = "external" },
            enabled = true,
            status = "configured",
            status_hl = "DiagnosticOk",
            health_status = {
              label = "Configured",
              icon = "✓",
              severity = "DiagnosticOk",
              installation = "installed",
              source = "Mason",
              runtime = "Started",
              enabled = true,
              attention = false,
            },
          })
        end
        return {
          category = opts.category,
          tools = tools,
          groups = { { ft = "python", names = vim.deepcopy(names) } },
          summary = { total = #tools },
        }
      end,
      toggle = function(selection, callback)
        table.insert(operations, selection)
        table.insert(callbacks, callback)
      end,
      install = function(selection, callback)
        table.insert(operations, selection)
        table.insert(callbacks, callback)
      end,
      reorder = function(selection, callback)
        table.insert(operations, selection)
        order[1], order[2] = order[2], order[1]
        callback(true)
      end,
    }
    tool = require("hangar")
  end)

  after_each(function()
    tool.close()
    vim.wait(20)
    if vim.api.nvim_win_is_valid(original_window) then
      vim.api.nvim_set_current_win(original_window)
    end
    if vim.api.nvim_buf_is_valid(source) then
      vim.api.nvim_buf_delete(source, { force = true })
    end
    vim.o.runtimepath = original_runtimepath
    vim.o.columns, vim.o.lines = original_columns, original_lines
    vim.notify = original_notify
    logger.get_entries = original_entries
    linter.get_linter_diagnostics = original_diagnostics
    for name in pairs(package.loaded) do
      if
        name == "hangar"
        or name:match("^hangar%.")
        or name:match("^nui[%.]?")
      then
        package.loaded[name] = saved_modules[name]
      end
    end
    require("tests.helpers").cleanup_all()
  end)

  -- Registered after the spec's own hook, so setup follows any module reset.
  before_each(function()
    require("tests.helpers").configure()
  end)

  it(
    "captures source scope, navigates categories, expands and retains reordered selection",
    function()
      tool.open()
      local buffer, window = body(), vim.api.nvim_get_current_win()
      tool.open()
      assert.equals(buffer, body())
      assert.equals(window, vim.api.nvim_get_current_win())
      assert.equals(source, snapshots[1].source.bufnr)
      assert.equals("python", snapshots[1].source.filetype)
      press("<S-Tab>")
      assert.equals("package", snapshots[#snapshots].category)
      press("<Tab>")
      assert.equals("lsp", snapshots[#snapshots].category)
      press("3")
      assert.equals("linter", snapshots[#snapshots].category)
      press("4")
      assert.equals("formatter", snapshots[#snapshots].category)
      assert.is_true(line_for("ruff_fix") < line_for("ruff_format"))
      select("ruff_fix")
      press("]")
      assert.is_true(vim.wait(100, function()
        return #snapshots >= 7
      end))
      assert.is_true(line_for("ruff_format") < line_for("ruff_fix"))
      local selected_line = vim.api.nvim_win_get_cursor(window)[1]
      assert.is_truthy(
        vim.api
          .nvim_buf_get_lines(buffer, selected_line - 1, selected_line, false)[1]
          :find("ruff_fix", 1, true)
      )
      press("o")
      assert.is_truthy(lines():find("ruff_fix", 1, true))
      assert.is_nil(lines():find("ft: python", 1, true))
      press("s")
      assert.equals("states", snapshots[#snapshots].scope)
      assert.is_nil(lines():find("ruff_fix", 1, true))
      press("<CR>")
      assert.is_truthy(lines():find("ruff_fix", 1, true))
      tool.close()
      tool.open()
      assert.equals("formatter", snapshots[#snapshots].category)
      assert.equals("buffer", snapshots[#snapshots].scope)
      assert.is_truthy(lines():find("ruff_fix", 1, true))
      for _, size in ipairs({
        { 180, 45 },
        { 120, 40 },
        { 120, 21 },
        { 48, 40 },
      }) do
        vim.o.columns, vim.o.lines = size[1], size[2]
        local count = #snapshots
        vim.api.nvim_exec_autocmds("VimResized", {})
        assert.is_true(vim.wait(100, function()
          return #snapshots > count
        end))
        assert.equals(body(), vim.api.nvim_get_current_buf())
        local preview = buffer_for("HangarDetails")
        if size[1] < 85 or size[2] < 23 then
          assert.is_nil(preview)
        else
          local frame = vim.fn.bufwinid(buffer_for("HangarFrame"))
          assert.is_not_nil(preview)
          local preview_window = vim.fn.bufwinid(preview)
          local fp = vim.api.nvim_win_get_position(frame)
          local dp = vim.api.nvim_win_get_position(preview_window)
          assert.is_true(
            dp[2] >= fp[2] + vim.api.nvim_win_get_width(frame) + 2
              or dp[1] >= fp[1] + vim.api.nvim_win_get_height(frame) + 2
          )
        end
      end
    end
  )

  it(
    "keeps help inert and rejects stale callbacks after external close and reopen",
    function()
      tool.open()
      select("ruff")
      press("i")
      press("?")
      local help = lines()
      for _, key in ipairs({ "<Space>", "i", "[", "]", "o", "K" }) do
        press(key)
      end
      assert.equals(1, #operations)
      callbacks[1](true)
      vim.api.nvim_exec_autocmds("User", { pattern = "HangarChanged" })
      vim.wait(20)
      assert.equals(help, lines())
      press("g?")
      assert.is_truthy(vim.api.nvim_get_current_line():find("ruff", 1, true))
      press("K")
      assert.is_truthy(lines(buffer_for("HangarDetails")):find("ruff", 1, true))
      local detail_text = lines(buffer_for("HangarDetails"))
      assert.is_truthy(detail_text:find("Installation: Installed", 1, true))
      assert.is_truthy(detail_text:find("Source: Mason", 1, true))
      assert.is_truthy(detail_text:find("Runtime: Started", 1, true))
      assert.is_truthy(detail_text:find("Enabled: On", 1, true))
      local detail_buffer = buffer_for("HangarDetails")
      assert.equals(detail_buffer, vim.api.nvim_get_current_buf())
      press("<Esc>", detail_buffer)
      assert.equals(body(), vim.api.nvim_get_current_buf())
      press("6")
      select("pyright")
      press("K")
      assert.is_truthy(
        lines(buffer_for("HangarDetails")):find("Enabled: N/A", 1, true)
      )
      press("<Esc>", buffer_for("HangarDetails"))
      press("3")
      local maximum = require("hangar.config").get().ui.details.max_messages
      logger.get_entries = function()
        return { { level = "ERROR", message = string.rep("字", 100) } }
      end
      linter.get_linter_diagnostics = function()
        local messages = {}
        for index = 1, maximum + 2 do
          messages[index] = {
            file = "sample.py",
            lnum = index,
            message = string.rep("診斷", 100),
            severity = vim.diagnostic.severity.ERROR,
          }
        end
        return { messages = messages }
      end
      select("ruff")
      press("K")
      detail_buffer = buffer_for("HangarDetails")
      assert.is_truthy(lines(detail_buffer):find("+2 more", 1, true))
      local detail_width =
        vim.api.nvim_win_get_width(vim.fn.bufwinid(detail_buffer))
      assert.is_true(detail_width > 0)
      assert.is_true(vim.wo[vim.fn.bufwinid(detail_buffer)].wrap)
      assert.is_truthy(
        lines(detail_buffer):find(string.rep("診斷", 50), 1, true)
      )
      local old_buffers = {}
      for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buffer].filetype:match("^Hangar") then
          table.insert(old_buffers, buffer)
        end
      end
      vim.api.nvim_win_close(vim.fn.bufwinid(body()), true)
      assert.is_true(vim.wait(100, function()
        return buffer_for("Hangar") == nil
      end))
      for _, buffer in ipairs(old_buffers) do
        assert.is_false(vim.api.nvim_buf_is_valid(buffer))
      end
      tool.open()
      local count = #snapshots
      callbacks[1](true)
      vim.wait(20)
      assert.equals(count, #snapshots)
      vim.api.nvim_exec_autocmds("User", { pattern = "HangarChanged" })
      assert.is_true(vim.wait(100, function()
        return #snapshots == count + 1
      end))
      vim.api.nvim_win_close(vim.fn.bufwinid(buffer_for("HangarFrame")), true)
      assert.is_true(vim.wait(100, function()
        return buffer_for("Hangar") == nil
      end))
      vim.api.nvim_exec_autocmds("User", { pattern = "HangarChanged" })
      vim.wait(20)
      assert.equals(count + 1, #snapshots)
      for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
        assert.is_nil((autocmd.group_name or ""):match("^HangarView"))
      end
    end
  )

  it(
    "fits narrow layouts and disposes debounced refreshes and wiped buffers",
    function()
      -- Exercise the real timer without waiting for the user-facing debounce.
      local config = require("hangar.config").get().ui
      config.refresh.debounce_ms = 10
      tool.open()
      press("3")
      select("ruff")
      press("K")
      for _, size in ipairs({ { 120, 40 }, { 120, 24 }, { 48, 14 }, { 24, 9 } }) do
        vim.o.columns, vim.o.lines = size[1], size[2]
        vim.api.nvim_exec_autocmds("VimResized", {})
        local count = #snapshots
        assert.is_true(vim.wait(100, function()
          return #snapshots > count
        end))
        assert.equals(
          buffer_for("HangarDetails"),
          vim.api.nvim_get_current_buf()
        )
        local frame = vim.fn.bufwinid(buffer_for("HangarFrame"))
        local origin = vim.api.nvim_win_get_position(frame)
        -- Neovim reports the outer border position; child windows start inside it.
        origin[1], origin[2] = origin[1] + 1, origin[2] + 1
        local frame_width = vim.api.nvim_win_get_width(frame)
        local frame_height = vim.api.nvim_win_get_height(frame)
        for _, filetype in ipairs({
          "HangarNavigation",
          "Hangar",
          "HangarStatus",
        }) do
          local window = vim.fn.bufwinid(buffer_for(filetype))
          local position = vim.api.nvim_win_get_position(window)
          assert.equals(origin[2], position[2])
          assert.equals(frame_width, vim.api.nvim_win_get_width(window))
          assert.is_true(position[1] >= origin[1])
          assert.is_true(
            position[1] + vim.api.nvim_win_get_height(window)
              <= origin[1] + frame_height
          )
          assert.equals("none", vim.api.nvim_win_get_config(window).border)
        end
        if size[1] == 24 then
          assert.is_truthy(
            lines(buffer_for("HangarNavigation")):find("Linter", 1, true)
          )
        end
        if size[1] == 120 then
          local frame_position = vim.api.nvim_win_get_position(frame)
          local frame_bottom = frame_position[1]
            + vim.api.nvim_win_get_height(frame)
          local details_window = vim.fn.bufwinid(buffer_for("HangarDetails"))
          local details_position = vim.api.nvim_win_get_position(details_window)
          assert.is_true(details_position[1] >= frame_bottom)
        end
        for _, window in ipairs(vim.api.nvim_list_wins()) do
          local buffer = vim.api.nvim_win_get_buf(window)
          if
            vim.bo[buffer].filetype:match("^Hangar")
            and vim.bo[buffer].filetype ~= "HangarDetails"
          then
            assert.is_true(vim.api.nvim_win_get_width(window) <= vim.o.columns)
            for _, line in
              ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false))
            do
              assert.is_true(vim.api.nvim_win_call(window, function()
                return vim.fn.strdisplaywidth(line)
              end) <= vim.api.nvim_win_get_width(window), line)
            end
          end
        end
      end
      press("<Esc>", buffer_for("HangarDetails"))
      local count = #snapshots
      vim.api.nvim_exec_autocmds("DiagnosticChanged", { buffer = source })
      assert.is_true(vim.wait(100, function()
        return #snapshots == count + 1
      end))
      vim.api.nvim_exec_autocmds("DiagnosticChanged", { buffer = source })
      count = #snapshots
      vim.api.nvim_buf_delete(body(), { force = true })
      vim.wait(config.refresh.debounce_ms * 2)
      assert.equals(count, #snapshots)
      assert.is_nil(buffer_for("Hangar"))
      tool.close()
    end
  )
  it(
    "fits schema-valid details preferences inside the available editor",
    function()
      vim.o.columns, vim.o.lines = 160, 40
      require("hangar.config").get().ui.details.width = 300
      tool.open()
      press("K")
      for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)
        if vim.bo[buffer].filetype:match("^Hangar") then
          local position = vim.api.nvim_win_get_position(window)
          assert.is_true(position[2] >= 0)
          assert.is_true(
            position[2] + vim.api.nvim_win_get_width(window) <= vim.o.columns
          )
          assert.is_true(
            position[1] + vim.api.nvim_win_get_height(window) <= vim.o.lines
          )
        end
      end
      assert.is_not_nil(buffer_for("HangarDetails"))
    end
  )

  it(
    "refreshes an open view from caller ui changes while preserving help and selection",
    function()
      vim.o.columns, vim.o.lines = 180, 50
      tool.open()
      select("ruff")
      press("?")
      local count = #snapshots
      require("hangar.config").get().ui.width = 90
      vim.api.nvim_exec_autocmds("User", { pattern = "HangarChanged" })
      assert.is_true(vim.wait(200, function()
        return #snapshots > count
      end))
      assert.equals(90, vim.api.nvim_win_get_width(vim.fn.bufwinid(body())))
      press("<Space>")
      assert.same({}, operations)
      press("?")
      assert.is_truthy(vim.api.nvim_get_current_line():find("ruff", 1, true))
    end
  )

  it(
    "keeps one details pane current across rows, categories and help",
    function()
      local manager = package.loaded["hangar.manager"]
      local snapshot = manager.snapshot
      manager.snapshot = function(opts)
        local result = snapshot(opts)
        if opts.category == "package" then
          result.tools, result.groups, result.summary = {}, {}, { total = 0 }
        end
        return result
      end
      local tool_only =
        { "Installation:", "Source:", "Runtime:", "Mason package:", "Backend:" }
      local function pane()
        local buffer = buffer_for("HangarDetails")
        return buffer, buffer and vim.fn.bufwinid(buffer)
      end
      local function text()
        return table.concat(
          vim.api.nvim_buf_get_lines((pane()), 0, -1, false),
          "\n"
        )
      end
      local function move(row)
        select(row)
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = body() })
      end
      local function without_tool_facts()
        for _, field in ipairs(tool_only) do
          assert.is_nil(text():find(field, 1, true), field)
        end
      end
      for _, size in ipairs({ { 160, 45 }, { 100, 40 } }) do
        vim.o.columns, vim.o.lines = size[1], size[2]
        tool.open()
        press("4")
        press("s")
        local buffer, window = pane()
        assert.is_not_nil(buffer)
        assert.truthy(text():find("Priority order", 1, true))
        assert.truthy(text():find("1. ruff_fix", 1, true))
        without_tool_facts()

        -- Expansion persists across sessions, so expand only when collapsed.
        if not lines():find("ruff_format", 1, true) then
          press("o")
        end
        move("ruff_format")
        assert.truthy(text():find("ruff_format", 1, true))
        assert.truthy(text():find("Installation:", 1, true))
        move("python (")
        without_tool_facts()

        press("6")
        assert.truthy(text():find("No managed tools", 1, true))
        without_tool_facts()
        press("?")
        assert.truthy(text():find("Legend", 1, true))
        without_tool_facts()
        assert.same({ buffer, window }, { pane() })

        press("?")
        press("4")
        local header = table.concat(
          vim.api.nvim_buf_get_lines(
            buffer_for("HangarNavigation"),
            0,
            -1,
            false
          ),
          "\n"
        )
        assert.truthy(header:find("Enabled", 1, true))
        assert.is_nil(lines():find("Enabled", 1, true))

        move("python (")
        press("K")
        assert.equals(window, vim.api.nvim_get_current_win())
        press("q", buffer)
        assert.equals(vim.fn.bufwinid(body()), vim.api.nvim_get_current_win())
        assert.is_true(vim.api.nvim_win_is_valid(window))

        vim.api.nvim_win_close(window, true)
        vim.wait(50)
        move("python (")
        local _, reopened = pane()
        assert.is_true(reopened ~= nil and vim.api.nvim_win_is_valid(reopened))
        tool.close()
      end

      -- Nine lines cannot hold a normal frame even without margin.
      vim.o.columns, vim.o.lines = 80, 9
      tool.open()
      local compact = table.concat(
        vim.api.nvim_buf_get_lines(buffer_for("HangarNavigation"), 0, -1, false),
        "\n"
      )
      assert.is_nil(compact:find("Enabled", 1, true))
    end
  )

  it("colors each status icon by state and keeps theme overrides", function()
    local manager = package.loaded["hangar.manager"]
    local function entry(name, enabled, health)
      return {
        name = name,
        meta = { ft = { "python" } },
        enabled = enabled,
        status = health.label,
        status_hl = health.severity,
        health_status = health,
      }
    end
    manager.snapshot = function(opts)
      table.insert(snapshots, vim.deepcopy(opts))
      return {
        category = opts.category,
        tools = {
          entry("on_tool", true, {
            label = "Configured",
            severity = "DiagnosticOk",
            installation = "installed",
            enabled = true,
          }),
          entry("off_tool", false, {
            label = "Disabled",
            severity = "Comment",
            installation = "installed",
            enabled = false,
          }),
          entry("busy_tool", true, {
            label = "Installing",
            severity = "DiagnosticInfo",
            installation = "installing",
            enabled = true,
          }),
          entry("bad_tool", true, {
            label = "Failed",
            severity = "DiagnosticError",
            installation = "installed",
            enabled = true,
          }),
        },
        groups = {},
        summary = { total = 4 },
      }
    end
    local override = { fg = 0xff0000 }
    vim.api.nvim_set_hl(0, "HangarIconError", override)
    tool.open()
    local function icon_group(name)
      local row = line_for(name) - 1
      for _, mark in
        ipairs(
          vim.api.nvim_buf_get_extmarks(
            body(),
            -1,
            { row, 0 },
            { row, -1 },
            { details = true }
          )
        )
      do
        -- Padding moves the icon, so find its group anywhere in the row.
        if tostring(mark[4].hl_group):find("^HangarIcon") then
          return mark[4].hl_group
        end
      end
    end
    assert.equals("HangarIconEnabled", icon_group("on_tool"))
    assert.equals("HangarIconDisabled", icon_group("off_tool"))
    assert.equals("HangarIconInstalling", icon_group("busy_tool"))
    assert.equals("HangarIconError", icon_group("bad_tool"))

    local function refreshed(event)
      local count = #snapshots
      vim.api.nvim_exec_autocmds(event, {})
      assert.is_true(vim.wait(200, function()
        return #snapshots > count
      end))
    end
    refreshed("ColorScheme")
    tool.close()
    tool.open()
    assert.same(override, vim.api.nvim_get_hl(0, { name = "HangarIconError" }))

    vim.cmd("highlight clear")
    refreshed("ColorScheme")
    for _, group in pairs(require("hangar.ui.render").icon_highlights) do
      assert.is_not_nil(vim.api.nvim_get_hl(0, { name = group }).link, group)
    end
  end)

  it(
    "applies, resets and bounds layout spacing from caller ui changes",
    function()
      local ui = require("hangar.config").get().ui
      local defaults = vim.deepcopy(ui.layout)
      vim.o.columns, vim.o.lines = 160, 45
      tool.open()
      local function refreshed(apply)
        local count = #snapshots
        apply()
        assert.is_true(vim.wait(200, function()
          return #snapshots > count
        end))
      end
      local function save(layout)
        refreshed(function()
          -- A caller replaces the layout table, as a settings reload does.
          ui.layout =
            vim.tbl_deep_extend("force", vim.deepcopy(defaults), layout)
          vim.api.nvim_exec_autocmds("User", { pattern = "HangarChanged" })
        end)
      end
      local function resize(columns, rows)
        refreshed(function()
          vim.o.columns, vim.o.lines = columns, rows
          vim.api.nvim_exec_autocmds("VimResized", {})
        end)
      end
      ---Outer border box of a bordered window.
      local function box(filetype)
        local buffer = buffer_for(filetype)
        local window = buffer and vim.fn.bufwinid(buffer)
        if not window or window == -1 then
          return nil
        end
        local position = vim.api.nvim_win_get_position(window)
        return {
          row = position[1],
          col = position[2],
          width = vim.api.nvim_win_get_width(window) + 2,
          height = vim.api.nvim_win_get_height(window) + 2,
        }
      end
      local function measure()
        local row = line_for("pyright")
        local text = vim.api.nvim_buf_get_lines(body(), row - 1, row, false)[1]
        local frame, details = box("HangarFrame"), box("HangarDetails")
        local on = text:find("On", 1, true)
        return {
          row = row,
          indent = #text:match("^ *"),
          -- "On" is padded to the Enabled width; the gap follows it.
          -- Narrow columns can truncate the status, so it may be absent.
          status = on
            and text:find("Configured", 1, true)
            and (text:find("Configured", 1, true) - on),
          gap = details and details.col - frame.col - frame.width,
          margin = math.min(
            frame.row,
            frame.col,
            vim.o.columns - (details or frame).col - (details or frame).width
          ),
        }
      end

      local default = measure()
      assert.equals(1, default.row)
      assert.equals(2 + 2, default.indent)
      assert.equals(2, default.gap)
      assert.is_true(default.margin >= 2)

      save({ padding = { horizontal = 5 } })
      assert.equals(5 + 2, measure().indent)
      save({ padding = { vertical = 3 } })
      assert.equals(3 + 1, measure().row)
      save({ column_gap = 7 })
      assert.equals(default.status + 4, measure().status)
      save({ gap = 6 })
      assert.equals(6, measure().gap)
      save({ margin = 9 })
      assert.is_true(measure().margin >= 9)
      save(vim.empty_dict())
      assert.same(default, measure())

      -- Margin gives way first; gap shrinks only after margin reaches 0.
      save({
        padding = { vertical = 8, horizontal = 8 },
        column_gap = 8,
        gap = 10,
        margin = 10,
      })
      resize(160, 40)
      assert.equals(10, measure().gap)
      resize(160, 24)
      assert.equals(0, measure().gap)
      for _, size in ipairs({ { 48, 14 }, { 24, 9 } }) do
        resize(size[1], size[2])
        for _, filetype in ipairs({ "HangarFrame", "HangarDetails" }) do
          local window = box(filetype)
          if window then
            assert.is_true(window.row >= 0 and window.col >= 0, filetype)
            assert.is_true(window.col + window.width <= vim.o.columns, filetype)
            assert.is_true(window.row + window.height <= vim.o.lines, filetype)
          end
        end
        assert.is_true(
          vim.api.nvim_win_get_height(vim.fn.bufwinid(body())) >= 1
        )
      end
    end
  )

  it(
    "replaces view options, rebinds keys and keeps a valid category",
    function()
      vim.o.columns, vim.o.lines = 160, 45
      ---Text of every floating window, which holds the footer hints.
      local function floats()
        local text = {}
        for _, window in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(window).relative ~= "" then
            local buffer = vim.api.nvim_win_get_buf(window)
            table.insert(text, lines(buffer))
          end
        end
        return table.concat(text, "\n")
      end
      local function update(values)
        local count = #snapshots
        tool.update_ui(values)
        assert.is_true(vim.wait(200, function()
          return #snapshots > count
        end))
      end
      local function mapped(key)
        return vim.api.nvim_buf_call(body(), function()
          return vim.fn.maparg(key, "n") ~= ""
        end)
      end

      tool.open()
      local default_width = vim.api.nvim_win_get_width(vim.fn.bufwinid(body()))
      update({ width = 90 })
      assert.equals(90, vim.api.nvim_win_get_width(vim.fn.bufwinid(body())))
      update({})
      assert.equals(
        default_width,
        vim.api.nvim_win_get_width(vim.fn.bufwinid(body()))
      )
      assert.is_false(pcall(tool.update_ui, "wide"))
      for _, categories in ipairs({ {}, { "nope" } }) do
        assert.is_false(pcall(tool.update_ui, { categories = categories }))
      end
      assert.equals(
        default_width,
        vim.api.nvim_win_get_width(vim.fn.bufwinid(body()))
      )

      -- Close moves from q to x: bindings, help and footer follow.
      local mappings = vim.deepcopy(require("hangar.config").get().ui.mappings)
      for _, mapping in ipairs(mappings) do
        if mapping.action == "close" then
          mapping.keys = { "x" }
        end
      end
      update({ mappings = mappings, categories = { "lsp", "formatter" } })
      assert.is_true(mapped("x"))
      assert.is_false(mapped("q"))
      assert.is_true(mapped("2"))
      assert.is_false(mapped("3"))
      assert.truthy(floats():find(" x close", 1, true))
      assert.is_nil(floats():find(" q close", 1, true))
      press("?")
      assert.truthy(
        lines():find("1–2  Select category (LSP, Formatter)", 1, true)
      )
      assert.truthy(lines():find("x  Close Hangar", 1, true))
      press("?")

      -- The selected category follows its name, or falls back to the first.
      press("2")
      update({ mappings = mappings, categories = { "formatter", "lsp" } })
      assert.equals("formatter", snapshots[#snapshots].category)
      update({ mappings = mappings, categories = { "lsp" } })
      assert.equals("lsp", snapshots[#snapshots].category)

      -- A view reopened after an update starts on a valid category.
      update({})
      press("6")
      press("q")
      tool.update_ui({ categories = { "lsp" } })
      tool.open()
      assert.equals("lsp", snapshots[#snapshots].category)
    end
  )
end)
