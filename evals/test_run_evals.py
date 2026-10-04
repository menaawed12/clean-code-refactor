"""Unit tests for the eval runner's metrics and regression gate (run in CI).

    python3 -m unittest discover -s evals -p 'test_*.py'
"""

import unittest

import run_evals


def row(case, arm, results):
    passed = sum(1 for result in results if result["passed"])
    return {"case": case, "arm": arm, "passed": passed, "total": len(results), "results": results}


def check(expect_on_fixture, passed):
    return {"id": "x", "expect_on_fixture": expect_on_fixture, "passed": passed, "detail": ""}


class RateTest(unittest.TestCase):
    def test_fixed_and_preserved_are_separate(self):
        rows = [row("a", "with", [check("fail", True), check("fail", False), check("pass", True)])]
        self.assertEqual(run_evals.rate(rows, "fixed"), 0.5)
        self.assertEqual(run_evals.rate(rows, "preserved"), 1.0)

    def test_no_checks_of_a_kind_gives_none(self):
        self.assertIsNone(run_evals.rate([row("a", "with", [check("pass", True)])], "fixed"))


class PassAtKTest(unittest.TestCase):
    def test_case_passes_only_when_every_run_passes(self):
        rows = [
            row("steady", "with", [check("fail", True)]),
            row("steady", "with", [check("fail", True)]),
            row("flaky", "with", [check("fail", True)]),
            row("flaky", "with", [check("fail", False)]),
        ]
        self.assertEqual(run_evals.pass_at_k(rows), 0.5)

    def test_empty_gives_none(self):
        self.assertIsNone(run_evals.pass_at_k([]))


class SummarizeTest(unittest.TestCase):
    def test_metrics_per_arm(self):
        rows = [row("a", "with", [check("fail", True), check("pass", True)]), row("a", "without", [check("fail", False), check("pass", True)])]
        summary, lines = run_evals.summarize(rows, ["a"], ["with", "without"])
        self.assertEqual(summary["byArm"]["with"], {"fixed": 1.0, "preserved": 1.0, "passAtK": 1.0})
        self.assertEqual(summary["byArm"]["without"], {"fixed": 0.0, "preserved": 1.0, "passAtK": 0.0})
        self.assertTrue(lines[-1].startswith("| **all cases** |"))


class CompareToBaselineTest(unittest.TestCase):
    BASELINE = {"with": {"fixed": 0.80, "preserved": 1.0, "passAtK": 0.6}}

    def test_drop_within_tolerance_passes(self):
        current = {"with": {"fixed": 0.76, "preserved": 1.0, "passAtK": 0.6}}
        self.assertEqual(run_evals.compare_to_baseline(current, self.BASELINE, 0.05), [])

    def test_drop_beyond_tolerance_is_reported(self):
        current = {"with": {"fixed": 0.70, "preserved": 0.9, "passAtK": 0.6}}
        regressions = run_evals.compare_to_baseline(current, self.BASELINE, 0.05)
        self.assertEqual(len(regressions), 2)
        self.assertTrue(regressions[0].startswith("with/fixed"))

    def test_improvement_passes(self):
        current = {"with": {"fixed": 0.95, "preserved": 1.0, "passAtK": 0.9}}
        self.assertEqual(run_evals.compare_to_baseline(current, self.BASELINE, 0.0), [])

    def test_missing_arm_is_a_regression(self):
        self.assertEqual(len(run_evals.compare_to_baseline({}, self.BASELINE, 0.05)), 3)


if __name__ == "__main__":
    unittest.main()
