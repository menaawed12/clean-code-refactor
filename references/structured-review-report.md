# Structured Review Report

Use this concise format for non-trivial refactors and reviews:

```text
Scope: <files, component, and requested outcome>
Profile and risk: <selected policy profile; trust/data/contract concerns>
Protected invariants: <behavior, API, authorization, data, and operational constraints>

Findings:
- [severity] <file:location> — <category> [<identifiers>]: <evidence and impact>. <resolution or narrow deferral reason>

Change impact: <callers, consumers, schema/events/cache, migrations, and rollout notes>
Verification: <commands/checks run and outcome>
Not run / exceptions: <tool or check, reason, and residual risk>
```

Use `blocker`, `critical`, `major`, or `minor` severity. State a concrete resolution for blocker and critical findings. For a deferred major or minor finding, include the smallest scope, owner or follow-up mechanism when known, and residual risk.

Tag security findings with identifiers from [standards-mapping.md](standards-mapping.md), for example `[CWE-89, A05:2025]` or `[LLM05, ASI05]`, when the identifier fits the evidence. Omit the brackets otherwise.

## Machine-Readable Output (SARIF)

When the user or the repository's CI asks for machine-readable findings, also emit SARIF 2.1.0, which code-scanning tools ingest. Keep the text report; SARIF does not replace it.

```json
{
  "version": "2.1.0",
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "runs": [{
    "tool": { "driver": { "name": "clean-code-refactor", "version": "<package version>", "rules": [
      { "id": "CCR-SEC-INJECTION", "shortDescription": { "text": "Untrusted data reaches a query sink" },
        "properties": { "tags": ["security", "CWE-89", "A05:2025"] } }
    ] } },
    "results": [{
      "ruleId": "CCR-SEC-INJECTION",
      "level": "error",
      "message": { "text": "<evidence, impact, and resolution>" },
      "locations": [{ "physicalLocation": {
        "artifactLocation": { "uri": "src/orders/repository.py" },
        "region": { "startLine": 42 } } }]
    }]
  }]
}
```

- Map severity to `level`: blocker and critical → `error`, major → `warning`, minor → `note`.
- Use repository-relative URIs with forward slashes. Never include absolute paths, secrets, or personal data.
- Emit only findings that were actually observed. A check that did not run belongs in the text report's "Not run" line, not in SARIF as an empty success.
