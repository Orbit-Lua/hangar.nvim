---@class Hangar.ApplyRuntimeOpts
---@field name string
---@field meta Hangar.Definition
---@field is_enabled boolean
---@class Hangar.StatusOpts
---@field name string
---@field meta Hangar.Definition
---@field installed boolean?
---@field filetype string?
---@field bufnr integer?
---@class Hangar.ApplyOrderOpts
---@field ft string
---@field enabled_names string[]

---@class Hangar.CategoryHandler
---@field capabilities {toggle: boolean, install: boolean, reorder: boolean}
---@field apply_runtime? fun(opts: Hangar.ApplyRuntimeOpts): boolean?, string?
---@field apply_order? fun(opts: Hangar.ApplyOrderOpts): boolean?, string?
---@field entry_status? fun(opts: Hangar.StatusOpts): string?, string?, table?
---@field install? fun(name: string, on_complete?: fun(success: boolean, err?: string)): boolean
---@field installation_status? fun(name: string): boolean?, string?
---@field wiring_status? fun(opts: Hangar.StatusOpts): string?, string?
---@field unavailable? fun(): string? why runtime changes cannot apply, checked before state is saved

return {
  lsp = require("hangar.category.lsp"),
  dap = require("hangar.category.dap"),
  linter = require("hangar.category.linter"),
  formatter = require("hangar.category.formatter"),
  parser = require("hangar.category.parser"),
  package = require("hangar.category.package"),
}
