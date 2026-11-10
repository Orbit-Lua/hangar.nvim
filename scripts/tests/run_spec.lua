package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path
assert(arg[1] and arg[2], "provide a spec and completion path")
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.deps/telemetry.lua")
require("scripts.tests.validate").install(arg[2])
require("telemetry.busted").install()
require("plenary.busted").run(arg[1])
