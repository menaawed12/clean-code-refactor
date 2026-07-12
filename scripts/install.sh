#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [options]

Options:
  -e, --editor NAME     Install target: all, agents, cursor, copilot, claude, codex,
                        windsurf, cline, roo, continue, amazonq, opencode, or kilo.
                        Repeat the option or use a comma-separated list.
  -t, --target PATH     Target project directory (default: current directory).
      --codex-home PATH Codex home directory (default: $CODEX_HOME or ~/.codex).
  -f, --force           Replace this skill's existing installed files.
  -h, --help            Show this help.
EOF
}

editors=()
target_path="$(pwd)"
codex_home="${CODEX_HOME:-$HOME/.codex}"
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--editor) editors+=("$2"); shift 2 ;;
    -t|--target) target_path="$2"; shift 2 ;;
    --codex-home) codex_home="$2"; shift 2 ;;
    -f|--force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -d "$target_path" ]]; then
  echo "Target project directory does not exist: $target_path" >&2
  exit 1
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
target_root="$(cd "$target_path" && pwd -P)"
skill_source="$repository_root/SKILL.md"
reference_source="$repository_root/references"
profile_source="$repository_root/scripts/profile-repository.ps1"

for required in "$skill_source" "$reference_source" "$profile_source"; do
  [[ -e "$required" ]] || { echo "Required source is missing: $required" >&2; exit 1; }
done

skill_body="$(awk '
  NR == 1 && /^---$/ { front = 1; next }
  front && /^---$/ { front = 0; next }
  !front { print }
' "$skill_source")"
rule_body="$(printf '%s\n' "$skill_body" | sed \
  -e 's|references/|clean-code-refactor-references/|g' \
  -e 's|scripts/profile-repository\.ps1|clean-code-refactor-tools/profile-repository.ps1|g')"

warn_skip() {
  echo "Skipped existing path (use --force to replace): $1" >&2
}

can_replace() {
  [[ ! -e "$1" || $force -eq 1 ]]
}

copy_skill_folder() {
  local destination="$1"
  if ! can_replace "$destination"; then
    warn_skip "$destination"
    return
  fi
  mkdir -p "$destination/scripts"
  cp "$skill_source" "$destination/SKILL.md"
  cp -R "$reference_source" "$destination/references"
  cp "$profile_source" "$destination/scripts/profile-repository.ps1"
  echo "Installed skill folder: $destination"
}

install_rule_file() {
  local destination="$1"
  local format="${2:-plain}"
  local parent reference_destination tool_destination content
  parent="$(dirname "$destination")"
  reference_destination="$parent/clean-code-refactor-references"
  tool_destination="$parent/clean-code-refactor-tools"

  if ! can_replace "$destination"; then warn_skip "$destination"; return; fi
  if ! can_replace "$reference_destination"; then warn_skip "$reference_destination"; return; fi
  if ! can_replace "$tool_destination"; then warn_skip "$tool_destination"; return; fi

  mkdir -p "$parent" "$tool_destination"
  case "$format" in
    cursor)
      {
        printf '%s\n' '---' \
          'description: Apply clean-code refactoring, hardening, lint remediation, and duplicate detection.' \
          'globs:' \
          'alwaysApply: false' \
          '---' ''
        printf '%s\n' "$rule_body"
        printf '%s\n' '' '@clean-code-refactor-references/language-hardening.md' '@clean-code-refactor-references/static-quality-rules.md'
      } > "$destination"
      ;;
    continue)
      {
        printf '%s\n' '---' \
          'name: Clean Code Refactor' \
          'description: Refactor, review, and harden changed code.' \
          'alwaysApply: false' \
          '---' ''
        printf '%s\n' "$rule_body"
      } > "$destination"
      ;;
    plain) printf '%s\n' "$rule_body" > "$destination" ;;
    *) echo "Unsupported rule format: $format" >&2; exit 2 ;;
  esac
  cp -R "$reference_source" "$reference_destination"
  cp "$profile_source" "$tool_destination/profile-repository.ps1"
  echo "Installed rule: $destination"
}

