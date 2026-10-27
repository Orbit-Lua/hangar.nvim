-- Fixture activation: initial runtime names by filetype.
return {
  formatters_by_ft = {
    lua = { "stylua" },
    python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
    sh = { "shfmt" },

    -- web dev
    css = { "deno_fmt" },
    html = { "deno_fmt" },

    -- eslint_d is used for fix, not complete formatting, so deno_fmt is needed
    typescript = { "deno_fmt", "eslint_d" },
    javascript = { "deno_fmt", "eslint_d" },

    typescriptreact = { "deno_fmt", "eslint_d" },
    javascriptreact = { "deno_fmt", "eslint_d" },
    jsx = { "deno_fmt", "eslint_d" },

    json = { "deno_fmt" },
    jsonc = { "deno_fmt" },
    toml = { "tombi" },
    prisma = { "prisma_fmt" },
    cs = { "csharpier" },

    -- markdown
    ["markdown"] = { "markdownlint-cli2", "markdown-toc" },
    ["markdown.mdx"] = { "markdownlint-cli2", "markdown-toc" },

    yaml = { "yamlfmt" },

    sql = { "sqlfluff" },
    mysql = { "sqlfluff" },
    plsql = { "sqlfluff" },
  },
  linters_by_ft = {
    -- ['*'] = { 'global linter' },
    -- ['_'] = { 'fallback linter' },
    -- ["*"] = { "typos" },

    dockerfile = { "hadolint" },
    markdown = { "markdownlint-cli2" },
    lua = { "luacheck" },

    typescript = { "eslint_d" },
    javascript = { "eslint_d" },

    typescriptreact = { "eslint_d" },
    javascriptreact = { "eslint_d" },
    jsx = { "eslint_d" },

    sql = { "sqlfluff" },
    mysql = { "sqlfluff" },
    plsql = { "sqlfluff" },
  },
}
