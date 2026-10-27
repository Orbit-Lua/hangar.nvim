-- Fixture registry: the tools of the configuration that hangar was extracted from.
local M = {}

-- This registry is the canonical source for managed development tools,
-- installer dependencies, and Treesitter parsers.

-- LSP: lsp_config_name -> { mason, ft }
M.lsp = {
  pyright = { mason = "pyright", ft = { "python" } },
  ruff = { mason = "ruff", ft = { "python" } },
  roslyn = { mason = "roslyn-language-server", ft = { "cs" } },
  html = { mason = "html-lsp", ft = { "html" } },
  cssls = { mason = "css-lsp", ft = { "css" } },
  tailwindcss = {
    mason = "tailwindcss-language-server",
    ft = { "html", "css", "typescriptreact", "javascriptreact" },
  },
  dockerls = {
    mason = "dockerfile-language-server",
    ft = { "dockerfile" },
  },
  docker_compose_language_service = {
    mason = "docker-compose-language-service",
    ft = { "yaml.docker-compose" },
  },
  clangd = { mason = "clangd", ft = { "c", "cpp" } },
  bashls = { mason = "bash-language-server", ft = { "sh", "bash" } },
  marksman = { mason = "marksman", ft = { "markdown" } },
  prismals = { mason = "prisma-language-server", ft = { "prisma" } },
  tombi = { mason = "tombi", ft = { "toml" } },
  jsonls = { mason = "json-lsp", ft = { "json" } },
  lua_ls = { mason = "lua-language-server", ft = { "lua" } },
  gopls = { mason = "gopls", ft = { "go" } },
  powershell_es = { mason = "powershell-editor-services", ft = { "ps1" } },
  lemminx = { mason = "lemminx", ft = { "xml" } },
  yamlls = { mason = "yaml-language-server", ft = { "yaml" } },
}

-- DAP: adapter type name (as used in dap.adapters) -> { mason?, ft, note? }
M.dap = {
  python = {
    mason = nil,
    ft = { "python" },
    note = "uses venv debugpy",
  },
  coreclr = { mason = "netcoredbg", ft = { "cs" } },
}

-- LINTER: individual linter ID (as used in nvim-lint) -> { mason, ft }
M.linter = {
  eslint_d = {
    mason = "eslint_d",
    ft = {
      "typescript",
      "javascript",
      "typescriptreact",
      "javascriptreact",
      "jsx",
    },
  },
  hadolint = { mason = "hadolint", ft = { "dockerfile" } },
  ["markdownlint-cli2"] = { mason = "markdownlint-cli2", ft = { "markdown" } },
  luacheck = {
    mason = nil,
    ft = { "lua" },
    note = "uses Luacheck 1.2+ from LuaRocks or the standalone executable",
  },
  sqlfluff = { mason = "sqlfluff", ft = { "sql", "mysql", "plsql" } },
}

-- FORMATTER: individual formatter ID (as used in conform.nvim) -> { mason, ft, note? }
-- ruff_* variants all map to the same "ruff" mason package
M.formatter = {
  stylua = { mason = "stylua", ft = { "lua" } },
  ruff_fix = { mason = "ruff", ft = { "python" } },
  ruff_organize_imports = { mason = "ruff", ft = { "python" } },
  ruff_format = { mason = "ruff", ft = { "python" } },
  shfmt = { mason = "shfmt", ft = { "sh" } },
  deno_fmt = {
    mason = "deno",
    ft = {
      "css",
      "html",
      "typescript",
      "javascript",
      "typescriptreact",
      "javascriptreact",
      "jsx",
      "json",
      "jsonc",
      "markdown",
      "markdown.mdx",
    },
  },
  eslint_d = {
    mason = "eslint_d",
    ft = {
      "typescript",
      "javascript",
      "typescriptreact",
      "javascriptreact",
      "jsx",
    },
  },
  csharpier = { mason = "csharpier", ft = { "cs" } },
  ["markdownlint-cli2"] = {
    mason = "markdownlint-cli2",
    ft = { "markdown", "markdown.mdx" },
  },
  ["markdown-toc"] = {
    mason = "markdown-toc",
    ft = { "markdown", "markdown.mdx" },
  },
  sqlfluff = { mason = "sqlfluff", ft = { "sql", "mysql", "plsql" } },
  prisma_fmt = {
    mason = nil,
    ft = { "prisma" },
    note = "uses local node_modules",
  },
  tombi = { mason = "tombi", ft = { "toml" } },
  yaml = { mason = "yamlfmt", ft = { "yaml" }, runtime_name = "yamlfmt" },
}

-- PARSER: Treesitter parser name -> { ft }
-- Parser names and Neovim filetypes are intentionally mapped explicitly.
M.parser = {
  lua = { ft = { "lua" } },
  luadoc = { ft = { "lua" } },
  printf = { ft = { "c", "cpp" } },
  vim = { ft = { "vim" } },
  vimdoc = { ft = { "help" } },
  html = { ft = { "html" } },
  css = { ft = { "css" } },
  javascript = { ft = { "javascript", "javascriptreact" } },
  typescript = { ft = { "typescript" } },
  tsx = { ft = { "typescriptreact", "javascriptreact" } },
  c = { ft = { "c" } },
  cpp = { ft = { "cpp" } },
  python = { ft = { "python" } },
  bash = { ft = { "sh", "bash" } },
  markdown = { ft = { "markdown", "markdown.mdx" } },
  sql = { ft = { "sql", "mysql", "plsql" } },
  prisma = { ft = { "prisma" } },
  comment = { ft = {} },
  c_sharp = { ft = { "cs" } },
  xml = { ft = { "xml" } },
  go = { ft = { "go" } },
  regex = { ft = {} },
  yaml = { ft = { "yaml" } },
}
for _, definition in pairs(M.parser) do
  definition.source = "treesitter"
end

-- Mason packages needed by configuration code but not represented by a
-- directly toggleable runtime tool.
M.package = {
  ["typescript-language-server"] = {
    source = "mason",
    role = "dependency",
    note = "provides the tsserver runtime used by the TypeScript LSP config",
  },
}

-- Default formatter order per ft where more than one formatter applies.
M.formatter_defaults = {
  python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
  markdown = { "markdownlint-cli2", "markdown-toc" },
  ["markdown.mdx"] = { "markdownlint-cli2", "markdown-toc" },
}

-- Canonical default linter order per ft
M.linter_defaults = {}

for _, category in ipairs({ "lsp", "dap", "linter", "formatter" }) do
  for _, definition in pairs(M[category]) do
    definition.source = definition.mason and "mason" or "external"
  end
end

return M
