#!/usr/bin/env python3
"""Grades behavioral eval cases for the clean-code-refactor skill.

Each case in evals/cases/<id>/ has:
  case.json   prompt and declarative checks
  fixture/    the repository the agent works on (all the agent sees)
  hidden/     tests the agent never sees, run by the grader
  solution/   a reference result: files overlaid on the fixture, plus REPORT.md

Usage:
  grade.py self-test                       Prove every check is meaningful: it must give its
                                           expected result on the untouched fixture and pass
                                           on the reference solution.
  grade.py grade CASE WORKSPACE [--report FILE] [--json]
                                           Grade an agent's finished workspace and final report.

Standard library only; Python 3.9+. Commands run with a timeout and only inside a
temporary copy or the given workspace.
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

EVALS_DIR = Path(__file__).resolve().parent
CASES_DIR = EVALS_DIR / "cases"
COMMAND_TIMEOUT_SECONDS = 120


class CaseError(Exception):
    """A case definition is malformed."""


def load_case(case_id: str) -> dict:
    case_dir = CASES_DIR / case_id
    case_file = case_dir / "case.json"
    if not case_file.is_file():
        raise CaseError(f"unknown case '{case_id}'")
    case = json.loads(case_file.read_text(encoding="utf-8"))
    if case.get("id") != case_id:
        raise CaseError(f"{case_file}: id must be '{case_id}'")
    for key in ("title", "prompt", "checks"):
        if not case.get(key):
            raise CaseError(f"{case_file}: missing '{key}'")
    for check in case["checks"]:
        if check.get("type") not in CHECKS:
            raise CaseError(f"{case_file}: check '{check.get('id')}' has unknown type '{check.get('type')}'")
        if check.get("expect_on_fixture") not in ("pass", "fail"):
            raise CaseError(f"{case_file}: check '{check.get('id')}' needs expect_on_fixture 'pass' or 'fail'")
    case["dir"] = case_dir
    return case


def contained_path(workspace: Path, relative: str) -> Path:
    path = (workspace / relative).resolve()
    if workspace.resolve() not in (path, *path.parents):
        raise CaseError(f"path escapes the workspace: {relative}")
    return path


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


# ------------------------------------------------------------------ checks
# Each check returns (passed, detail).


def check_command(check, case, workspace, report):
    argv = [
        part.replace("{python}", sys.executable).replace("{case}", str(case["dir"])).replace("{workspace}", str(workspace))
        for part in check["run"]
    ]
    env = dict(os.environ, PYTHONPATH=str(workspace), PYTHONDONTWRITEBYTECODE="1")
    try:
        completed = subprocess.run(
            argv, cwd=workspace, env=env, capture_output=True, text=True, timeout=COMMAND_TIMEOUT_SECONDS
        )
    except subprocess.TimeoutExpired:
        return False, f"timed out after {COMMAND_TIMEOUT_SECONDS}s"
    expected = check.get("expect_exit", 0)
    tail = (completed.stdout + completed.stderr).strip().splitlines()[-3:]
    return completed.returncode == expected, f"exit {completed.returncode}: {' | '.join(tail)}"


def check_file_unchanged(check, case, workspace, report):
    original = read_text(case["dir"] / "fixture" / check["path"])
    current = read_text(contained_path(workspace, check["path"]))
    return current is not None and current == original, "unchanged" if current == original else "modified or missing"


def check_path_absent(check, case, workspace, report):
    exists = contained_path(workspace, check["path"]).exists()
    return not exists, "absent" if not exists else "present"


def _matches(check, workspace):
    text = read_text(contained_path(workspace, check["path"]))
    if text is None:
        return None
    return len(re.findall(check["pattern"], text, flags=re.MULTILINE))


def check_regex_absent(check, case, workspace, report):
    count = _matches(check, workspace)
    if count is None:
        return False, "file missing"
    return count == 0, f"{count} match(es)"


def check_regex_count_at_least(check, case, workspace, report):
    count = _matches(check, workspace)
    if count is None:
        return False, "file missing"
    return count >= check["count"], f"{count} match(es), need at least {check['count']}"


def check_regex_count_at_most(check, case, workspace, report):
    count = _matches(check, workspace)
    if count is None:
        return False, "file missing"
    return count <= check["count"], f"{count} match(es), allowed at most {check['count']}"


def check_python_function_max_lines(check, case, workspace, report):
    text = read_text(contained_path(workspace, check["path"]))
    if text is None:
        return False, "file missing"
    try:
        tree = ast.parse(text)
    except SyntaxError as error:
        return False, f"syntax error: {error}"
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == check["function"]:
            length = node.end_lineno - node.lineno + 1
            return length <= check["max"], f"{length} lines, allowed at most {check['max']}"
    return False, f"function {check['function']} not found"


def check_report_matches(check, case, workspace, report):
    if report is None:
        return False, "no report"
    found = re.search(check["pattern"], report, flags=re.MULTILINE) is not None
    return found, "matched" if found else "no match"


CHECKS = {
    "command": check_command,
    "file_unchanged": check_file_unchanged,
    "path_absent": check_path_absent,
    "regex_absent": check_regex_absent,
    "regex_count_at_least": check_regex_count_at_least,
    "regex_count_at_most": check_regex_count_at_most,
    "python_function_max_lines": check_python_function_max_lines,
    "report_matches": check_report_matches,
}


def run_checks(case: dict, workspace: Path, report: str | None) -> list[dict]:
    results = []
    for check in case["checks"]:
        try:
            passed, detail = CHECKS[check["type"]](check, case, workspace, report)
        except CaseError:
            raise
        except Exception as error:  # A broken workspace must fail the check, not the grader.
            passed, detail = False, f"error: {error}"
        results.append({"id": check["id"], "passed": passed, "detail": detail, "expect_on_fixture": check["expect_on_fixture"]})
    return results


def copy_fixture(case: dict, destination: Path, overlay_solution: bool) -> None:
    shutil.copytree(case["dir"] / "fixture", destination)
    if overlay_solution:
        for source in sorted((case["dir"] / "solution").rglob("*")):
            relative = source.relative_to(case["dir"] / "solution")
            if source.is_file() and relative.as_posix() != "REPORT.md":
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)


# ------------------------------------------------------------------ commands


def self_test() -> int:
    case_ids = sorted(path.name for path in CASES_DIR.iterdir() if path.is_dir())
    failures = 0
    for case_id in case_ids:
        case = load_case(case_id)
        if not (case["dir"] / "hidden").is_dir() or not (case["dir"] / "solution" / "REPORT.md").is_file():
            raise CaseError(f"{case_id}: needs hidden/ and solution/REPORT.md")
        if not any(check["expect_on_fixture"] == "fail" for check in case["checks"]):
            raise CaseError(f"{case_id}: at least one check must fail on the untouched fixture")
        with tempfile.TemporaryDirectory(prefix="ccr-eval-") as temp:
            fixture_workspace = Path(temp) / "fixture"
            copy_fixture(case, fixture_workspace, overlay_solution=False)
            for result in run_checks(case, fixture_workspace, report=None):
                expected_pass = result["expect_on_fixture"] == "pass"
                if result["passed"] != expected_pass:
                    failures += 1
                    print(f"FAIL: {case_id}/{result['id']} on fixture: expected {result['expect_on_fixture']} ({result['detail']})")
                else:
                    print(f"PASS: {case_id}/{result['id']} on fixture is {result['expect_on_fixture']}")

            solution_workspace = Path(temp) / "solution"
            copy_fixture(case, solution_workspace, overlay_solution=True)
            report = (case["dir"] / "solution" / "REPORT.md").read_text(encoding="utf-8")
            for result in run_checks(case, solution_workspace, report=report):
                if not result["passed"]:
                    failures += 1
                    print(f"FAIL: {case_id}/{result['id']} on solution ({result['detail']})")
                else:
                    print(f"PASS: {case_id}/{result['id']} on solution")
    print(f"\nEval self-test: {len(case_ids)} cases, {failures} failure(s).")
    return 1 if failures else 0


def grade(case_id: str, workspace: Path, report_path: Path | None, as_json: bool) -> int:
    case = load_case(case_id)
    report = read_text(report_path) if report_path else None
    results = run_checks(case, workspace.resolve(), report)
    passed = sum(1 for result in results if result["passed"])
    summary = {"case": case_id, "passed": passed, "total": len(results), "checks": results}
    if as_json:
        print(json.dumps(summary, indent=2))
    else:
        for result in results:
            print(f"{'PASS' if result['passed'] else 'FAIL'}: {result['id']} ({result['detail']})")
        print(f"{case_id}: {passed}/{len(results)} checks passed")
    return 0 if passed == len(results) else 1


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("self-test", help="check that every eval case is meaningful")
    grade_parser = commands.add_parser("grade", help="grade a finished workspace")
    grade_parser.add_argument("case")
    grade_parser.add_argument("workspace", type=Path)
    grade_parser.add_argument("--report", type=Path, help="the agent's final message")
    grade_parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.command == "self-test":
            return self_test()
        return grade(args.case, args.workspace, args.report, args.json)
    except CaseError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
