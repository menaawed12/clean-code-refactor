#!/usr/bin/env bash
# Profiles a repository to suggest a review profile. Local and read-only.
#
# POSIX counterpart of scripts/profile-repository.ps1 (bash 3.2+ and POSIX awk; no jq,
# Python, or network). Both profilers share one contract, and the PowerShell test suite
# checks that they report the same languages, frameworks, checks, and signals:
#   - Excluded directories are pruned before descent; symlinked directories are noted and
#     not followed; symlinked files are counted but never read.
#   - Bounds: file count, directory depth, per-manifest read size, and wall-clock time.
#     Exceeding a bound marks the report incomplete instead of failing silently.
#   - Risk signals come from path tokens and carry evidence and confidence; matches in
#     documentation files are reported separately as documentation hints.
#
# Usage: bash scripts/profile-repository.sh [--path DIR] [--format markdown|json]
#          [--max-files N] [--max-depth N] [--max-file-bytes N] [--timeout-seconds N]
# Exit codes: 0 success, 2 usage error.

set -u

usage() {
  cat <<'EOF'
Usage: bash profile-repository.sh [options]
  --path DIR             Repository root to profile (default: current directory).
  --format FORMAT        'markdown' (default) or 'json'.
  --max-files N          Maximum files inspected (100..100000; default 20000).
  --max-depth N          Maximum directory depth below the root (1..64; default 12).
  --max-file-bytes N     Maximum bytes read per manifest (1024..10485760; default 524288).
  --timeout-seconds N    Wall-clock budget for the walk (1..600; default 30).
  -h, --help             Show this help.
EOF
}

fail_usage() { echo "Error: $1" >&2; usage >&2; exit 2; }

require_int_in_range() {
  case "$2" in ''|*[!0-9]*) fail_usage "$1 must be an integer between $3 and $4." ;; esac
  if [ "$2" -lt "$3" ] || [ "$2" -gt "$4" ]; then fail_usage "$1 must be between $3 and $4."; fi
}

target_path="$(pwd)"
output_format="markdown"
max_files=20000
max_depth=12
max_file_bytes=524288
timeout_seconds=30

while [ $# -gt 0 ]; do
  case "$1" in
    --path) [ $# -ge 2 ] || fail_usage "--path needs a value."; target_path="$2"; shift 2 ;;
    --format) [ $# -ge 2 ] || fail_usage "--format needs a value."; output_format="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"; shift 2 ;;
    --max-files) [ $# -ge 2 ] || fail_usage "--max-files needs a value."; max_files="$2"; shift 2 ;;
    --max-depth) [ $# -ge 2 ] || fail_usage "--max-depth needs a value."; max_depth="$2"; shift 2 ;;
    --max-file-bytes) [ $# -ge 2 ] || fail_usage "--max-file-bytes needs a value."; max_file_bytes="$2"; shift 2 ;;
    --timeout-seconds) [ $# -ge 2 ] || fail_usage "--timeout-seconds needs a value."; timeout_seconds="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail_usage "Unknown option: $1" ;;
  esac
done

case "$output_format" in markdown|json) ;; *) fail_usage "--format must be 'markdown' or 'json'." ;; esac
require_int_in_range --max-files "$max_files" 100 100000
require_int_in_range --max-depth "$max_depth" 1 64
require_int_in_range --max-file-bytes "$max_file_bytes" 1024 10485760
require_int_in_range --timeout-seconds "$timeout_seconds" 1 600
[ -d "$target_path" ] || fail_usage "Path is not a directory: $target_path"

# Byte-wise globbing and sorting so results do not depend on the caller's locale.
export LC_ALL=C
root="$(cd "$target_path" && pwd -P)"

records="$(mktemp "${TMPDIR:-/tmp}/ccr-profile-XXXXXX")" || { echo "Error: cannot create a temporary file." >&2; exit 1; }
trap 'rm -f "$records"' EXIT

scanned_files=0
directories_pruned=0
directories_skipped=0
read_errors=0
oversize_files=0
manifests_read=0
incomplete_reason=""

is_excluded_directory() {
  case "$1" in
    .git|node_modules|vendor|bower_components|bin|obj|dist|build|out|target|.venv|venv|__pycache__|.tox|\
    .mypy_cache|.pytest_cache|site-packages|.gradle|.idea|.vs|packages|Pods|.terraform|.dart_tool|.next|.nuxt|\
    coverage|.cache|.bundle) return 0 ;;
  esac
  return 1
}

