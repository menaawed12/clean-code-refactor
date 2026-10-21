# Install in Your AI Tool

This page gives the shortest install path for each AI tool. Commands assume a checkout of this repository (or an extracted `clean-code-refactor-<version>-package.zip`) and use the bash installer; the PowerShell installer takes the same targets (`.\scripts\install.ps1 -Editor <id> -TargetPath <project>`).

Tools fall into three groups:

- **Installed by the installers.** The installer writes the skill into the folder the tool reads. Pick the target id from the table below.
- **Installed as a package.** Claude Code can also install the skill as a plugin from this repository's marketplace.
- **Uploaded or pasted by hand.** Web and desktop chat apps (claude.ai, the Claude desktop app, ChatGPT) have no folder an installer can write to. `--bundle` / `-BundlePath` writes upload-ready files for them.

## Quick reference

| Tool | How to install | Target id or file |
| --- | --- | --- |
| Claude Code | Installer, or the plugin marketplace | `claude` (project or `--scope user`) |
| claude.ai and the Claude desktop app | Upload the skill zip | `--bundle` → `clean-code-refactor-<version>.zip` |
| ChatGPT skills | Upload the skill zip | `--bundle` → `clean-code-refactor-<version>.zip` |
| ChatGPT custom GPT or project | Paste instructions, attach files | `--bundle` → `chatgpt-instructions.md` |
| Codex CLI, Codex IDE extension, Codex cloud | Installer | `agents` (writes `AGENTS.md` and `.agents/skills/`) |
| VS Code with GitHub Copilot | Installer | `copilot` (or `agents`) |
| Visual Studio with GitHub Copilot | Installer | `copilot` (`.github/copilot-instructions.md` pointer) |
| Cursor | Installer | `cursor` |
| Windsurf | Installer | `windsurf` |
| OpenCode | Installer | `opencode` (project or `--scope user`) |
| Gemini CLI | Installer | `agents` |
| JetBrains IDEs with Junie, Junie CLI | Installer | `junie` (project or `--scope user`) |
| Cline, Roo Code, Continue, Amazon Q Developer, Kilo Code | Installer | `cline`, `roo`, `continue`, `amazonq`, `kilo` |
| Zed | Installer | `agents` (Zed reads the `AGENTS.md` pointer) |
| Aider | Point Aider at the skill | `--read` (see below) |

`docs/ide-compatibility.md` lists the exact folders each target writes and which destinations are confirmed against vendor documentation.

## Claude Code

Install into one project, or for every project on the machine:

```bash
bash ./scripts/install.sh --editor claude --target /path/to/project
bash ./scripts/install.sh --editor claude --scope user
```

Or install it as a plugin. This repository is its own plugin marketplace (`.claude-plugin/marketplace.json`), and the plugin is the skill at the repository root. In Claude Code:

```text
/plugin marketplace add menaawed12/clean-code-refactor
/plugin install clean-code-refactor@clean-code-refactor
```

From a shell, the same steps are `claude plugin marketplace add menaawed12/clean-code-refactor` and `claude plugin install clean-code-refactor@clean-code-refactor`. Plugin updates follow the `version` in `.claude-plugin/plugin.json`, which `scripts/validate-skill.ps1` keeps equal to the package version. Use either the installer or the plugin, not both, or the skill appears twice.

## claude.ai and the Claude desktop app

Build the upload files, then upload the zip:

```bash
bash ./scripts/install.sh --bundle ./dist
```

```powershell
.\scripts\install.ps1 -BundlePath .\dist
```

1. Open **Settings → Capabilities** and make sure code execution and file creation is on (skills need it).
2. Under **Skills**, choose **Upload skill** and select `dist/clean-code-refactor-<version>.zip`.
3. Turn the skill on. Claude uses it when a request matches its description, or ask for it by name.

