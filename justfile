set shell := ["sh", "-cu"]
set windows-shell := ["cmd.exe", "/d", "/c"]

lua_paths := "lua tests scripts"

# Check formatting, lint, generated help, and run the core and integration specs
all: fmt-check lint doc-check test-core test-integration

# Rewrite Lua formatting
fmt:
    stylua {{ lua_paths }} --config-path=.stylua.toml

# Check formatting without rewriting
fmt-check:
    stylua --check {{ lua_paths }} --config-path=.stylua.toml

# Run Luacheck
lint:
    luacheck {{ lua_paths }}

# Run one spec
test-spec spec:
    nvim --headless --clean -i NONE -l scripts/tests/run_suite.lua "{{ spec }}"

# Run hermetic core specs
test-core:
    nvim --headless --clean -i NONE -l scripts/tests/run_suite.lua tests/core

# Run specs that start other Neovim processes
test-integration:
    nvim --headless --clean -i NONE -l scripts/tests/run_suite.lua tests/integration

# Clone the pinned Plenary and Nui test dependencies into .deps/
deps:
    nvim --headless --clean -u NONE -l scripts/deps.lua

# Generate doc/hangar.txt from the annotations
doc:
    nvim --headless --clean -u NONE -l scripts/doc.lua

# Fail when doc/hangar.txt is out of date or its help tags are invalid
doc-check:
    nvim --headless --clean -u NONE -l scripts/doc.lua --check
