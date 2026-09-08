#!/usr/bin/env bash
# Behavioral test suite for scripts/install.sh (bash 3.2+; no external test framework).
# Covers: fresh install, idempotent re-run, unmanaged skip, forced upgrade with stale +
# nested reference removal, user-modification protection, dry-run, usage errors, spaces
# and Unicode paths, symlink containment, user scope with redirected homes, JSON output.
set -u

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
installer="$repository_root/scripts/install.sh"
validator="$repository_root/scripts/validate-skill.ps1"

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
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail_test "$1" "(expected '$3', got '$2')"; fi
}

run_installer() {
  local out
  out="$(bash "$installer" "$@" 2>&1)"
  RUN_EXIT=$?
  RUN_OUTPUT="$out"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -r "$1" | cut -d' ' -f1
  else printf ''
  fi
}

PKG_VERSION="$(sed -n "s/^PKG_VERSION='\([^']*\)'.*/\1/p" "$installer")"

# ---------------------------------------------------------------- T1 fresh cursor install
T="$(new_target t1)"
run_installer --editor cursor --target "$T"
assert_eq "T1 exits 0" "$RUN_EXIT" "0"
RULE="$T/.cursor/rules/clean-code-refactor.mdc"
[ -f "$RULE" ] && pass "T1 rule file exists" || fail_test "T1 rule file exists"
if [ -f "$RULE" ]; then
  if grep -q 'clean-code-refactor-clean-code-refactor' "$RULE"; then
    fail_test "T1 no double-prefixed reference links"
  else
    pass "T1 no double-prefixed reference links"
  fi
  missing=0
  for link in $(grep -oE 'clean-code-refactor-references/[A-Za-z0-9][A-Za-z0-9._/-]*' "$RULE" | sort -u); do
    rel="${link#clean-code-refactor-references/}"
    [ -f "$T/.cursor/rules/clean-code-refactor-references/$rel" ] || { missing=1; break; }
  done
  [ $missing -eq 0 ] && pass "T1 every generated reference link resolves" || fail_test "T1 every generated reference link resolves"
  grep -q "$PKG_VERSION" "$RULE" && pass "T1 rule carries package version marker" || fail_test "T1 rule carries package version marker"
fi
[ -f "$T/.cursor/rules/clean-code-refactor-tools/profile-repository.ps1" ] && pass "T1 profiler tool installed" || fail_test "T1 profiler tool installed"
[ -f "$T/.cursor/rules/clean-code-refactor-tools/.clean-code-refactor-install.json" ] && pass "T1 receipt written" || fail_test "T1 receipt written"

# ---------------------------------------------------------------- T2 idempotent re-run
run_installer --editor cursor --target "$T" --json
assert_eq "T2 re-run exits 0" "$RUN_EXIT" "0"
printf '%s' "$RUN_OUTPUT" | grep -q '"upToDate"' && pass "T2 JSON reports upToDate" || fail_test "T2 JSON reports upToDate"

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
grep -q 'clean-code-refactor' "$T/.cursor/rules/clean-code-refactor.mdc" && pass "T3 rule replaced" || fail_test "T3 rule replaced"

# ---------------------------------------------------------------- T4 forced upgrade from stale fixture
T="$(new_target t4)"
mkdir -p "$T/.cursor/rules/clean-code-refactor-references/references"
printf 'stale' > "$T/.cursor/rules/clean-code-refactor-references/stale-old-file.md"
printf 'nested junk' > "$T/.cursor/rules/clean-code-refactor-references/references/junk.md"
STALE_RULE="$T/.cursor/rules/clean-code-refactor.mdc"
printf 'OLD BROKEN clean-code-refactor-clean-code-refactor-references/static-quality-rules.md' > "$STALE_RULE"
run_installer --editor cursor --target "$T"
assert_eq "T4 stale unmanaged install skipped without force" "$RUN_EXIT" "0"
grep -q 'OLD BROKEN' "$STALE_RULE" && pass "T4 stale rule untouched without force" || fail_test "T4 stale rule untouched without force"
run_installer --editor cursor --target "$T" --force
assert_eq "T4 forced upgrade exits 0" "$RUN_EXIT" "0"
grep -q 'OLD BROKEN' "$STALE_RULE" && fail_test "T4 rule content updated" || pass "T4 rule content updated"
[ ! -f "$T/.cursor/rules/clean-code-refactor-references/stale-old-file.md" ] && pass "T4 stale reference removed" || fail_test "T4 stale reference removed"
[ ! -e "$T/.cursor/rules/clean-code-refactor-references/references" ] && pass "T4 nested references directory removed" || fail_test "T4 nested references directory removed"

