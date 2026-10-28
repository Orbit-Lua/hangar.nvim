-- Generate doc/hangar.txt with mini.doc from the public annotations in
-- lua/hangar/init.lua and lua/hangar/config.lua. With --check, generate into a
-- temporary directory instead, fail when the result differs from the tracked
-- file, and fail when :helptags reports an error such as a duplicate tag.
local root = vim.fn.getcwd()
local check = arg[1] == "--check"
local generator = root .. "/.deps/mini.doc"
if vim.fn.isdirectory(generator) == 0 then
  error("mini.doc is missing; run just deps", 0)
end
vim.opt.runtimepath:prepend(generator)

local doc = require("mini.doc")
doc.setup({})
local hooks = vim.deepcopy(doc.default_hooks)
-- Only blocks that name a help tag are public; other annotations document code.
hooks.block_pre = function(block)
  local public = block:has_descendant(function(item)
    return type(item) == "table"
      and item.type == "section"
      and item.info.id == "@tag"
  end)
  if not public then
    block:clear_lines()
    return
  end
  doc.default_hooks.block_pre(block)
end

local tracked = root .. "/doc/hangar.txt"
local directory = check and (vim.fn.tempname() .. "/doc") or (root .. "/doc")
vim.fn.mkdir(directory, "p")
local output = directory .. "/hangar.txt"
doc.generate({
  root .. "/lua/hangar/init.lua",
  root .. "/lua/hangar/config.lua",
}, output, { hooks = hooks })

if check then
  local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
  end
  if vim.fn.filereadable(tracked) == 0 or read(output) ~= read(tracked) then
    error("doc/hangar.txt is out of date; run just doc", 0)
  end
  local ok, err = pcall(vim.cmd.helptags, vim.fn.fnameescape(directory))
  if not ok then
    error("helptags failed: " .. tostring(err), 0)
  end
end
