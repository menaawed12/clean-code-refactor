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

## Contents

- `SKILL.md` — canonical portable skill instructions.
- `references/language-hardening.md` — language and runtime-specific review guidance.
- `references/static-quality-rules.md` — self-contained static quality, security, reliability, and maintainability rules.
- `scripts/validate-skill.ps1` — validates the package structure and required instructions.
- `scripts/install.ps1` — installs the skill in an editor-specific project format.

## Install

Use the installer from this repository to add the skill to a target project:

```powershell
.\scripts\install.ps1 -Editor all -TargetPath C:\path\to\project
```

Supported editor integrations:

| Editor or agent | Installed format |
| --- | --- |
| Cursor | `.cursor/rules/clean-code-refactor.mdc` |
| GitHub Copilot | `.github/skills/clean-code-refactor/` plus `.github/copilot-instructions.md` pointer for editor-wide support |
| Claude Code | `.claude/skills/clean-code-refactor/` |
| Codex | `$CODEX_HOME/skills/clean-code-refactor/` or `~/.codex/skills/clean-code-refactor/` |
| Shared agent standard | `.agents/skills/clean-code-refactor/` plus a root `AGENTS.md` pointer |
| Windsurf | `.windsurf/rules/clean-code-refactor.md` |
| Cline | `.clinerules/clean-code-refactor.md` |
| Roo Code | `.roo/rules/clean-code-refactor.md` |
| Continue | `.continue/rules/clean-code-refactor.md` |
| Amazon Q Developer | `.amazonq/rules/clean-code-refactor.md` |
| OpenCode | `.opencode/skills/clean-code-refactor/` |
| Kilo Code | `.kilo/rules/clean-code-refactor.md` and a `kilo.jsonc` `instructions` entry |

`-Editor all` installs every project-local integration. Install Codex separately because its native skill location is user-scoped:

```powershell
.\scripts\install.ps1 -Editor codex
```

Use `-Force` only when replacing this skill's previously installed files. The installer does not overwrite unrelated instructions.

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
