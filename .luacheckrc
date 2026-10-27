---@meta _

stds = { "luajit" }
cache = true
codes = true
-- Configuration code assigns fields such as vim.g and vim.opt.
globals = { "vim" }
files["tests/**"] = {
  read_globals = { "assert", "describe", "it", "before_each", "after_each" },
}
