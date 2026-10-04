# IDE and Agent Compatibility

This file summarizes `integrations/registry.json` — the machine-readable source of truth the installers read. The registry models the **IDE + agent + scope** combination; the table below is documentation, not a support claim beyond what the registry declares.

Statuses:

- **supported** — installer writes the declared destination; format-level behavior covered by the behavioral test suite.
- **verify-against-docs** — the destination follows the vendor's documented user-level location, but you should confirm it against your installed version's documentation before relying on it.
- **planned / manual / unsupported** — declared in the roadmap, installed by hand, or not available. These are never written by the installer; `-Editor detected` and `-Editor all` only touch declared entries.

## Declared targets (this release)

| Editor / agent | Project scope | User scope | Rule format |
| --- | --- | --- | --- |
| agents (shared `.agents/skills` standard) | `.agents/skills/clean-code-refactor/` + `AGENTS.md` pointer | `~/.agents/skills/clean-code-refactor/` | skill folder |
| Cursor | `.cursor/rules/clean-code-refactor.mdc` | `~/.cursor/skills/clean-code-refactor/` (verify-against-docs) | Cursor `.mdc` rule |
| GitHub Copilot | `.github/skills/clean-code-refactor/` + `.github/copilot-instructions.md` pointer | `~/.copilot/skills/clean-code-refactor/` (verify-against-docs) | skill folder |
| Claude Code | `.claude/skills/clean-code-refactor/` | `~/.claude/skills/clean-code-refactor/` (verify-against-docs) | skill folder |
| Codex CLI | — (use `agents`) | `$CODEX_HOME` or `~/.codex/skills/clean-code-refactor/` (deprecated upstream; prefer `agents`) | skill folder |
| Windsurf | `.windsurf/rules/clean-code-refactor.md` | — | Markdown rule |
| Cline | `.clinerules/clean-code-refactor.md` | — | Markdown rule |
| Roo Code | `.roo/rules/clean-code-refactor.md` | — | Markdown rule |
| Continue | `.continue/rules/clean-code-refactor.md` | — | Markdown rule (front matter) |
| Amazon Q Developer | `.amazonq/rules/clean-code-refactor.md` | — | Markdown rule |
| OpenCode | `.opencode/skills/clean-code-refactor/` | `$XDG_CONFIG_HOME` or `~/.config/opencode/skills/clean-code-refactor/` (verify-against-docs) | skill folder |
| Kilo Code | `.kilo/rules/clean-code-refactor.md` + `kilo.jsonc` entry | — | Markdown rule |

## Choosing a target

Several agents now read the shared `.agents/skills/` folders, so one `agents` install covers them:

| Agent | Project folders read | User folders read | Source (checked 2026-10-04) |
| --- | --- | --- | --- |
| Codex CLI | `.agents/skills/` (from the working directory up to the repository root) and `.codex/skills/` | `~/.agents/skills/`; `$CODEX_HOME/skills/` is deprecated but still read | Codex source code (`codex-rs/ext/skills/src/host_roots.rs`) |
| Gemini CLI | `.gemini/skills/` or the `.agents/skills/` alias | `~/.gemini/skills/` or the `~/.agents/skills/` alias | Gemini CLI documentation (`docs/cli/skills.md`) |
| Cursor | `.cursor/skills/`, `.agents/skills/`, and for compatibility `.claude/skills/` and `.codex/skills/` | the same folders under `~` | Cursor documentation (cursor.com/docs/skills), via search summary |
| GitHub Copilot in VS Code | `.github/skills/`, `.agents/skills/` | `~/.copilot/skills/`, `~/.agents/skills/` | VS Code agent-skills documentation (checked 2026-09-08) |

Install into as few locations as your agents need. Because agents such as Cursor also read other agents' folders, installing several targets can make the same skill appear more than once; `--editor all` is meant for evaluation and broad setups, not for everyday use.

## What is verified

User-scope destinations for GitHub Copilot (`~/.copilot/skills/`), Claude Code (`~/.claude/skills/`), and the shared `~/.agents/skills/` location are confirmed against the official VS Code agent-skills documentation (checked 2026-09-08). The `~/.agents/skills/` and `.agents/skills/` locations are also confirmed for Codex from its source code and for Gemini CLI from its documentation (checked 2026-10-04). The behavioral test suite (`tests/`) verifies installer output: files land at the declared destinations, generated links resolve, upgrades replace owned content without leaving stale or nested files, user modifications are protected, dry-run writes nothing, and destinations cannot be redirected outside the selected root through symlinks. **File-copy success is not evidence that an editor loaded a skill.** Loading, activation, and precedence must be confirmed per editor version against its official documentation before being claimed; report any gap you observe rather than assuming support.

## Roadmap (not installed by this release)

The following families are planned or manual-workflow targets; none have declared destinations in the registry yet, and none are written by `-Editor all`:

- JetBrains IDEs (IntelliJ IDEA, PyCharm, WebStorm, PhpStorm, Rider, GoLand, CLion, RubyMine, RustRover, DataGrip, Android Studio) via AI Assistant/Junie skill import — planned, certified per IDE and plugin version.
- Visual Studio (Copilot/agent customization) — planned; manual CLI fallback meanwhile.
- Zed (personal instructions) — planned.
- VS Code forks (VSCodium, Code-OSS) — manual; do not assume Copilot availability or identical paths.
- Other editors (Sublime Text, Notepad++, Vim/Neovim, Emacs, Helix, Kate, Geany, Eclipse, Theia, NetBeans, Qt Creator, RStudio/Positron, JupyterLab) — documented plugin or terminal workflow.
- Browser/remote IDEs (Codespaces, Gitpod, code-server, cloud workspaces) — install inside the actual agent execution environment; remote hosts are separate installation contexts.
- Terminal agents (Claude Code, Codex, Copilot CLI, OpenCode, Gemini CLI, Amazon Q, Aider) — covered where a native user-level destination is declared above. Gemini CLI is covered by the `agents` target.
- Windsurf skill folders — Windsurf's documentation describes native skill folders. The `windsurf` target still installs a rule file until those locations are confirmed from a primary source.

Additional IDEs can be added by extending `integrations/registry.json` and running `pwsh ./scripts/sync-bash-installer.ps1`. The PowerShell installer reads the registry directly; `scripts/validate-skill.ps1` fails if the bash installer's generated tables are out of date.
