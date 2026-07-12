# Test, Performance, and Supply-Chain Review

## Test Quality

- Test observable outcomes, not implementation details. Add focused regression coverage for changed branches, rejection paths, boundary values, authorization, and failure handling.
- Flag tests without meaningful assertions, tests that duplicate production algorithms, disabled tests, broad mocks that hide contract errors, and order-, timing-, locale-, or network-dependent tests without control.
- Recommend property, fuzz, mutation, or contract testing when parser, validation, serialization, financial, concurrency, or high-risk boundary logic changes. Use them when the repository supports them; do not install tooling unless asked.

## Performance and Resilience

- Flag unbounded reads, recursion, retries, pagination, queues, uploads, fan-out, cache growth, and parallelism. Set explicit limits appropriate to the product contract.
- Avoid remote calls inside loops, repeated serialization/parsing, accidental N+1 queries, synchronous work on event loops, and allocation-heavy hot paths.
- Measure before claiming a performance improvement. Preserve correctness under timeout, cancellation, overload, partial failure, and retry.

## Dependency and Delivery Safety

- Review dependency additions for maintenance, license compatibility, advisories, lockfile integrity, transitive impact, and necessity. Prefer existing approved dependencies.
- Do not add lifecycle hooks, download-and-execute installers, unpinned CI actions, mutable container tags, or unverified binaries without explicit approval and integrity controls.
- Scan changed files and generated artifacts for secrets, PII, credentials, private endpoints, and debug output. Keep build artifacts minimal and non-sensitive.