The zip holds one `clean-code-refactor/` folder with `SKILL.md`, `references/`, and the read-only profiler scripts. Every [GitHub release](https://github.com/menaawed12/clean-code-refactor/releases) also ships the same layout as `clean-code-refactor-<version>.zip`, with checksums and provenance attestations. Menu names change between app versions; if yours differ, follow Anthropic's current help article on using skills.

## ChatGPT

**Skills (plans that offer them).** ChatGPT skills use the same `SKILL.md` folder format. Where your workspace has skills turned on, upload `dist/clean-code-refactor-<version>.zip` from the skills page and install it. Availability depends on your plan and workspace settings, and the upload location has moved between releases, so confirm it against OpenAI's current help article.

**Custom GPT or project (any plan).** ChatGPT cannot read files from your disk, so the skill is pasted:

1. Run `--bundle` as above, or open [`integrations/chatgpt/instructions.md`](../integrations/chatgpt/instructions.md) directly.
2. For a custom GPT, open **Explore GPTs → Create → Configure**. Paste the whole of `chatgpt-instructions.md` into **Instructions** (it stays under the 8,000-character limit; validation checks this). For a project, paste it into the project's **Instructions**.
3. Under **Knowledge** (custom GPT) or **Files** (project), upload `SKILL.md` and every file in `references/` from `dist/clean-code-refactor/`. The instructions tell ChatGPT to consult them.

A pasted copy does not update itself. The first line of the file names its version; repeat these steps after upgrading. ChatGPT cannot run your linters or tests, so the instructions tell it to list the checks for you to run instead of claiming they passed.

**Codex.** Codex in ChatGPT, the Codex CLI, and the Codex IDE extension read `AGENTS.md` and `.agents/skills/` from the repository. Install the `agents` target into the repository and commit the result:

```bash
bash ./scripts/install.sh --editor agents --target /path/to/project
```

## VS Code and Visual Studio

GitHub Copilot in VS Code reads skills from `.github/skills/` and `.agents/skills/`, and instructions from `.github/copilot-instructions.md`. The `copilot` target writes the skill folder and adds a marked pointer section to `copilot-instructions.md`:

```bash
bash ./scripts/install.sh --editor copilot --target /path/to/project
bash ./scripts/install.sh --editor copilot --scope user   # ~/.copilot/skills/
```

Visual Studio's Copilot reads `.github/copilot-instructions.md`, so the same `copilot` target reaches it through the pointer. Other VS Code extensions have their own targets: Cline (`cline`), Roo Code (`roo`), Continue (`continue`), Amazon Q Developer (`amazonq`), and Kilo Code (`kilo`). VS Code forks such as VSCodium may not ship Copilot; use the target for the agent extension you run there.

## OpenCode

```bash
bash ./scripts/install.sh --editor opencode --target /path/to/project
bash ./scripts/install.sh --editor opencode --scope user   # $XDG_CONFIG_HOME/opencode/skills/
```

## Cursor, Windsurf, and Gemini CLI

```bash
bash ./scripts/install.sh --editor cursor --target /path/to/project
bash ./scripts/install.sh --editor windsurf --target /path/to/project
bash ./scripts/install.sh --editor agents --target /path/to/project   # Gemini CLI reads .agents/skills/
```

## JetBrains IDEs (Junie)

Junie, in IntelliJ IDEA, PyCharm, WebStorm, GoLand, and the other JetBrains IDEs, and the Junie CLI read agent skills from `.junie/skills/` in the project and in your home directory:

```bash
bash ./scripts/install.sh --editor junie --target /path/to/project
bash ./scripts/install.sh --editor junie --scope user   # ~/.junie/skills/
```

The user-scope destination is marked `verify-against-docs`; confirm it for your Junie version.

## Zed

Zed's agent reads one rules file from the project root, and `AGENTS.md` is one it accepts. Install the `agents` target; its `AGENTS.md` pointer directs the agent to `.agents/skills/clean-code-refactor/SKILL.md`. If the project already has a `.rules` file, Zed reads that first, so add the same pointer line there.

## Aider

Aider loads extra read-only context files with `--read`:

```bash
bash ./scripts/install.sh --editor agents --target /path/to/project
aider --read .agents/skills/clean-code-refactor/SKILL.md
```

To load it every time, add it to `.aider.conf.yml`:

```yaml
read:
  - .agents/skills/clean-code-refactor/SKILL.md
```

## Checking an install

`--verify` (bash) and `-Verify` (PowerShell) confirm that installed copies match the package. Uploaded and pasted copies cannot be verified this way; compare the version on the first line of the pasted instructions or the `version` in the uploaded `SKILL.md` with the current release instead.
