# Clean Code Refactor Skill

A portable Cursor skill for behavior-preserving refactoring, lint remediation, duplicate detection, and secure, maintainable code across major languages.

## Contents

- `.cursor/skills/clean-code-refactor/SKILL.md` — the Cursor skill.
- `.cursor/skills/clean-code-refactor/references/language-hardening.md` — language and runtime-specific review guidance.
- `scripts/validate-skill.ps1` — validates the package structure and required instructions.

## Install

Copy the repository's `.cursor` directory into the root of a target project, preserving its structure. Merge with that project's existing `.cursor` directory if it already has one.

Keep project-specific architecture, test commands, and deployment rules in separate project rules. This skill discovers and obeys those local conventions rather than replacing them.

## Use

Select `clean-code-refactor` in Cursor, then provide the scope and intent, for example:

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
