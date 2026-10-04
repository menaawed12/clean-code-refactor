# Changelog

All notable changes to this package are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is defined once in `integrations/registry.json`; `scripts/validate-skill.ps1` fails if `SKILL.md`, `scripts/install.sh`, or this file disagree with it.

## [1.3.0] - Unreleased

### Added

- `scripts/profile-repository.sh`: a bash 3.2+ and POSIX awk port of the repository profiler for macOS, Linux, and Git Bash, with the same bounds, signals, and JSON shape as `profile-repository.ps1`. The PowerShell suite checks that both profilers report identical results. Both installers ship it, and `SKILL.md` offers both commands.
- `scripts/sync-bash-installer.ps1` generates the bash installer's copy of the registry (version, tool list, editor ids, and both target tables). The validator runs it in check mode, so drift in any column now fails validation; before, only some columns were compared.
- `.gitattributes` keeps shell scripts LF-only so they run from Windows checkouts.
- `references/ai-and-agent-code.md`: rules for code that calls language models, builds prompts, retrieves context, or exposes tools and MCP servers to agents, tagged with OWASP LLM 2025 and Agentic 2026 identifiers. A matching `ai-application` policy profile.
- `references/standards-mapping.md`: maps the skill's rule areas to OWASP Top 10:2025, CWE Top 25 (2025), OWASP LLM and Agentic Top 10, ASVS 5.0, NIST SSDF, SLSA v1.2, and WCAG 2.2.
- The structured review report tags security findings with CWE and OWASP identifiers and can also be emitted as SARIF 2.1.0.
- Supply-chain guidance covers verifying that new package names are real (typosquatting and "slopsquatting"), dependency confusion, lockfile integrity, SHA-pinned CI, provenance, and SBOMs.
- The `frontend` profile requires WCAG 2.2 AA for changed UI and lists the success criteria added in 2.2.

- `evals/`: seven behavioral eval cases (SQL injection, duplication, scope discipline, planted repository instructions, model output reaching a shell, public API preservation, and test quality) with hidden tests, reference solutions, a grader, and a runner that compares an agent with and without the skill. CI runs the self-test, which proves every check fails on the untouched fixture or passes as declared, and passes on the reference solution.
- A user-scope `agents` target (`~/.agents/skills/clean-code-refactor/`), read by Codex and Gemini CLI (confirmed from their source and documentation) and by Cursor and GitHub Copilot.

### Changed

- `docs/ide-compatibility.md` records which agents read which skill folders, with sources, and notes that Codex has deprecated `$CODEX_HOME/skills` in favor of `~/.agents/skills`.
- Registry schema version 2: `package.toolSources` lists every shipped tool script, replacing `profilerSource` and `ruleFileLayout.profilerFileName`.

### Fixed

- The PowerShell profiler emitted `null` for empty lists and a bare string for single-item lists instead of JSON arrays.
- Both profilers reported a scan as complete when the file limit cut it short in the last directory walked.

### Security

- Neither profiler reads a symlinked manifest, so a repository cannot point the profiler at files outside it. Such files are reported as `symlinked manifest not read`.

## [1.2.0] - Unreleased

### Changed

- `SKILL.md` front matter follows the Agent Skills specification: adds `license` and `metadata.version`, makes `compatibility` describe environment requirements, and puts trigger phrases first in `description`. The language list moved into the Cross-Language Hardening section.
- `SKILL.md` tells agents that do not substitute `$ARGUMENTS` to use the user's request instead.
- `scripts/validate-skill.ps1` parses the front matter instead of matching one exact layout, enforces the specification's field names and length limits, and checks that the package version matches across the registry, `SKILL.md`, `scripts/install.sh`, and this changelog.

### Added

- Release workflow (`.github/workflows/release.yml`): a `v<version>` tag publishes the skill folder as a zip with `SHA256SUMS` and signed build-provenance attestations, after checking that the tag, registry version, and a dated changelog entry agree.
- Workflow linting in CI with actionlint and zizmor, and Dependabot updates for GitHub Actions.
- `PSScriptAnalyzerSettings.psd1`, shared by CI and editors, with the reason for each excluded rule.

### Security

- CI pins `actions/checkout` to a commit SHA (v7.0.1, Node 24), does not persist credentials, and adds job timeouts and concurrency limits. PSScriptAnalyzer, actionlint, and zizmor are pinned to exact versions.

### Fixed

- The bash test suite passes ShellCheck, and its assertions can no longer record a pass and a fail for the same check.
- The PowerShell test suite no longer aborts on Linux and macOS while looking for Git Bash.
- CI now fails on PSScriptAnalyzer warnings as well as errors. The fixes: test code no longer assigns to the automatic `$profile` variable, empty catch blocks now state their intent, internal functions use approved verbs and singular nouns, and `tests/run-tests.ps1` is saved with a UTF-8 BOM so Windows PowerShell 5.1 reads its Unicode test path correctly.
- The Linux CI job no longer runs the bash suite twice.
- Both test suites unset `XDG_CONFIG_HOME` before running, so user-scope install tests stay inside their redirected home on hosts that set it, such as GitHub's Ubuntu runners, instead of failing and writing to the real config directory.

## [1.1.0]

### Added

- User-scope (global) installs for GitHub Copilot, Claude Code, Cursor, OpenCode, and Codex.
- Registry-driven installers for PowerShell and bash with install receipts, upgrade handling, dry runs, and JSON output.
- Repository profiler, policy profiles, agent trust-boundary guidance, and a structured review report.

## [1.0.0]

### Added

- Initial portable clean-code refactoring skill with language hardening and self-contained static quality rules.
