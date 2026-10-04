# Clean Code Refactor Skill

A portable AI coding skill for behavior-preserving refactoring, lint remediation, duplicate detection, and secure, maintainable code across major languages.

## Language Support

The skill applies universal security, reliability, maintainability, lint, duplicate-detection, and test-quality rules to every language. It also provides dedicated hardening guidance for these major ecosystems:

| Ecosystem | Languages and artifacts |
| --- | --- |
| Web and application | Python, JavaScript, TypeScript, PHP, Ruby, Java, Kotlin, Scala, C#, F#, Visual Basic, and .NET |
| Systems and Apple platforms | C, C++, Objective-C, Rust, Go, and Swift |
| Mobile and UI | Dart and Flutter |
| Functional and concurrent | Elixir, Erlang, Clojure, and Haskell |
| Scripting and data | Bash, PowerShell, Perl, Lua, R, Julia, SQL, JSON, YAML, and TOML |
| Delivery and infrastructure | Dockerfiles, CI/CD definitions, Terraform/HCL, Kubernetes manifests, and other infrastructure-as-code |

For languages not listed above, the skill uses its universal rules, the repository's pinned toolchain, configured checks, and matching-version official guidance. It does not assume that an idiom from one language is safe or idiomatic in another.

## Advanced Capabilities

- Local, read-only repository profiling to detect language, framework, configured checks, delivery assets, and high-risk change signals.
- Policy profiles for strict, legacy-safe, API service, frontend, mobile, data, infrastructure, and AI application work.
- Change-impact analysis for public APIs, consumers, events, schemas, migrations, caches, and third-party integrations.
- Framework-aware hardening for major web, backend, mobile, and infrastructure ecosystems.
- Risk-based quality gates for authentication, authorization, secrets, payments, PII, public endpoints, migrations, concurrency, and delivery changes.
- Test-quality, performance, resilience, dependency, license, artifact, and supply-chain review rules.
- A severity-based, structured review report that records evidence, verification, exceptions, and residual risk, with CWE and OWASP tags and optional SARIF 2.1.0 output for code-scanning tools.
- AI application guidance: untrusted model input and output, per-call tool authorization, MCP server hardening, bounded agent loops and spend, and evaluation before prompt or model changes.
- Current supply-chain checks, including verifying that new package names are real (typosquatting and "slopsquatting"), dependency confusion, SHA-pinned CI, provenance, and SBOMs.
- WCAG 2.2 AA checks for changed UI.

Profile a target repository before non-trivial work. The bash and PowerShell profilers report the same results, and the test suite checks that they agree:

```bash
bash ./scripts/profile-repository.sh --path /path/to/project
```

```powershell
.\scripts\profile-repository.ps1 -Path C:\path\to\project
```

## Contents

- `SKILL.md` — canonical portable skill instructions.
- `references/language-hardening.md` — language and runtime-specific review guidance.
- `references/static-quality-rules.md` — self-contained static quality, security, reliability, and maintainability rules.
- `references/policy-and-framework-guidance.md` — policy profiles and framework-aware review guidance.
- `references/api-and-data-safety.md` — API, schema, migration, query, event, cache, and integration safety rules.
- `references/test-performance-and-supply-chain.md` — test quality, performance, resilience, and dependency guidance.
- `references/structured-review-report.md` — severity-based review-report format.
- `references/ai-and-agent-code.md` — rules for code that calls language models, builds prompts, retrieves context, or exposes tools and MCP servers to agents.
- `references/standards-mapping.md` — maps findings to OWASP Top 10:2025, CWE Top 25 (2025), OWASP LLM and Agentic Top 10, ASVS 5.0, NIST SSDF, SLSA v1.2, and WCAG 2.2 identifiers.
- `references/agent-security.md` — agent trust boundaries: untrusted repository content, tool-output injection, command discovery versus execution, and scoped permissions.
- `integrations/registry.json` — machine-readable editor/agent target registry (single source of truth for installers).
- `docs/ide-compatibility.md` — human-readable compatibility summary and roadmap.
- `SECURITY.md` — vulnerability reporting route and design commitments.
- `CHANGELOG.md` — release history; the version itself lives in `integrations/registry.json`.
- `scripts/validate-skill.ps1` — validates package structure, links, registry/installer parity, and required instructions.
- `scripts/check-policy.ps1` and `policy/` — organization and project policy validation, schema, and example.
- `scripts/sync-bash-installer.ps1` — regenerates the bash installer's copy of the registry; run it after editing `integrations/registry.json`.
- `scripts/install.ps1` — registry-driven installer (Windows PowerShell).
- `scripts/install.sh` — registry-parity Bash installer for macOS and Linux.
- `scripts/profile-repository.ps1`, `scripts/profile-repository.sh` — bounded, read-only repository profilers (PowerShell and bash 3.2+) with evidence and confidence reporting. Neither follows symlinks or reads symlinked manifests.
- `tests/run-tests.ps1`, `tests/install.sh.tests.sh` — behavioral installer test suites.
- `evals/` — behavioral evals that measure whether an agent does better work with the skill than without it; see [evals/README.md](evals/README.md).

