-- Clone the test and help dependencies into .deps/.
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
  {
    name = "mini.doc",
    url = "https://github.com/nvim-mini/mini.doc.git",
    commit = "54bb11880f2208a059a8d2564c3f4b586b78e044",
  },
  {
    name = "conform.nvim",
    url = "https://github.com/stevearc/conform.nvim.git",
    commit = "016802de402556da54c36bd7359b441266b01cdd",
  },
  {
    name = "nvim-lint",
    url = "https://github.com/mfussenegger/nvim-lint.git",
    commit = "f6230a5c06ba59e6059c14637f1dbe29a7978b9b",
  },
  {
    name = "nvim-dap",
    url = "https://github.com/mfussenegger/nvim-dap.git",
    commit = "8aba1e3805438ee6f74207e0b7385ef951bb9945",
  },
  -- The test reporter tracks its default branch, the stated exception to the
  -- pinning rule in AGENTS.md.
  {
    name = "telemetry.nvim",
    url = "https://github.com/Orbit-Lua/telemetry.nvim.git",
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
  if dependency.commit then
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
  else
    run({ "git", "-C", path, "pull", "--quiet", "--ff-only" })
  end
end