# Emits framework records for one manifest, reading at most max_file_bytes and never
# following a symlink out of the repository.
read_manifest_frameworks() {
  local file="$1" name="$2" relative="$3" size
  if [ -L "$file" ]; then printf 'S\tnote\tsymlinked manifest not read\tinfo\t%s\n' "$relative"; return 0; fi
  if ! size="$(wc -c < "$file" 2>/dev/null)"; then read_errors=$((read_errors + 1)); return; fi
  size="${size//[!0-9]/}"
  if [ "${size:-0}" -gt "$max_file_bytes" ]; then oversize_files=$((oversize_files + 1)); return; fi
  if [ ! -r "$file" ]; then read_errors=$((read_errors + 1)); return; fi
  manifests_read=$((manifests_read + 1))
  case "$name" in
    package.json)
      grep -Eq '"(react|next)"' "$file" && printf 'S\tframework\tReact/Next.js\thigh\t%s\n' "$relative"
      grep -Eq '"@angular/' "$file" && printf 'S\tframework\tAngular\thigh\t%s\n' "$relative"
      grep -Eq '"(vue|nuxt)"' "$file" && printf 'S\tframework\tVue/Nuxt\thigh\t%s\n' "$relative"
      grep -Eq '"(express|nestjs|@nestjs)"' "$file" && printf 'S\tframework\tNode/NestJS\thigh\t%s\n' "$relative"
      ;;
    composer.json) grep -Eiq 'laravel' "$file" && printf 'S\tframework\tLaravel\thigh\t%s\n' "$relative" ;;
    Gemfile) grep -Eiq 'rails' "$file" && printf 'S\tframework\tRails\thigh\t%s\n' "$relative" ;;
    pubspec.yaml) grep -Eiq 'flutter' "$file" && printf 'S\tframework\tFlutter\thigh\t%s\n' "$relative" ;;
    pyproject.toml)
      grep -Eiq 'django' "$file" && printf 'S\tframework\tDjango\thigh\t%s\n' "$relative"
      grep -Eiq 'fastapi' "$file" && printf 'S\tframework\tFastAPI\thigh\t%s\n' "$relative"
      grep -Eiq 'flask' "$file" && printf 'S\tframework\tFlask\thigh\t%s\n' "$relative"
      ;;
  esac
  return 0
}

# ------------------------------ bounded walk -------------------------------
# Depth-first with an explicit stack, like the PowerShell profiler: directories are
# pushed as they are found and files are recorded immediately.

stack_dirs=("$root")
stack_depths=(0)
stack_size=1
start_seconds=$SECONDS

{
  while [ "$stack_size" -gt 0 ]; do
    if [ "$scanned_files" -ge "$max_files" ]; then
      incomplete_reason="file inspection limit reached ($max_files files)"; break
    fi
    if [ $((SECONDS - start_seconds)) -ge "$timeout_seconds" ]; then
      incomplete_reason="time budget exceeded (${timeout_seconds}s)"; break
    fi
    stack_size=$((stack_size - 1))
    dir="${stack_dirs[$stack_size]}"
    depth="${stack_depths[$stack_size]}"

    if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then read_errors=$((read_errors + 1)); continue; fi

    for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      name="${entry##*/}"
      relative="${entry#"$root"/}"
      case "$relative" in
        *"$(printf '\t')"*|*"
"*) read_errors=$((read_errors + 1)); continue ;;
      esac
      if [ -d "$entry" ]; then
        if is_excluded_directory "$name"; then directories_pruned=$((directories_pruned + 1)); continue; fi
        if [ -L "$entry" ]; then
          directories_skipped=$((directories_skipped + 1))
          printf 'S\tnote\treparse point not followed\tinfo\t%s\n' "$relative"
          continue
        fi
        if [ "$depth" -ge "$max_depth" ]; then directories_skipped=$((directories_skipped + 1)); continue; fi
        stack_dirs[stack_size]="$entry"
        stack_depths[stack_size]=$((depth + 1))
        stack_size=$((stack_size + 1))
      else
        if [ "$scanned_files" -ge "$max_files" ]; then
          incomplete_reason="file inspection limit reached ($max_files files)"; break
        fi
        scanned_files=$((scanned_files + 1))
        printf 'F\t%s\n' "$relative"
        case "$name" in
          package.json|composer.json|Gemfile|pubspec.yaml|pyproject.toml)
            read_manifest_frameworks "$entry" "$name" "$relative" ;;
        esac
      fi
    done
  done

  printf 'T\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$scanned_files" "$directories_pruned" "$directories_skipped" \
    "$read_errors" "$oversize_files" "$manifests_read" "$incomplete_reason"
} > "$records"

