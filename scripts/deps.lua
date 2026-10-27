-- Clone the pinned test dependencies into .deps/ and check out their commits.
local dependencies = {
  {
    name = "plenary.nvim",
    url = "https://github.com/nvim-lua/plenary.nvim.git",
    commit = "74b06c6c75e4eeb3108ec01852001636d85a932b",
  },
  {
    name = "nui.nvim",
    url = "https://github.com/MunifTanjim/nui.nvim.git",
    commit = "10fc361835c856ba4233ef5ea135b919bf3dce97",
  },
}

local function run(command)
  local result = vim.system(command, { text = true }):wait(300000)
  if result.code ~= 0 then
    error(
      table.concat(command, " ") .. " failed:\n" .. (result.stderr or ""),
      0
    )
  end
end

local root = vim.fn.getcwd() .. "/.deps"
vim.fn.mkdir(root, "p")
for _, dependency in ipairs(dependencies) do
  local path = root .. "/" .. dependency.name
  if vim.fn.isdirectory(path .. "/.git") == 0 then
    run({ "git", "clone", "--filter=blob:none", dependency.url, path })
  end
  run({ "git", "-C", path, "fetch", "--quiet", "origin", dependency.commit })
  run({
    "git",
    "-C",
    path,
    "checkout",
    "--quiet",
    "--detach",
    dependency.commit,
  })
end
