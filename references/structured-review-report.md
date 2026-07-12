# Structured Review Report

Use this concise format for non-trivial refactors and reviews:

```text
Scope: <files, component, and requested outcome>
Profile and risk: <selected policy profile; trust/data/contract concerns>
Protected invariants: <behavior, API, authorization, data, and operational constraints>

Findings:
- [severity] <file:location> — <category>: <evidence and impact>. <resolution or narrow deferral reason>

Change impact: <callers, consumers, schema/events/cache, migrations, and rollout notes>
Verification: <commands/checks run and outcome>
Not run / exceptions: <tool or check, reason, and residual risk>
```

Use `blocker`, `critical`, `major`, or `minor` severity. State a concrete resolution for blocker and critical findings. For a deferred major or minor finding, include the smallest scope, owner or follow-up mechanism when known, and residual risk.