# ---------------------------------------------------------------- T5 user-modification protection
T="$(new_target t5)"
run_installer --editor claude --target "$T"
SKILL_COPY="$T/.claude/skills/clean-code-refactor/SKILL.md"
[ -f "$SKILL_COPY" ] && pass "T5 skill folder installed" || fail_test "T5 skill folder installed"
printf '\n<!-- user edit -->\n' >> "$SKILL_COPY"
run_installer --editor claude --target "$T"
assert_eq "T5 user modification skipped without force" "$RUN_EXIT" "0"
grep -q 'user edit' "$SKILL_COPY" && pass "T5 user edit preserved" || fail_test "T5 user edit preserved"
run_installer --editor claude --target "$T" --force
assert_eq "T5 force overwrites user modification" "$RUN_EXIT" "0"
grep -q 'user edit' "$SKILL_COPY" && fail_test "T5 user edit replaced" || pass "T5 user edit replaced"

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
[ -f "$FANCY/.cursor/rules/clean-code-refactor.mdc" ] && pass "T8 rule exists in fancy path" || fail_test "T8 rule exists in fancy path"

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
[ -f "$FAKE_HOME/.claude/skills/clean-code-refactor/SKILL.md" ] && pass "T10 claude user skill installed" || fail_test "T10 claude user skill installed"
[ -f "$FAKE_HOME/.cursor/skills/clean-code-refactor/SKILL.md" ] && pass "T10 cursor user skill installed" || fail_test "T10 cursor user skill installed"
[ -f "$FAKE_HOME/.config/opencode/skills/clean-code-refactor/SKILL.md" ] && pass "T10 opencode user skill installed" || fail_test "T10 opencode user skill installed"
[ -f "$FAKE_CODEX/skills/clean-code-refactor/SKILL.md" ] && pass "T10 codex skill installed in redirected home" || fail_test "T10 codex skill installed in redirected home"
T="$(new_target t10p)"
run_installer --editor claude --target "$T"
assert_eq "T10 project install unaffected by user install" "$RUN_EXIT" "0"

# ---------------------------------------------------------------- T11 pointers preserved and idempotent
T="$(new_target t11)"
run_installer --editor agents,copilot --target "$T"
[ -f "$T/AGENTS.md" ] && pass "T11 AGENTS.md pointer created" || fail_test "T11 AGENTS.md pointer created"
[ -f "$T/.github/copilot-instructions.md" ] && pass "T11 copilot pointer created" || fail_test "T11 copilot pointer created"
[ -f "$T/.agents/skills/clean-code-refactor/.clean-code-refactor-install.json" ] && pass "T11 agents receipt written" || fail_test "T11 agents receipt written"
[ -f "$T/.github/skills/clean-code-refactor/.clean-code-refactor-install.json" ] && pass "T11 copilot receipt written" || fail_test "T11 copilot receipt written"
printf '# Project conventions\n\nUse pnpm. Run tests with pnpm test.\n' > "$T/AGENTS.md"
run_installer --editor agents --target "$T"
grep -q 'pnpm test' "$T/AGENTS.md" && pass "T11 existing pointer content preserved" || fail_test "T11 existing pointer content preserved"
grep -q 'clean-code-refactor-skill' "$T/AGENTS.md" && pass "T11 pointer section appended" || fail_test "T11 pointer section appended"

# ---------------------------------------------------------------- T12 JSON output parses as summary
T="$(new_target t12)"
run_installer --editor cursor --target "$T" --json
assert_eq "T12 JSON run exits 0" "$RUN_EXIT" "0"
printf '%s' "$RUN_OUTPUT" | grep -q '"status": "installed"' && pass "T12 JSON contains installed status" || fail_test "T12 JSON contains installed status"
printf '%s' "$RUN_OUTPUT" | grep -q '"summary"' && pass "T12 JSON contains summary" || fail_test "T12 JSON contains summary"

# ---------------------------------------------------------------- T13 kilo config
T="$(new_target t13)"
run_installer --editor kilo --target "$T"
assert_eq "T13 kilo install exits 0" "$RUN_EXIT" "0"
[ -f "$T/kilo.jsonc" ] && grep -q '.kilo/rules/clean-code-refactor.md' "$T/kilo.jsonc" && pass "T13 kilo.jsonc configured" || fail_test "T13 kilo.jsonc configured"

# ---------------------------------------------------------------- T14 codex project scope is skipped
T="$(new_target t14)"
run_installer --editor codex --target "$T"
assert_eq "T14 codex skipped in project scope" "$RUN_EXIT" "0"
printf '%s' "$RUN_OUTPUT" | grep -q "not declared" && pass "T14 skip reason reported" || fail_test "T14 skip reason reported"

echo ""
echo "Bash suite: $PASS passed, $FAIL failed, $SKIP skipped."
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
