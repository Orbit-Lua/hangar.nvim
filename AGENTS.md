# AGENTS Instructions

Preserve the setup options, mappings and persisted state unless the task changes their contracts. Linux and Windows are equal targets.

## Git

- Write commits in [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) format.
- For a non-trivial change, write a commit body that explains why.
- Mark a breaking change with `!` and a `BREAKING CHANGE:` footer.
- Author commits as the user alone, without `Co-Authored-By` or other co-author trailers.
- Commit as the plan progresses.
- Before you push, squash related commits into one commit to keep the history clean.
- Push only after the user approves that push.
- Version releases with [Semantic Versioning 2.0.0](https://semver.org/).
- Pin each test and help dependency to a commit that exists on its remote.

## Code

- Read configuration only from the `setup()` options. Do not require a module of the configuration that uses hangar.
- Register no user command or mapping outside an open view.
- Keep a caller's `ui` table as the same object. Fill only its missing keys.
- Check the adapter's `unavailable()` before saving state. Persist intent before runtime changes.
- Import owners directly. Add a module only when its interface hides meaningful complexity.
- Use public plugin interfaces.
- Capture buffer identity before asynchronous work.
- Replace subscriptions during repeated setup.
- Preserve unexpected redraw errors with context.

## Platforms

- Build paths with `/`, which Neovim accepts on Windows.
- Use explicit executable names and argument lists for native commands.
- Keep just recipes valid under Unix `sh` and native Windows `cmd.exe`.

## Tests

- Add a test to the repo only when it guards behavior that no existing test covers.
- The test must fail when that behavior breaks. Weigh this before you add each test.
- Run throwaway tests freely to check your work.
- Keep throwaway tests out of the repo unless they meet the bar above.
- Name the protected contract and a mutation that breaks it in the report.
- Reject copied values, cosmetic snapshots, source substrings and mocks that reproduce implementation branches.
- Keep core specs hermetic: no network, installations or native tool execution.
- Restore resources and module caches even after failed assertions.
- Put fixtures below `vim.g.hangar_test_root` through `tests.helpers`.
- Reject skipped tests and uncaught editor errors through executed results.
- Run `just deps` once to clone the pinned Plenary, Nui and mini.doc sources into `.deps/`.
- Run `just all` before you finish. It checks the generated help and runs the core and integration specs.
- End the report with `Tests added`, `Tests updated` or `No tests added`, and its protected contract.

## CI

- Keep a CI check only when it catches a concrete failure that no existing check covers.
- Identify that failure before you add or keep the check.
- Apply the test rules to CI checks too.
- Run the repo's entry points against real inputs or isolated fixtures.
- Reject duplicate checks, source-text assertions, copied inventories and checks that only prove that a command or file exists.
- Name each workflow, job and step by its target and its action.
- Propagate command failures.
- Count a missing prerequisite or skipped required coverage as a failure.
- After you change these rules, audit the repo against them.
- Validate changes locally. Then verify the required CI on the pushed commit.
- Report each uncovered contract and each unavailable check.

## Docs

- Keep each doc concise and plain. Each sentence must carry information.
- Write English docs in US English, to the [ASD-STE100](https://www.asd-ste100.org/) writing rules:
  - Give one instruction in each sentence.
  - Write instructions in the imperative and in the active voice.
  - Use one word for one meaning, and one meaning for one word.
  - An instruction has 20 words or fewer. A description has 25 words or fewer.
- Review each sentence over these limits. Split it if it holds more than one instruction or fact. A list of items can stay in one sentence. Make a bullet list from more than five items.
- Write a non-English doc in two passes:
  1. Write an English draft to these rules.
  2. Translate the draft. Keep its sentence boundaries and one term for each concept. Keep commands, paths and code unchanged. Use the natural word order of the target language.
- Follow `.stylua.toml` and `.editorconfig`.
- Explain non-obvious behavior in comments.
- Document the public interface in annotation blocks with a `@tag`. Run `just doc` after you change one.
- Read [architecture](doc/architecture.md) before you change module boundaries or the setup options.
- Read the [guide](doc/guide.md) before you change user-visible behavior, persistence or layout.
