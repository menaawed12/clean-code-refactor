#!/usr/bin/env bash
# Behavioral test suite for scripts/install.sh (bash 3.2+; no external test framework).
# Covers: fresh install, idempotent re-run, unmanaged skip, forced upgrade with stale +
# nested reference removal, user-modification protection, dry-run, usage errors, spaces
# and Unicode paths, symlink containment, user scope with redirected homes, JSON output.
set -u

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
installer="$repository_root/scripts/install.sh"

PASS=0
FAIL=0
SKIP=0
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ccr-tests-XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

new_target() {
  local dir="$TMP_ROOT/target-$1"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail_test() { FAIL=$((FAIL + 1)); echo "FAIL: $1 ${2:-}"; }
skip_test() { SKIP=$((SKIP + 1)); echo "SKIP: $1"; }
# Record a pass when the command succeeds (check) or fails (check_not).
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail_test "$name"; fi; }
check_not() { local name="$1"; shift; if "$@"; then fail_test "$name"; else pass "$name"; fi; }
# shellcheck disable=SC2317  # invoked indirectly through check/check_not
output_has() { printf '%s' "$RUN_OUTPUT" | grep -q -- "$1"; }
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail_test "$1" "(expected '$3', got '$2')"; fi
}

run_installer() {
  local out
  out="$(bash "$installer" "$@" 2>&1)"
  RUN_EXIT=$?
  RUN_OUTPUT="$out"
}

PKG_VERSION="$(sed -n "s/^PKG_VERSION='\([^']*\)'.*/\1/p" "$installer")"

# ---------------------------------------------------------------- T1 fresh cursor install
T="$(new_target t1)"
run_installer --editor cursor --target "$T"
assert_eq "T1 exits 0" "$RUN_EXIT" "0"
RULE="$T/.cursor/rules/clean-code-refactor.mdc"
check "T1 rule file exists" [ -f "$RULE" ]
if [ -f "$RULE" ]; then
  if grep -q 'clean-code-refactor-clean-code-refactor' "$RULE"; then
    fail_test "T1 no double-prefixed reference links"
  else
    pass "T1 no double-prefixed reference links"
  fi
  missing=0
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    rel="${link#clean-code-refactor-references/}"
    [ -f "$T/.cursor/rules/clean-code-refactor-references/$rel" ] || { missing=1; break; }
  done <<EOF_LINKS
$(grep -oE 'clean-code-refactor-references/[A-Za-z0-9][A-Za-z0-9._/-]*' "$RULE" | sort -u)
EOF_LINKS
  check "T1 every generated reference link resolves" [ $missing -eq 0 ]
  check "T1 rule carries package version marker" grep -q "$PKG_VERSION" "$RULE"
fi
check "T1 profiler tool installed" [ -f "$T/.cursor/rules/clean-code-refactor-tools/profile-repository.ps1" ]
check "T1 receipt written" [ -f "$T/.cursor/rules/clean-code-refactor-tools/.clean-code-refactor-install.json" ]

# ---------------------------------------------------------------- T2 idempotent re-run
run_installer --editor cursor --target "$T" --json
assert_eq "T2 re-run exits 0" "$RUN_EXIT" "0"
check "T2 JSON reports upToDate" output_has '"upToDate"'

# ---------------------------------------------------------------- T3 unmanaged install skip
T="$(new_target t3)"
mkdir -p "$T/.cursor/rules"
printf 'user-owned rule content' > "$T/.cursor/rules/clean-code-refactor.mdc"
printf 'team rules' > "$T/.cursor/rules/team-conventions.mdc"
run_installer --editor cursor --target "$T"
assert_eq "T3 unmanaged install skipped, exit 0" "$RUN_EXIT" "0"
assert_eq "T3 foreign rule untouched" "$(cat "$T/.cursor/rules/clean-code-refactor.mdc")" "user-owned rule content"
assert_eq "T3 unrelated rule untouched" "$(cat "$T/.cursor/rules/team-conventions.mdc")" "team rules"
run_installer --editor cursor --target "$T" --force
assert_eq "T3 force replaces unmanaged install" "$RUN_EXIT" "0"
check "T3 rule replaced" grep -q 'clean-code-refactor' "$T/.cursor/rules/clean-code-refactor.mdc"

