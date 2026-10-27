local M = {}

---@class Hangar.ListAdapterSpec
---@field module string
---@field field string
---@field category "formatter"|"linter"

---@param spec Hangar.ListAdapterSpec
---@return Hangar.CategoryHandler
function M.new(spec)
  local order = require("hangar.order")
  local config = require("hangar.config")

  -- The injected activation lists initial runtime names by filetype; it is read
  -- per call so live configuration changes apply.
  local function initial_activation()
    return config.get().adapters.activation[spec.category]()
  end
  local missing_activation = "activation not configured: inject adapters.activation."
    .. spec.category
  local adapter = {
    capabilities = { toggle = true, install = true, reorder = true },
  }

  ---Report why runtime changes cannot apply, before any state is saved.
  function adapter.unavailable()
    if not config.get().adapters.activation[spec.category] then
      return missing_activation
    end
  end

  local function backend()
    local ok, module = pcall(require, spec.module)
    if not ok then
      return nil, tostring(module)
    end
    return module
  end

  function adapter.apply_runtime(opts)
    if adapter.unavailable() then
      return false, missing_activation
    end
    local module, err = backend()
    if not module then
      return false, err
    end

    -- Enabling restores a tool only where the configuration activates it;
    -- other supported filetypes stay unwired, matching the next startup.
    local activation = initial_activation()
    local runtime_name = opts.meta.runtime_name or opts.name
    for _, ft in ipairs(opts.meta.ft or {}) do
      local list = module[spec.field][ft] or {}
      if opts.is_enabled then
        if
          vim.tbl_contains(activation[ft] or {}, runtime_name)
          and not vim.tbl_contains(list, runtime_name)
        then
          table.insert(list, runtime_name)
        end
      else
        for i = #list, 1, -1 do
          if list[i] == runtime_name then
            table.remove(list, i)
          end
        end
      end
      if module[spec.field][ft] or #list > 0 then
        local names = order.from_runtime(spec.category, list)
        local ordered = order.enabled_names_for_ft(spec.category, ft, names)
        module[spec.field][ft] = order.to_runtime(spec.category, ordered)
      end
    end
  end

  function adapter.apply_order(opts)
    if adapter.unavailable() then
      return false, missing_activation
    end
    local module, err = backend()
    if not module then
      return false, err
    end
    local old = module[spec.field][opts.ft] or {}
    local known = {}
    for name, meta in pairs(config.get().registry[spec.category] or {}) do
      if vim.tbl_contains(meta.ft or {}, opts.ft) then
        known[meta.runtime_name or name] = true
      end
    end
    local result = vim.tbl_filter(function(name)
      return vim.tbl_contains(old, name)
    end, order.to_runtime(spec.category, opts.enabled_names))
    for _, name in ipairs(old) do
      if not known[name] and not vim.tbl_contains(result, name) then
        table.insert(result, name)
      end
    end
    module[spec.field][opts.ft] = result
  end

  function adapter.wiring_status(opts)
    local module = backend()
    if not module then
      return nil, nil
    end
    if adapter.unavailable() then
      return "activation not configured", "DiagnosticWarn"
    end

    local filetypes = opts.filetype and { opts.filetype }
      or (opts.meta.ft or {})
    if #filetypes == 0 then
      return "no ft", "DiagnosticWarn"
    end

    -- Measure against the configured activation, the set enabling restores.
    local runtime_name = opts.meta.runtime_name or opts.name
    local activation = initial_activation()
    local total, configured = 0, 0
    for _, ft in ipairs(filetypes) do
      if vim.tbl_contains(activation[ft] or {}, runtime_name) then
        total = total + 1
        if vim.tbl_contains(module[spec.field][ft] or {}, runtime_name) then
          configured = configured + 1
        end
      end
    end

    if configured == 0 then
      return "not configured", "DiagnosticWarn"
    elseif configured < total then
      return string.format("partly configured %d/%d", configured, total),
        "DiagnosticWarn"
    end
    return nil, nil
  end

  return adapter
end

return M
