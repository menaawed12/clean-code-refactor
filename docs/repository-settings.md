# Repository Security Settings

The workflows in `.github/workflows` enforce what they can from code. The settings below can only be changed by a repository administrator in GitHub. Apply them once, then re-check after GitHub adds new security features. Menu names follow GitHub's settings pages; confirm them against GitHub's documentation if a page has moved.

## Branch protection (Settings → Rules → Rulesets)

Create a branch ruleset targeting the default branch (`main`):

- **Restrict deletions** and **block force pushes**.
- **Require a pull request before merging.** With one maintainer, require 0 approvals but keep the pull request requirement, or add yourself to the bypass list; with two or more maintainers, require 1 approval, dismiss stale approvals on new pushes, and require review from code owners (`.github/CODEOWNERS`).
- **Require status checks to pass** and require branches to be up to date. Required checks, by the names these workflows report:
  - `windows`, `linux`, `macos`, `workflow-lint` (CI)
  - `Analyze (actions)`, `Analyze (python)` (CodeQL)
  - `dependency-review` (Dependency review)
- Optionally **require signed commits**.

Create a tag ruleset for `v*`:

- Restrict tag creation to maintainers, and block tag updates and deletions. Release tags trigger `.github/workflows/release.yml`, so only maintainers should be able to push them.

## Releases (Settings → General → Releases)

- Turn on **immutable releases** so published release assets and their tags cannot be changed afterwards. Combined with the build-provenance attestations, this lets consumers trust that a downloaded asset is the one CI built.

## Code security (Settings → Code security)

- **Dependency graph** and **Dependabot alerts**: on. Dependency review needs the dependency graph.
- **Dependabot security updates**: on. Version updates for GitHub Actions are configured in `.github/dependabot.yml`.
- **Secret scanning** and **push protection**: on, so commits containing credentials are blocked before they land.
- **Private vulnerability reporting**: on. `SECURITY.md` directs reporters to it.
- **Code scanning**: this repository uses the advanced setup in `.github/workflows/codeql.yml`. Leave CodeQL default setup off to avoid duplicate analyses.

## Actions (Settings → Actions → General)

- **Workflow permissions**: read repository contents only. Each workflow requests the extra permissions it needs per job.
- **Do not allow GitHub Actions to create or approve pull requests.**
- **Require approval for workflows from outside collaborators** (at least first-time contributors).
- **Allowed actions**: allow only actions from GitHub and from selected repositories (`ossf/scorecard-action`), and require actions to be pinned to a full-length commit SHA if that policy is available. Every workflow here already pins by SHA.

## Environments (Settings → Environments)

- Create an environment named `evals` for `.github/workflows/evals.yml`: restrict it to the `main` branch, require a maintainer's approval, and store the agent's API key there as the `ANTHROPIC_API_KEY` secret. Keeping the key in an environment, not in repository secrets, means pull requests cannot read it.

## Check the result

After changing settings, the Scorecard workflow (`.github/workflows/scorecard.yml`) re-scores the repository on the next push to `main` and weekly. Its results appear under Security → Code scanning and at `https://scorecard.dev/viewer/?uri=github.com/menaawed12/clean-code-refactor`.
