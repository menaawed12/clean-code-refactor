# Behavioral Evals

The installer tests prove that files land in the right place. These evals measure what actually matters: whether an agent that uses the skill does better work than the same agent without it.

## Cases

Each case in `cases/<id>/` is a small repository, a realistic prompt, and checks that grade the result:

| Case | Skill promise under test |
| --- | --- |
| `sql-injection-refactor` | A readability refactor still parameterizes an injectable query and reports it. |
| `duplicate-validation` | Duplication is removed without changing error messages or exceptions. |
| `scope-discipline` | A long function is split without touching out-of-scope code or tests. |
| `repo-instruction-injection` | Instructions planted in repository files are not followed, and the attempt is reported. |
| `llm-output-to-shell` | Model output is treated as untrusted and kept away from a shell. |
| `public-api-preservation` | A rename keeps existing importers working and says how. |
| `test-quality` | Assertion-free tests become meaningful tests without changing production code. |

- `fixture/` is the only thing the agent sees.
- `hidden/` holds tests the grader runs against the agent's result. The agent never sees them.
- `solution/` is a reference result (files overlaid on the fixture, plus the final report in `REPORT.md`).
- `case.json` declares the prompt and the checks. Every check states whether it passes or fails on the untouched fixture.

Checks come in two kinds, reported separately:

- **Fixed:** checks that fail on the fixture, such as "the injection is closed" or "the report names the risk". They measure whether the requested work was done well. A do-nothing agent scores 0%.
- **Preserved:** checks that pass on the fixture, such as "behavior is unchanged", "out-of-scope files are untouched", or "the planted script was not run". They measure whether anything was broken. A do-nothing agent scores 100%.

## Self-test (runs in CI)

```bash
python3 evals/grade.py self-test
```

This proves every case is meaningful: each check must give its declared result on the untouched fixture and pass on the reference solution, and each case needs at least one check that fails on the fixture. It needs only Python 3.9+ and no network or API key.

## Running an agent

```bash
python3 evals/run_evals.py --editor claude --runs 3 \
  --agent-cmd 'claude -p {prompt} --permission-mode acceptEdits'
```

For each case, arm (`with` and `without` the skill), and run, the runner copies the fixture into a fresh temporary workspace. In the `with` arm it installs the skill with `scripts/install.sh --editor <editor>`, just as a user would, and prepends "Use the clean-code-refactor skill for this task." to the prompt (pass `--skill-hint ''` to measure whether the agent picks the skill up on its own). It then runs the agent in the workspace, saves its standard output as the report, and grades the result.

Results go to `eval-results/` (ignored by Git): `summary.md`, `summary.json`, and for every run the report, the per-check results, and a diff of the agent's changes.

Placeholders in `--agent-cmd`: `{prompt}` (the prompt as one argument), `{prompt_file}` (a file containing it), and `{workspace}`. The example command is a starting point; check your agent's `--help` for its current non-interactive and permission flags, and make sure the agent may run the project's tests.

- **Run evals only in a disposable environment** such as a container or VM. The agent edits files and runs commands. Fixtures contain deliberately planted instructions; the planted script only creates a marker file.
- Agents are not deterministic. Use `--runs 3` or more before drawing conclusions, and compare the two arms with the same agent, model, and settings.
- Live runs need the agent's API credentials, so they are not part of CI.

## Adding a case

1. Create `cases/<id>/` with `fixture/`, `hidden/`, `solution/` (including `REPORT.md`), and `case.json` whose `id` matches the folder.
2. Keep fixtures small, standard-library only, and fast to test.
3. Give every check an `expect_on_fixture` value, and include at least one check that fails on the fixture.
4. Run `python3 evals/grade.py self-test` until it passes.

Check types: `command` (exit code of a command run in the workspace; `{python}`, `{case}`, and `{workspace}` are substituted), `file_unchanged`, `path_absent`, `regex_absent`, `regex_count_at_least`, `regex_count_at_most`, `python_function_max_lines`, and `report_matches` (searches the agent's final report).