# ---------------------------------------------------------------- T4 forced upgrade from stale fixture
T="$(new_target t4)"
mkdir -p "$T/.cursor/rules/clean-code-refactor-references/references"
printf 'stale' > "$T/.cursor/rules/clean-code-refactor-references/stale-old-file.md"
printf 'nested junk' > "$T/.cursor/rules/clean-code-refactor-references/references/junk.md"
STALE_RULE="$T/.cursor/rules/clean-code-refactor.mdc"
printf 'OLD BROKEN clean-code-refactor-clean-code-refactor-references/static-quality-rules.md' > "$STALE_RULE"
run_installer --editor cursor --target "$T"
assert_eq "T4 stale unmanaged install skipped without force" "$RUN_EXIT" "0"
check "T4 stale rule untouched without force" grep -q 'OLD BROKEN' "$STALE_RULE"
run_installer --editor cursor --target "$T" --force
assert_eq "T4 forced upgrade exits 0" "$RUN_EXIT" "0"
check_not "T4 rule content updated" grep -q 'OLD BROKEN' "$STALE_RULE"
check "T4 stale reference removed" [ ! -f "$T/.cursor/rules/clean-code-refactor-references/stale-old-file.md" ]
check "T4 nested references directory removed" [ ! -e "$T/.cursor/rules/clean-code-refactor-references/references" ]

# ---------------------------------------------------------------- T5 user-modification protection
T="$(new_target t5)"
run_installer --editor claude --target "$T"
SKILL_COPY="$T/.claude/skills/clean-code-refactor/SKILL.md"
check "T5 skill folder installed" [ -f "$SKILL_COPY" ]
printf '\n<!-- user edit -->\n' >> "$SKILL_COPY"
run_installer --editor claude --target "$T"
assert_eq "T5 user modification skipped without force" "$RUN_EXIT" "0"
check "T5 user edit preserved" grep -q 'user edit' "$SKILL_COPY"
run_installer --editor claude --target "$T" --force
assert_eq "T5 force overwrites user modification" "$RUN_EXIT" "0"
check_not "T5 user edit replaced" grep -q 'user edit' "$SKILL_COPY"

# ---------------------------------------------------------------- T6 dry run
T="$(new_target t6)"
BEFORE="$(find "$T" -type f | sort)"
run_installer --editor all --target "$T" --dry-run
assert_eq "T6 dry run exits 0" "$RUN_EXIT" "0"
AFTER="$(find "$T" -type f | sort)"
assert_eq "T6 dry run writes nothing" "$AFTER" "$BEFORE"

# ---------------------------------------------------------------- T7 invalid editor, no partial writes
T="$(new_target t7)"
BEFORE="$(find "$T" -type f | sort)"
run_installer --editor does-not-exist --target "$T"
assert_eq "T7 invalid editor exits 2" "$RUN_EXIT" "2"
AFTER="$(find "$T" -type f | sort)"
assert_eq "T7 invalid editor writes nothing" "$AFTER" "$BEFORE"

# ---------------------------------------------------------------- T8 spaces and Unicode
T="$(new_target t8)"
FANCY="$T/my project - ünïcode ✓"
mkdir -p "$FANCY"
run_installer --editor cursor --target "$FANCY"
assert_eq "T8 spaces and Unicode path install" "$RUN_EXIT" "0"
check "T8 rule exists in fancy path" [ -f "$FANCY/.cursor/rules/clean-code-refactor.mdc" ]

