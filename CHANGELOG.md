# Changelog

All notable changes to this package are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is defined once in `integrations/registry.json`; `scripts/validate-skill.ps1` fails if `SKILL.md`, `scripts/install.sh`, or this file disagree with it.

## [1.2.0] - Unreleased

### Changed

- `SKILL.md` front matter follows the Agent Skills specification: adds `license` and `metadata.version`, makes `compatibility` describe environment requirements, and puts trigger phrases first in `description`. The language list moved into the Cross-Language Hardening section.
- `SKILL.md` tells agents that do not substitute `$ARGUMENTS` to use the user's request instead.
- `scripts/validate-skill.ps1` parses the front matter instead of matching one exact layout, enforces the specification's field names and length limits, and checks that the package version matches across the registry, `SKILL.md`, `scripts/install.sh`, and this changelog.

### Fixed

- The bash test suite passes ShellCheck, and its assertions can no longer record a pass and a fail for the same check.
- The PowerShell test suite no longer aborts on Linux and macOS while looking for Git Bash.

## [1.1.0]

### Added

- User-scope (global) installs for GitHub Copilot, Claude Code, Cursor, OpenCode, and Codex.
- Registry-driven installers for PowerShell and bash with install receipts, upgrade handling, dry runs, and JSON output.
- Repository profiler, policy profiles, agent trust-boundary guidance, and a structured review report.

## [1.0.0]

### Added

- Initial portable clean-code refactoring skill with language hardening and self-contained static quality rules.
