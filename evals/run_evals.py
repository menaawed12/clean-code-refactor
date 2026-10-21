#!/usr/bin/env python3
"""Runs a coding agent on every eval case, with and without the skill, and compares scores.

Each run copies a case's fixture into a fresh temporary workspace. For the "with" arm the
skill is installed into the workspace with scripts/install.sh, exactly as a user would.
The agent command runs inside the workspace; its standard output is saved as the final
report and graded with evals/grade.py. Hidden tests never enter the workspace.

The agent command is a template. Placeholders:
  {prompt}       the task prompt (passed as one argument)
  {prompt_file}  path to a file containing the prompt
  {workspace}    the workspace directory

Example (adjust flags to your agent version; see evals/README.md):
  python3 evals/run_evals.py --editor claude \\
      --agent-cmd 'claude -p {prompt} --permission-mode acceptEdits'

Run this only in a disposable environment: the agent edits files and runs commands.
"""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import grade  # noqa: E402  (sibling module)

REPOSITORY_ROOT = grade.EVALS_DIR.parent
DEFAULT_SKILL_HINT = "Use the clean-code-refactor skill for this task.\n\n"


def install_skill(workspace: Path, editor: str) -> None:
    completed = subprocess.run(
        ["bash", str(REPOSITORY_ROOT / "scripts" / "install.sh"), "--editor", editor, "--target", str(workspace)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"skill install failed: {completed.stdout}{completed.stderr}")


def run_agent(template: str, prompt: str, workspace: Path, timeout: int) -> tuple[str, int, float]:
    prompt_file = workspace.parent / "PROMPT.txt"
    prompt_file.write_text(prompt, encoding="utf-8")
    argv = [
        part.replace("{prompt_file}", str(prompt_file)).replace("{workspace}", str(workspace))
        for part in shlex.split(template)
    ]
    argv = [prompt if part == "{prompt}" else part for part in argv]
    started = time.monotonic()
    try:
        completed = subprocess.run(argv, cwd=workspace, capture_output=True, text=True, timeout=timeout)
        output, code = completed.stdout, completed.returncode
    except subprocess.TimeoutExpired as expired:
        output = expired.stdout.decode() if isinstance(expired.stdout, bytes) else (expired.stdout or "")
        code = -1
    return output, code, time.monotonic() - started


METRICS = ("fixed", "preserved", "passAtK")


def rate(rows: list[dict], kind: str) -> float | None:
    """Share of checks that pass, over checks of one kind.

    fixed     - checks that fail on the untouched fixture: the work that was asked for.
    preserved - checks that pass on the fixture: behavior, scope, and safety kept intact.
    Reported separately because a do-nothing agent passes every preservation check.
    """
    expected = "fail" if kind == "fixed" else "pass"
    outcomes = [result["passed"] for row in rows for result in row["results"] if result["expect_on_fixture"] == expected]
    return sum(outcomes) / len(outcomes) if outcomes else None


def pass_at_k(rows: list[dict]) -> float | None:
    """Share of cases where every run passed every check (pass^k: reliable, not lucky)."""
    by_case: dict[str, bool] = {}
    for row in rows:
        by_case[row["case"]] = by_case.get(row["case"], True) and row["passed"] == row["total"]
    return sum(by_case.values()) / len(by_case) if by_case else None


def summarize(rows: list[dict], case_ids: list[str], arms: list[str]) -> tuple[dict, list[str]]:
    def cell(value):
        return f"{value:.0%}" if value is not None else "-"

    summary = {"runs": rows, "byArm": {}}
    header = " | ".join(f"{arm}: fixed | {arm}: preserved | {arm}: pass^k" for arm in arms)
    lines = [f"| Case | {header} |", "| --- |" + " --- | --- | --- |" * len(arms)]
    for case_id in case_ids:
        cells = []
        for arm in arms:
            selected = [row for row in rows if row["case"] == case_id and row["arm"] == arm]
            cells += [cell(rate(selected, "fixed")), cell(rate(selected, "preserved")), cell(pass_at_k(selected))]
        lines.append(f"| {case_id} | " + " | ".join(cells) + " |")
    totals = []
    for arm in arms:
        selected = [row for row in rows if row["arm"] == arm]
        metrics = {"fixed": rate(selected, "fixed"), "preserved": rate(selected, "preserved"), "passAtK": pass_at_k(selected)}
        summary["byArm"][arm] = metrics
        totals += [f"**{cell(metrics[name])}**" for name in METRICS]
    lines.append("| **all cases** | " + " | ".join(totals) + " |")
    return summary, lines


def compare_to_baseline(current: dict, baseline: dict, max_drop: float) -> list[str]:
    """Describe every metric that fell more than max_drop below the baseline."""
    regressions = []
    for arm, metrics in baseline.items():
        for name in METRICS:
            before = metrics.get(name)
            after = current.get(arm, {}).get(name)
            if before is None:
                continue
            if after is None:
                regressions.append(f"{arm}/{name}: missing from this run (baseline {before:.0%})")
            elif before - after > max_drop:
                regressions.append(f"{arm}/{name}: {after:.0%}, down from {before:.0%} (allowed drop {max_drop:.0%})")
    return regressions


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--agent-cmd", required=True, help="agent command template (see placeholders above)")
    parser.add_argument("--editor", default="claude", help="installer target for the 'with' arm (default: claude)")
    parser.add_argument("--cases", nargs="*", help="case ids to run (default: all)")
    parser.add_argument("--arms", default="with,without", help="comma-separated arms: with, without")
    parser.add_argument("--runs", type=int, default=1, help="runs per case and arm (default: 1)")
    parser.add_argument("--timeout", type=int, default=900, help="seconds per agent run (default: 900)")
    parser.add_argument("--skill-hint", default=DEFAULT_SKILL_HINT,
                        help="text prepended to the prompt in the 'with' arm; pass '' to test automatic triggering")
    parser.add_argument("--out", type=Path, default=Path("eval-results"), help="results directory (default: eval-results)")
    parser.add_argument("--baseline", type=Path, help="fail (exit 1) when a metric drops more than --max-drop below this baseline")
    parser.add_argument("--max-drop", type=float, default=0.05, help="allowed drop per metric, as a fraction (default: 0.05)")
    parser.add_argument("--write-baseline", type=Path, help="write this run's metrics as a new baseline")
    args = parser.parse_args(argv)

    case_ids = args.cases or sorted(path.name for path in grade.CASES_DIR.iterdir() if path.is_dir())
    arms = [arm.strip() for arm in args.arms.split(",") if arm.strip()]
    if not set(arms) <= {"with", "without"} or args.runs < 1:
        parser.error("--arms accepts 'with' and 'without'; --runs must be at least 1")

    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    for case_id in case_ids:
        case = grade.load_case(case_id)
        for arm in arms:
            for run in range(1, args.runs + 1):
                with tempfile.TemporaryDirectory(prefix=f"ccr-{case_id}-{arm}-") as temp:
                    workspace = Path(temp) / "workspace"
                    grade.copy_fixture(case, workspace, overlay_solution=False)
                    prompt = case["prompt"]
                    if arm == "with":
                        install_skill(workspace, args.editor)
                        prompt = args.skill_hint + prompt
                    report, exit_code, seconds = run_agent(args.agent_cmd, prompt, workspace, args.timeout)
                    results = grade.run_checks(case, workspace, report)

                    run_dir = args.out / case_id / f"{arm}-{run}"
                    run_dir.mkdir(parents=True, exist_ok=True)
                    (run_dir / "REPORT.md").write_text(report, encoding="utf-8")
                    (run_dir / "checks.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
                    diff = subprocess.run(
                        ["diff", "-ruN", "-x", ".claude", "-x", ".cursor", "-x", ".github", "-x", ".agents",
                         "-x", "__pycache__", str(case["dir"] / "fixture"), str(workspace)],
                        capture_output=True, text=True,
                    )
                    (run_dir / "changes.diff").write_text(diff.stdout, encoding="utf-8")

                passed = sum(1 for result in results if result["passed"])
                rows.append({"case": case_id, "arm": arm, "run": run, "passed": passed, "total": len(results),
                             "agentExit": exit_code, "seconds": round(seconds, 1), "results": results})
                print(f"{case_id} [{arm} #{run}]: {passed}/{len(results)} checks, agent exit {exit_code}, {seconds:.0f}s")

    summary, lines = summarize(rows, case_ids, arms)
    summary.update({"agentCommand": args.agent_cmd, "editor": args.editor, "runsPerCase": args.runs})

    (args.out / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    (args.out / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n" + "\n".join(lines))
    print(f"\nResults: {args.out.resolve()}")

    if args.write_baseline:
        baseline = {"byArm": summary["byArm"], "cases": case_ids, "runsPerCase": args.runs, "agentCommand": args.agent_cmd}
        args.write_baseline.write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
        print(f"Baseline written: {args.write_baseline}")
    if args.baseline:
        if not args.baseline.is_file():
            print(f"No baseline at {args.baseline}; regression gate skipped. Record one with --write-baseline.")
            return 0
        baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        if sorted(baseline.get("cases", [])) != sorted(case_ids):
            print("Note: the baseline covers a different set of cases; rates are compared anyway.")
        regressions = compare_to_baseline(summary["byArm"], baseline.get("byArm", {}), args.max_drop)
        for regression in regressions:
            print(f"REGRESSION: {regression}")
        if regressions:
            return 1
        print(f"No regression beyond {args.max_drop:.0%} against {args.baseline}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