# ------------------------------ classification and output ------------------

awk -F '\t' -v root="$root" -v format="$output_format" '
function json_escape(s,    out, i, c) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\") out = out "\\\\"
    else if (c == "\"") out = out "\\\""
    else if (c in control) out = out control[c]
    else out = out c
  }
  return "\"" out "\""
}
function in_list(value, list) { return index(" " list " ", " " value " ") > 0 }
function add_signal(category, value, confidence, evidence,    key, n) {
  key = category SUBSEP value
  if (!(key in sig_conf)) {
    sig_order[++sig_count] = key
    sig_cat[key] = category; sig_val[key] = value; sig_conf[key] = confidence
    sig_n[key] = 0
    if (evidence != "") { sig_n[key] = 1; sig_ev[key, 1] = evidence }
    return
  }
  if (evidence == "" || sig_n[key] >= 5) return
  for (n = 1; n <= sig_n[key]; n++) if (sig_ev[key, n] == evidence) return
  sig_ev[key, ++sig_n[key]] = evidence
  if (sig_conf[key] == "low" && confidence == "high") sig_conf[key] = "high"
}
function has_token(list,    t) {
  for (t in tokens) if (in_list(t, list)) return 1
  return 0
}
function classify(relative,    name, ext, stem, parts, words, i, j, n, m, is_doc, is_code, target, confidence) {
  n = split(relative, parts, "/")
  name = parts[n]
  ext = ""
  if (match(name, /\.[^.]*$/)) ext = tolower(substr(name, RSTART))

  if (name in manifest_language) add_signal("language", manifest_language[name], "high", relative)
  if (in_list(ext, ".sln .csproj .fsproj .vbproj")) add_signal("language", ".NET", "high", relative)
  if (in_list(ext, ".sh .bash .zsh .fish")) { shell_scripts++; add_signal("language", "Shell", "high", relative) }
  if (ext == ".ps1" || ext == ".psm1") { shell_scripts++; add_signal("language", "PowerShell", "high", relative) }
  if (name == "Dockerfile" || ext == ".dockerfile") add_signal("delivery", "Docker", "high", relative)
  if (ext == ".tf" || ext == ".tfvars") add_signal("delivery", "Terraform", "high", relative)
  if (name == "Chart.yaml") add_signal("delivery", "Helm chart", "high", relative)
  if (name in check_name) add_signal("check", check_name[name], "medium", relative)
  if (index(relative, ".github/workflows/") == 1 && (ext == ".yml" || ext == ".yaml")) add_signal("check", "GitHub Actions", "high", relative)

  is_doc = in_list(ext, doc_extensions)
  is_code = (ext == "" || in_list(ext, code_extensions))
  if (!is_doc && !is_code) return
  stem = relative
  sub(/\.[A-Za-z0-9]+$/, "", stem)
  delete tokens
  n = split(stem, parts, "/")
  for (i = 1; i <= n; i++) {
    m = split(parts[i], words, /[^A-Za-z0-9]+/)
    for (j = 1; j <= m; j++) if (words[j] != "") tokens[tolower(words[j])] = 1
  }
  target = (is_doc && !is_code) ? "documentationHints" : "riskSignals"
  confidence = (is_doc && !is_code) ? "documentation-only" : "low"
  if (has_token(auth_tokens)) add_signal(target, "authentication or authorization surface", confidence, relative)
  if (has_token(schema_tokens)) add_signal(target, "database schema or migration surface", confidence, relative)
  if (has_token(payment_tokens)) add_signal(target, "payment or billing surface", confidence, relative)
  if (has_token(delivery_tokens)) add_signal(target, "delivery or infrastructure surface", confidence, relative)
}
function values_of(category,    i, k, list, n, out, a, b, tmp) {
  n = 0
  for (i = 1; i <= sig_count; i++) { k = sig_order[i]; if (sig_cat[k] == category) list[++n] = sig_val[k] }
  for (a = 2; a <= n; a++) for (b = a; b > 1 && list[b - 1] > list[b]; b--) { tmp = list[b]; list[b] = list[b - 1]; list[b - 1] = tmp }
  value_count = n
  out = ""
  for (i = 1; i <= n; i++) out = out (i > 1 ? SUBSEP : "") list[i]
  return out
}
function json_array(joined,    items, n, i, out) {
  if (joined == "") return "[]"
  n = split(joined, items, SUBSEP)
  out = "["
  for (i = 1; i <= n; i++) out = out (i > 1 ? ", " : "") json_escape(items[i])
  return out "]"
}
function human_list(joined,    items, n, i, out) {
  if (joined == "") return "none detected"
  n = split(joined, items, SUBSEP)
  out = ""
  for (i = 1; i <= n; i++) out = out (i > 1 ? ", " : "") items[i]
  return out
}
BEGIN {
  for (i = 1; i < 32; i++) control[sprintf("%c", i)] = sprintf("\\u%04x", i)
  control["\t"] = "\\t"; control["\n"] = "\\n"; control["\r"] = "\\r"
  code_extensions = ".py .js .mjs .cjs .jsx .ts .tsx .java .kt .kts .scala .cs .vb .fs .go .rs .c .h .cpp .hpp .cc .m .mm .php .rb .swift .dart .ex .exs .erl .hrl .clj .cljs .hs .lua .pl .pm .r .jl .sql .sh .bash .zsh .fish .ps1 .psm1 .psd1 .tf .hcl .yml .yaml .json .toml .gradle .groovy"
  doc_extensions = ".md .mdx .rst .txt .adoc"
  auth_tokens = "auth authn authz authentication authorization identity permission permissions rbac oauth jwt sso"
  schema_tokens = "migration migrations schema seed seeds"
  payment_tokens = "payment payments billing invoice checkout"
  delivery_tokens = "terraform deploy deployment deployments pipeline pipelines workflow workflows infra infrastructure helm k8s"
  split("package.json tsconfig.json jsconfig.json", a, " "); for (i in a) manifest_language[a[i]] = "TypeScript/JavaScript"
  split("pyproject.toml requirements.txt Pipfile setup.py", a, " "); for (i in a) manifest_language[a[i]] = "Python"
  split("pom.xml build.gradle build.gradle.kts settings.gradle settings.gradle.kts", a, " "); for (i in a) manifest_language[a[i]] = "Java/Kotlin/Scala"
  manifest_language["global.json"] = ".NET"; manifest_language["go.mod"] = "Go"; manifest_language["Cargo.toml"] = "Rust"
  manifest_language["composer.json"] = "PHP"; manifest_language["Gemfile"] = "Ruby"; manifest_language["pubspec.yaml"] = "Dart/Flutter"
  split(".eslintrc .eslintrc.js .eslintrc.json .eslintrc.yml eslint.config.js eslint.config.mjs eslint.config.ts", a, " "); for (i in a) check_name[a[i]] = "ESLint"
  check_name[".prettierrc"] = "Prettier"; check_name["prettier.config.js"] = "Prettier"
  check_name["pytest.ini"] = "Pytest"; check_name["tox.ini"] = "Pytest/tox"; check_name["conftest.py"] = "Pytest"
  check_name[".pre-commit-config.yaml"] = "Pre-commit"; check_name["Dockerfile"] = "Docker"
  check_name["docker-compose.yml"] = "Docker"; check_name["docker-compose.yaml"] = "Docker"
  check_name["kustomization.yaml"] = "Kustomize"; check_name["Chart.yaml"] = "Helm"; check_name["Makefile"] = "Make"
  check_name[".gitlab-ci.yml"] = "GitLab CI"; check_name["azure-pipelines.yml"] = "Azure Pipelines"
  check_name["jest.config.js"] = "Jest"; check_name["jest.config.ts"] = "Jest"; check_name["vitest.config.ts"] = "Vitest"
  check_name["tsconfig.json"] = "TypeScript"; check_name["phpstan.neon"] = "PHPStan"; check_name[".rubocop.yml"] = "RuboCop"
  check_name[".golangci.yml"] = "golangci-lint"; check_name["clippy.toml"] = "Clippy"; check_name[".swiftlint.yml"] = "SwiftLint"
  shell_scripts = 0
}
$1 == "F" { classify($2); next }
$1 == "S" { add_signal($2, $3, $4, $5); next }
$1 == "T" {
  scanned = $2; pruned = $3; skipped = $4; read_errors = $5; oversize = $6; manifests = $7; incomplete = $8
}
END {
  languages = values_of("language");    language_count = value_count
  frameworks = values_of("framework");  framework_count = value_count
  checks = values_of("check")
  delivery = values_of("delivery")
  risks = values_of("riskSignals");     risk_count = value_count
  hints = values_of("documentationHints")
  notes = values_of("note")
  if (risk_count > 0) profile = "strict"
  else if (index(SUBSEP delivery SUBSEP, SUBSEP "Terraform" SUBSEP) || index(SUBSEP delivery SUBSEP, SUBSEP "Helm chart" SUBSEP)) profile = "infrastructure"
  else if (framework_count > 0) profile = "api-service or frontend (select by changed surface)"
  else profile = "legacy-safe or strict (select by change risk)"
  note = "Read-only discovery only. Confirm actual commands and project conventions before changing code. Documentation-only signals are labeled; verify each risk signal against real code."

  # Signals sorted by category, then value.
  for (i = 1; i <= sig_count; i++) sorted[i] = sig_order[i]
  for (pass = 2; pass <= sig_count; pass++) {
    for (pos = pass; pos > 1; pos--) {
      ka = sorted[pos - 1]; kb = sorted[pos]
      if (sig_cat[ka] < sig_cat[kb] || (sig_cat[ka] == sig_cat[kb] && sig_val[ka] <= sig_val[kb])) break
      sorted[pos - 1] = kb; sorted[pos] = ka
    }
  }

  if (format == "json") {
    print "{"
    print "  \"repository\": " json_escape(root) ","
    print "  \"suggestedProfile\": " json_escape(profile) ","
    print "  \"complete\": " (incomplete == "" ? "true" : "false") ","
    print "  \"incompleteReason\": " (incomplete == "" ? "null" : json_escape(incomplete)) ","
    print "  \"languages\": " json_array(languages) ","
    print "  \"frameworks\": " json_array(frameworks) ","
    print "  \"configuredChecks\": " json_array(checks) ","
    print "  \"deliverySignals\": " json_array(delivery) ","
    print "  \"riskSignals\": " json_array(risks) ","
    print "  \"documentationHints\": " json_array(hints) ","
    print "  \"notes\": " json_array(notes) ","
    print "  \"signals\": ["
    for (i = 1; i <= sig_count; i++) {
      k = sorted[i]
      evidence = ""
      for (n = 1; n <= sig_n[k]; n++) evidence = evidence (n > 1 ? SUBSEP : "") sig_ev[k, n]
      printf "    { \"category\": %s, \"value\": %s, \"confidence\": %s, \"evidence\": %s }%s\n", \
        json_escape(sig_cat[k]), json_escape(sig_val[k]), json_escape(sig_conf[k]), json_array(evidence), (i < sig_count ? "," : "")
    }
    print "  ],"
    printf "  \"stats\": { \"scannedFiles\": %d, \"directoriesPruned\": %d, \"directoriesSkipped\": %d, \"readErrors\": %d, \"oversizeFiles\": %d, \"manifestsRead\": %d, \"shellScripts\": %d },\n", \
      scanned, pruned, skipped, read_errors, oversize, manifests, shell_scripts
    print "  \"note\": " json_escape(note)
    print "}"
    exit 0
  }

  print "# Repository Profile"
  print ""
  print "- Repository: " root
  print "- Suggested profile: " profile
  print "- languages: " human_list(languages)
  print "- frameworks: " human_list(frameworks)
  print "- configured Checks: " human_list(checks)
  print "- delivery Signals: " human_list(delivery)
  print "- risk Signals: " human_list(risks)
  print "- documentation Hints: " human_list(hints)
  for (i = 1; i <= sig_count; i++) {
    k = sorted[i]
    if (!in_list(sig_cat[k], "language framework check delivery riskSignals")) continue
    evidence = ""
    for (n = 1; n <= sig_n[k]; n++) evidence = evidence (n > 1 ? ", " : "") sig_ev[k, n]
    print "  - " sig_cat[k] ": " sig_val[k] " [" sig_conf[k] "] <- " evidence
  }
  print "- Files sampled: " scanned "; directories pruned: " pruned "; directories skipped: " skipped "; read errors: " read_errors "; shell scripts: " shell_scripts
  if (incomplete == "") print "- Status: complete"
  else print "- Status: INCOMPLETE (" incomplete "). Findings may be missing; widen the bounds and rerun."
  print "- Note: " note
}
' "$records"
