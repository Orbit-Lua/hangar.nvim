# AGENTS Instructions

Preserve the setup options, mappings and persisted state unless the task changes their contracts. Linux and Windows are equal targets.

## Git

- Write commits in [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) format.
- Start the type, the scope and the description in lowercase. Keep the case of code identifiers and proper nouns.
- For a non-trivial change, write a commit body that explains why.
- Mark a breaking change with `!` and a `BREAKING CHANGE:` footer.
- Author commits as the user alone. Add no agent trailers or links, such as `Co-Authored-By` or a session URL.
- Commit as the plan progresses.
- Before you push, squash related commits into one commit to keep the history clean.
- Push only after the user approves that push.

## Releases

- Version releases with [Semantic Versioning 2.0.0](https://semver.org/).
- Name each release tag with the `v` prefix and the version, such as `v1.2.3`.
- When you create a changelog, use [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) format. Keep the format of an existing changelog.
- Release in this order:
  1. Update the version references and the changelog in one commit, such as `chore(release): prepare v1.2.3`.
  2. Push the commit to the default branch.
  3. Wait until the branch pipeline of that commit passes.
  4. Tag that commit with an annotated tag: `git tag -a v1.2.3 -m "Release v1.2.3" <commit>`. Tag a release candidate as `v1.2.3-rc.1`.
  5. Push the tag alone: `git push origin v1.2.3`.
  6. Create the GitHub release from the tag. No tag pipeline exists yet.
- Push the commit and the tag in separate pushes. Do not use `git push --follow-tags`. One push starts two overlapping pipelines, and a single runner queues the tag pipeline.

## Code

- Read configuration only from the `setup()` options. Do not require a module of the configuration that uses hangar.
- Never pick, bundle or guess tools or Mason package names. The consumer configuration declares each tool.
- Gate only the tools that the consumer enabled. Never enable an LSP server or start Tree-sitter where the consumer did not.
- Give each integration an `integrations.<name>` switch. A disabled integration leaves its backend untouched.
- Apply an integration when its plugin loads. Make each apply idempotent, so a repeated setup replaces behavior without stacked wrappers.
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
- Pin each test and help dependency to a commit that exists on its remote.
- Exception: telemetry.nvim, the test reporter, tracks its default branch.
- Run `just deps` to clone the test dependencies into `.deps/` and update telemetry.nvim.
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
- Run the checks in branch pipelines only. A tag pipeline builds, smoke-tests and publishes the package, and then creates the release.
- Start each release job with a check that the tagged commit is on the default branch.
- Match release jobs to the tag format of the version, such as `v[0-9]+.[0-9]+.[0-9]+`.
- Protect the release tags. Only protected refs can read the release credentials.
- A tag pipeline uses the CI config of the tagged commit. Merge a CI change to the default branch before you tag.
- Run the checks in a workflow on `pull_request` and on `push` to branches.
- Run the release in a separate workflow on `push` of tags that match `v[0-9]+.[0-9]+.[0-9]+`. GitHub tag filters are globs, such as `v[0-9]+.[0-9]+.[0-9]+-*`.
- Check out release jobs with `fetch-depth: 0`, so that the ancestry check sees the default branch.
- Keep release secrets in an environment that allows only the release tags. Protect the tags with a tag ruleset.
- After you change these rules, audit the repo against them.
- Validate changes locally. Then verify the required CI on the pushed commit.
- Report each uncovered contract and each unavailable check.

## Docs

- Keep each doc concise and plain. Each sentence must carry information.
- Write only standing rules in `AGENTS.md`. A standing rule changes how an agent does later, unrelated tasks.
- Record a fact about one place or one failure at its source: a code comment, a test, a commit body, an ADR or an issue.
- Write English docs in US English, to the [ASD-STE100](https://www.asd-ste100.org/) writing rules:
  - Give one instruction in each sentence.
  - Write instructions in the imperative and in the active voice.
  - Use one word for one meaning, and one meaning for one word.
  - An instruction has 20 words or fewer. A description has 25 words or fewer.
- Review each sentence over these limits. Split it if it holds more than one instruction or fact.
- Use a numbered list for three or more instructions in a fixed order, also across sentences.
- Write a set of full-sentence items, or of more than five items, as a bullet list. Otherwise, the set can stay in one sentence, even when the sentence is over the limits.
- Write a non-English doc in two passes:
  1. Write an English draft to these rules.
  2. Translate the draft:
     1. Keep its sentence boundaries and one term for each concept.
     2. Keep commands, paths and code unchanged.
     3. Use the natural word order of the target language.
- Follow `.stylua.toml` and `.editorconfig`.
- Explain non-obvious behavior in comments.
- Document the public interface in annotation blocks with a `@tag`. Run `just doc` after you change one.
- Read [architecture](doc/architecture.md) before you change module boundaries or the setup options.
- Read the [guide](doc/guide.md) before you change user-visible behavior, persistence or layout.