## Install

Choose the installation method that fits your environment. All methods use the same canonical `SKILL.md`, references, and local profiler; none executes remote code.

### 1. Windows PowerShell

```powershell
.\scripts\install.ps1 -Editor all -TargetPath C:\path\to\project
```

### 2. macOS or Linux Bash

```bash
bash ./scripts/install.sh --editor all --target /path/to/project
```

### 3. Install one editor only

Use either installer with a specific target. This is useful for a project that uses one coding agent:

```powershell
.\scripts\install.ps1 -Editor opencode -TargetPath C:\path\to\project
```

```bash
bash ./scripts/install.sh --editor cursor --target /path/to/project
```

### 4. Git clone, then install

Use a normal Git checkout when you want to inspect or pin the source before installation:

```bash
git clone https://github.com/menaawed12/clean-code-refactor.git
cd clean-code-refactor
bash ./scripts/install.sh --editor all --target /path/to/project
```

### 5. Manual or air-gapped installation

Each [GitHub release](https://github.com/menaawed12/clean-code-refactor/releases) ships `clean-code-refactor-<version>.zip`, the ready-to-copy skill folder, with a `SHA256SUMS` file and a signed build-provenance attestation. Verify a download before installing it:

```bash
sha256sum --check --ignore-missing SHA256SUMS
gh attestation verify clean-code-refactor-<version>.zip --repo menaawed12/clean-code-refactor
```

Alternatively, download or transfer a reviewed copy of this repository, then copy `SKILL.md`, `references/`, `scripts/profile-repository.ps1`, and `scripts/profile-repository.sh` to the editor location in the table below. For rule-based editors, use the PowerShell or Bash installer from the reviewed local copy to generate the required rule file and supporting folders. This supports environments without internet access or where installation scripts must be reviewed before use.

Supported editor integrations are declared in `integrations/registry.json` and summarized in [docs/ide-compatibility.md](docs/ide-compatibility.md). Both installers are validated against the registry; they cannot drift apart.

| Editor or agent | Installed format |
| --- | --- |
| Cursor | `.cursor/rules/clean-code-refactor.mdc` |
| GitHub Copilot | `.github/skills/clean-code-refactor/` plus `.github/copilot-instructions.md` pointer for editor-wide support |
| Claude Code | `.claude/skills/clean-code-refactor/` |
| Codex | `$CODEX_HOME/skills/clean-code-refactor/` or `~/.codex/skills/clean-code-refactor/` |
| Shared agent standard (read by Codex, Gemini CLI, Cursor, and GitHub Copilot) | `.agents/skills/clean-code-refactor/` plus a root `AGENTS.md` pointer; user scope `~/.agents/skills/clean-code-refactor/` |
| Windsurf | `.windsurf/rules/clean-code-refactor.md` |
| Cline | `.clinerules/clean-code-refactor.md` |
| Roo Code | `.roo/rules/clean-code-refactor.md` |
| Continue | `.continue/rules/clean-code-refactor.md` |
| Amazon Q Developer | `.amazonq/rules/clean-code-refactor.md` |
| OpenCode | `.opencode/skills/clean-code-refactor/` |
| Kilo Code | `.kilo/rules/clean-code-refactor.md` and a `kilo.jsonc` `instructions` entry |

### Organization policy

Administrators can install an organization policy next to the skill so every repository gets the same gates:

```bash
bash ./scripts/install.sh --editor agents,claude --target /path/to/project --policy ./org-policy.json
```

```powershell
.\scripts\install.ps1 -Editor agents,claude -TargetPath C:\path\to\project -PolicyFile .\org-policy.json
```

The policy sets coverage and duplication thresholds, blocking severities, ASVS and WCAG levels, banned APIs, allowed dependency registries, exception-ticket rules, and SARIF reporting. Start from [policy/policy.example.json](policy/policy.example.json); [policy/policy.schema.json](policy/policy.schema.json) gives editors completion and validation. A repository can add `.clean-code-refactor/policy.json` to tighten the rules further, but never to loosen them. Check the effective policy, for example in CI, with:

```powershell
pwsh ./scripts/check-policy.ps1 -ProjectPath /path/to/project -OrgPolicyPath ./org-policy.json
```

### Options and behavior

Both installers support the same options (PowerShell spelling shown; Bash uses the long forms):

```powershell
.\scripts\install.ps1 -Editor cursor -TargetPath C:\path\to\project   # one editor, project scope
.\scripts\install.ps1 -Editor all -TargetPath C:\path\to\project      # every registry target
.\scripts\install.ps1 -Editor detected -TargetPath C:\path\to\project # only editors already configured
.\scripts\install.ps1 -Scope user -UserHome $HOME -WhatIf             # plan a per-user global install
.\scripts\install.ps1 -Editor codex -List                             # list registry targets
.\scripts\install.ps1 -Editor all -OutputFormat Json                  # machine-readable plan/result
```

```bash
bash ./scripts/install.sh --editor cursor --target /path/to/project
bash ./scripts/install.sh --scope user --editor claude,cursor,opencode,codex --dry-run
bash ./scripts/install.sh --editor codex   # user-scoped by default
```

- **Exit codes:** `0` success (intentional skips allowed), `1` one or more targets failed, `2` usage or preflight error. Preflight failures abort before anything is written.
- **Upgrades:** installs record a `.clean-code-refactor-install.json` receipt with version and file hashes. A re-run updates owned files, removes files the package no longer ships (including nested leftovers), and preserves unrelated files. Without `-Force`/`--force` your modifications to owned files are detected and preserved; use force to overwrite.
- **Safety:** destinations must resolve inside the declared root; symlinked or junctioned path components are refused, and a failed preflight leaves the filesystem untouched.
- **User scope:** available where the registry declares it (the shared `agents` standard, GitHub Copilot, Claude Code, Cursor, OpenCode, Codex). For most setups, `--scope user --editor agents` plus your agent's own target is enough; see [docs/ide-compatibility.md](docs/ide-compatibility.md) for which agents read which folders. Redirect homes with `-UserHome`/`--user-home` (and `-CodexHome`/`--codex-home`) for tests or portable installs. Destinations marked `verify-against-docs` should be confirmed against your installed editor's documentation. Global availability never implies automatic execution or elevated privileges.

Use `-Force` or `--force` only when replacing this skill's previously installed files. The installers never overwrite unrelated instructions.

Keep project-specific architecture, test commands, and deployment rules in separate project rules. This skill discovers and obeys those local conventions rather than replacing them.

## Use

Invoke `clean-code-refactor` in your installed coding agent, then provide the scope and intent, for example:

```text
Refactor the payment service to remove duplication. Preserve its public API and add regression tests.
```

```text
Review the changed TypeScript files for lint, duplicate code, security, and reliability issues; address findings in scope.
```

## Validate

```powershell
.\scripts\validate-skill.ps1
```

Validation checks the `SKILL.md` front matter against the Agent Skills specification (allowed fields, name format, length limits), keeps the package version identical across the registry, `SKILL.md`, the bash installer, and `CHANGELOG.md`, checks required files and sections, resolves every relative Markdown link in the package, verifies the rule-body path transformation produces no double-prefixed or broken links, and fails when the registry and either installer drift apart.

## Test

Behavioral suites exercise the installers end-to-end in disposable directories (fresh install, idempotent re-run, unmanaged-install protection, forced upgrades that remove stale and nested files, user-modification protection, dry-run, usage errors, paths with spaces and Unicode, symlink containment, user scope with redirected homes, and JSON output):

```powershell
.\tests\run-tests.ps1          # PowerShell suite; also runs the bash suite when bash is available
```

```bash
bash ./tests/install.sh.tests.sh
```

GitHub Actions CI (`.github/workflows/ci.yml`) runs validation on Windows PowerShell 5.1 and PowerShell 7, the PowerShell suite on Windows and Linux, the bash suite on Linux and macOS, ShellCheck, PSScriptAnalyzer (rules and exclusions in `PSScriptAnalyzerSettings.psd1`), and actionlint plus zizmor for the workflows themselves. It runs with read-only permissions and no secrets, actions are pinned to commit SHAs and updated by Dependabot, and linters are pinned to exact versions.

## Release

1. Set the new version in `integrations/registry.json` and `SKILL.md` (`metadata.version`), then run `pwsh ./scripts/sync-bash-installer.ps1` to carry it into `scripts/install.sh`. `scripts/validate-skill.ps1` fails until they all match.
2. Add a dated `## [<version>] - YYYY-MM-DD` entry to `CHANGELOG.md`.
3. Push a `v<version>` tag. `.github/workflows/release.yml` checks that the tag, registry, and changelog agree, validates the package, and publishes the release assets with checksums and provenance attestations.

## Security

Local-first by design: no installer, validator, or profiler executes remote code or contacts external services. Destinations are contained and refuse symlink redirection; installed files are recorded with hashes. Vulnerability reporting and design commitments: see [SECURITY.md](SECURITY.md). Agent trust-boundary guidance for untrusted repositories: see [references/agent-security.md](references/agent-security.md).