install_agents_pointer() {
  local skill_destination="$target_root/.agents/skills/clean-code-refactor"
  local agents_path="$target_root/AGENTS.md"
  local marker='<!-- clean-code-refactor-skill -->'
  copy_skill_folder "$skill_destination"
  if [[ ! -e "$agents_path" ]]; then
    printf '%s\n' "$marker" '## Clean Code Refactor' '' 'For refactoring, lint remediation, duplicate detection, code hardening, and code-quality reviews, load and follow `.agents/skills/clean-code-refactor/SKILL.md`.' '<!-- /clean-code-refactor-skill -->' > "$agents_path"
    echo "Created agent pointer: $agents_path"
  elif ! grep -Fq "$marker" "$agents_path"; then
    printf '%s\n' '' "$marker" '## Clean Code Refactor' '' 'For refactoring, lint remediation, duplicate detection, code hardening, and code-quality reviews, load and follow `.agents/skills/clean-code-refactor/SKILL.md`.' '<!-- /clean-code-refactor-skill -->' >> "$agents_path"
    echo "Added agent pointer: $agents_path"
  fi
}

install_copilot_pointer() {
  local instructions_path="$target_root/.github/copilot-instructions.md"
  local marker='<!-- clean-code-refactor-skill -->'
  mkdir -p "$(dirname "$instructions_path")"
  if [[ ! -e "$instructions_path" ]]; then
    printf '%s\n' "$marker" '## Clean Code Refactor' '' 'For refactoring, lint remediation, duplicate detection, code hardening, and code-quality reviews, load and follow `.github/skills/clean-code-refactor/SKILL.md`.' '<!-- /clean-code-refactor-skill -->' > "$instructions_path"
    echo "Created Copilot pointer: $instructions_path"
  elif ! grep -Fq "$marker" "$instructions_path"; then
    printf '%s\n' '' "$marker" '## Clean Code Refactor' '' 'For refactoring, lint remediation, duplicate detection, code hardening, and code-quality reviews, load and follow `.github/skills/clean-code-refactor/SKILL.md`.' '<!-- /clean-code-refactor-skill -->' >> "$instructions_path"
    echo "Added Copilot pointer: $instructions_path"
  fi
}

install_kilo_rule() {
  local rule_path="$target_root/.kilo/rules/clean-code-refactor.md"
  local config_path="$target_root/kilo.jsonc"
  local rule_reference='.kilo/rules/clean-code-refactor.md'
  install_rule_file "$rule_path"
  if [[ ! -e "$config_path" ]]; then
    printf '%s\n' '{' '  "instructions": [' "    \"$rule_reference\"" '  ]' '}' > "$config_path"
    echo "Created Kilo Code configuration: $config_path"
  elif ! grep -Fq "$rule_reference" "$config_path"; then
    echo "Add \"$rule_reference\" to the instructions array in $config_path to enable the Kilo Code rule." >&2
  fi
}

requested=()
for editor_group in "${editors[@]}"; do
  IFS=',' read -r -a split_editors <<< "$editor_group"
  requested+=("${split_editors[@]}")
done

if [[ " ${requested[*]} " == *" all "* ]]; then
  requested=(agents cursor copilot claude windsurf cline roo continue amazonq opencode kilo)
fi

if [[ ${#requested[@]} -eq 0 ]]; then
  requested=(agents cursor copilot claude windsurf cline roo continue amazonq opencode kilo)
fi

unique_requested=()
for editor in "${requested[@]}"; do
  [[ -n "$editor" && " ${unique_requested[*]} " != *" $editor "* ]] || continue
  unique_requested+=("$editor")
done

for editor in "${unique_requested[@]}"; do
  case "$editor" in
    agents) install_agents_pointer ;;
    cursor) install_rule_file "$target_root/.cursor/rules/clean-code-refactor.mdc" cursor ;;
    copilot) copy_skill_folder "$target_root/.github/skills/clean-code-refactor"; install_copilot_pointer ;;
    claude) copy_skill_folder "$target_root/.claude/skills/clean-code-refactor" ;;
    codex) copy_skill_folder "$codex_home/skills/clean-code-refactor" ;;
    windsurf) install_rule_file "$target_root/.windsurf/rules/clean-code-refactor.md" ;;
    cline) install_rule_file "$target_root/.clinerules/clean-code-refactor.md" ;;
    roo) install_rule_file "$target_root/.roo/rules/clean-code-refactor.md" ;;
    continue) install_rule_file "$target_root/.continue/rules/clean-code-refactor.md" continue ;;
    amazonq) install_rule_file "$target_root/.amazonq/rules/clean-code-refactor.md" ;;
    opencode) copy_skill_folder "$target_root/.opencode/skills/clean-code-refactor" ;;
    kilo) install_kilo_rule ;;
    *) echo "Unsupported editor target: $editor" >&2; exit 2 ;;
  esac
done
