# Changelog

All notable changes to this package are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is defined once in `integrations/registry.json`; `scripts/validate-skill.ps1` fails if `SKILL.md`, `scripts/install.sh`, or this file disagree with it.

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
