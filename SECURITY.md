# Security Policy

## Supported versions

Security fixes are made to the latest commit on the default branch and to the latest tagged release. Older installed copies are not patched in place; reinstall from the fixed version. Each installed unit records its package version in a `.clean-code-refactor-install.json` receipt next to the installed files.

## Reporting a vulnerability

Report suspected vulnerabilities privately via GitHub security advisories for this repository ("Report a vulnerability" on the Security tab). If that is unavailable, open a minimal public issue asking for a private contact without including exploit details.

Include: affected file(s) and commit, reproduction steps, and impact. Do not include secrets or credentials in reports.

You will receive an acknowledgement within 7 days, and a fix or a documented risk-acceptance decision within 90 days for confirmed issues. Coordinated disclosure is requested: please allow a reasonable fix window before public disclosure.

## Scope

In scope: the installers (`scripts/install.ps1`, `scripts/install.sh`), the repository profiler (`scripts/profile-repository.ps1`), the validation script, the editor registry (`integrations/registry.json`), and instructions in this package that could cause an agent to take unsafe actions (for example, guidance that could be read as authorizing command execution or data exfiltration).

Out of scope: vulnerabilities in downstream applications reviewed with this skill, the runtime security of editor products, and GitHub platform issues. Reports about adversarial repository content should describe a concrete way the guidance or tooling leads to an unsafe action.

## Design commitments

- The package is local-first: no installer, validator, or profiler executes remote code or contacts external services.
- Installers write only to declared, contained destinations and refuse to traverse symlinks/junctions out of the selected root.
- Owned installed files are recorded with hashes in a receipt; user modifications are never silently overwritten.
- Guidance separates advisory controls from controls that require host-enforced sandboxing (see `references/agent-security.md`).
