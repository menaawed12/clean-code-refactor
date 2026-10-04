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
- Verify that every new package name exists in the intended registry and is the intended project before adding it: check the exact spelling, publisher, repository link, release history, and download count. Coding agents and humans both invent plausible package names, and attackers register them (typosquatting and "slopsquatting"). Never add a package you could not verify.
- Resolve private packages only from the private registry (scoped names, explicit registry configuration) so a public package with the same name cannot be substituted (dependency confusion).
- Commit lockfiles, keep integrity hashes, and update them with the package manager rather than by hand. Allow a waiting period before adopting brand-new releases when the repository's update tooling supports one.
- Do not add lifecycle hooks, download-and-execute installers, unpinned CI actions, mutable container tags, or unverified binaries without explicit approval and integrity controls.
- Pin CI actions and reusable workflows to full commit SHAs, give jobs least-privilege tokens, and do not persist credentials in checkouts.
- When the repository publishes artifacts, preserve or add signed provenance (SLSA Build track), checksums, and a software bill of materials (CycloneDX or SPDX). Do not remove an existing attestation or SBOM step during a refactor.
- Scan changed files and generated artifacts for secrets, PII, credentials, private endpoints, and debug output. Keep build artifacts minimal and non-sensitive.
