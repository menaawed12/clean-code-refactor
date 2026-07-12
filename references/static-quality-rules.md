# Self-Contained Static Quality Rules

Apply these rules to added and modified production code without relying on any remote analysis service. Classify a finding as **blocker**, **critical**, **major**, or **minor**. Blockers and critical findings must be resolved before completion; major findings must be resolved or explicitly accepted with a narrow, evidence-based reason. Do not use severity to avoid fixing a real risk.

## Security

- Treat values from requests, files, queues, environment, databases, and third parties as untrusted until validated for type, range, length, format, ownership, and state.
- Require parameterized or typed APIs at SQL, command, template/HTML, path, redirect, deserialization, and network sinks. Never build executable strings from untrusted data.
- Flag hard-coded secrets, insecure defaults, disabled certificate validation, weak or home-grown cryptography, predictable randomness for security decisions, and missing authorization checks as critical.
- Review authentication, authorization, uploads, external URLs, redirects, serialization, dynamic loading, regex denial of service, and logs for contextual security hotspots.
- Do not leak secrets, tokens, personal data, stack traces, or internal identifiers through logs, errors, telemetry, tests, or committed fixtures.

## Reliability

- Flag swallowed exceptions, ignored error results, empty catch blocks, unsafe retries, missing timeouts, missing cancellation propagation, and unbounded waits or queues.
- Ensure files, sockets, transactions, locks, database rows, subscriptions, and background tasks have explicit ownership and deterministic cleanup.
- Reject unchecked nullability, unsafe casts, unchecked indexing, lossy numeric conversions, integer overflow, invalid enum/state transitions, and assumptions about evaluation order.
- Make concurrency safe: define ownership, synchronization, termination, idempotency, ordering, and retry behavior. Avoid blocking work on request or asynchronous execution paths.
- Preserve atomicity for state changes that must succeed or fail together; prevent partial updates, duplicate side effects, and cross-tenant data access.

## Maintainability and Code Smells

- Remove or resolve dead code, unused imports/variables/parameters, unreachable branches, stale feature flags, redundant assignments, and misleading comments.
- Simplify deeply nested control flow, duplicated conditions, long parameter lists, boolean-control flags, hidden side effects, mutable global state, and functions with several unrelated responsibilities.
- Keep dependency direction clear. Do not let presentation, transport, or persistence concerns leak into domain logic without a deliberate boundary.
- Give names domain meaning. Replace magic values with scoped, named concepts when their meaning is not obvious at the use site; avoid generic helpers that conceal behavior or mix unrelated domains.
- Keep comments for intent, constraints, or non-obvious decisions. Update or remove comments that merely repeat code or describe behavior no longer present.

## Duplication and Tests

- Flag copied production code when blocks share the same behavior and reason to change. Do not extract shared code when duplication intentionally separates independent domains, policies, or change cadence.
- Flag duplicated tests only when an extracted fixture, helper, parameterization, or data-driven case improves clarity without hiding the behavior under test.
- Require focused regression coverage for bug fixes and changed branches, failure paths, authorization decisions, boundary values, and security-sensitive behavior where applicable.
- Flag tests with no meaningful assertion, unconditional pass paths, disabled execution, production logic duplicated in test helpers, or dependence on timing, order, or external state without control.

## Gate and Reporting

- Enforce: zero new blocker or critical findings; every security hotspot reviewed; no new actionable duplication; and no reduction in relevant test coverage without an explicit reason.
- Use the repository's approved thresholds when available; otherwise target at least 80% coverage for new executable production code and at most 3% duplicated lines in new code.
- Report each unresolved major or minor finding with severity, file/location, risk, evidence, and the narrow reason for deferral. Never hide a finding through a broad suppression or exclusion.
