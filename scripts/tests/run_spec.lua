package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path
assert(arg[1] and arg[2], "provide a spec and completion path")
require("scripts.tests.validate").install(arg[2])
require("plenary.busted").run(arg[1])