# ---------------------------------------------------------------- T9 symlink containment
T="$(new_target t9)"
OUTSIDE="$TMP_ROOT/outside-t9"
mkdir -p "$OUTSIDE"
if ln -s "$OUTSIDE" "$T/.cursor" 2>/dev/null && [ -L "$T/.cursor" ]; then
  run_installer --editor cursor --target "$T"
  assert_eq "T9 symlinked destination refused (exit 2)" "$RUN_EXIT" "2"
  outside_count="$(find "$OUTSIDE" -type f | wc -l | tr -d ' ')"
  assert_eq "T9 nothing written outside the root" "$outside_count" "0"
else
  skip_test "T9 symlink containment (real symlinks not available; MSYS ln -s copies)"
fi

# ---------------------------------------------------------------- T10 user scope with redirected homes
FAKE_HOME="$TMP_ROOT/home-t10"
FAKE_CODEX="$TMP_ROOT/codex-t10"
mkdir -p "$FAKE_HOME" "$FAKE_CODEX"
run_installer --scope user --editor claude,cursor,opencode,codex --user-home "$FAKE_HOME" --codex-home "$FAKE_CODEX"
assert_eq "T10 user-scope installs exit 0" "$RUN_EXIT" "0"
check "T10 claude user skill installed" [ -f "$FAKE_HOME/.claude/skills/clean-code-refactor/SKILL.md" ]
check "T10 cursor user skill installed" [ -f "$FAKE_HOME/.cursor/skills/clean-code-refactor/SKILL.md" ]
check "T10 opencode user skill installed" [ -f "$FAKE_HOME/.config/opencode/skills/clean-code-refactor/SKILL.md" ]
check "T10 codex skill installed in redirected home" [ -f "$FAKE_CODEX/skills/clean-code-refactor/SKILL.md" ]
T="$(new_target t10p)"
run_installer --editor claude --target "$T"
assert_eq "T10 project install unaffected by user install" "$RUN_EXIT" "0"

# ---------------------------------------------------------------- T11 pointers preserved and idempotent
T="$(new_target t11)"
run_installer --editor agents,copilot --target "$T"
check "T11 AGENTS.md pointer created" [ -f "$T/AGENTS.md" ]
check "T11 copilot pointer created" [ -f "$T/.github/copilot-instructions.md" ]
check "T11 agents receipt written" [ -f "$T/.agents/skills/clean-code-refactor/.clean-code-refactor-install.json" ]
check "T11 copilot receipt written" [ -f "$T/.github/skills/clean-code-refactor/.clean-code-refactor-install.json" ]
printf '# Project conventions\n\nUse pnpm. Run tests with pnpm test.\n' > "$T/AGENTS.md"
run_installer --editor agents --target "$T"
check "T11 existing pointer content preserved" grep -q 'pnpm test' "$T/AGENTS.md"
check "T11 pointer section appended" grep -q 'clean-code-refactor-skill' "$T/AGENTS.md"

# ---------------------------------------------------------------- T12 JSON output parses as summary
T="$(new_target t12)"
run_installer --editor cursor --target "$T" --json
assert_eq "T12 JSON run exits 0" "$RUN_EXIT" "0"
check "T12 JSON contains installed status" output_has '"status": "installed"'
check "T12 JSON contains summary" output_has '"summary"'

# ---------------------------------------------------------------- T13 kilo config
T="$(new_target t13)"
run_installer --editor kilo --target "$T"
assert_eq "T13 kilo install exits 0" "$RUN_EXIT" "0"
check "T13 kilo.jsonc configured" grep -q '.kilo/rules/clean-code-refactor.md' "$T/kilo.jsonc"

# ---------------------------------------------------------------- T14 codex project scope is skipped
T="$(new_target t14)"
run_installer --editor codex --target "$T"
assert_eq "T14 codex skipped in project scope" "$RUN_EXIT" "0"
check "T14 skip reason reported" output_has "not declared"

echo ""
echo "Bash suite: $PASS passed, $FAIL failed, $SKIP skipped."
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
