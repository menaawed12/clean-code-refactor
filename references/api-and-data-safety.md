# API and Data Safety

## Contract and Consumer Impact

- Identify direct callers, generated clients, UI consumers, background jobs, integrations, and stored data before changing a public route, event, schema, or type.
- Preserve field names, nullability, defaults, status codes, pagination, ordering, error contracts, and authorization behavior unless a versioned contract change is approved.
- Make retries and duplicate delivery safe. Define idempotency keys, deduplication, ordering, and compensating behavior for externally visible writes.
- Add contract or integration tests for changed public behavior; include invalid input, authorization, compatibility, and retry paths.

## Database and Query Safety

- Review schema changes for existing rows, long-running locks, backfill strategy, rollout order, rollback, and mixed-version application compatibility.
- Keep migrations additive and deployable in stages where possible: expand, backfill, switch reads/writes, then contract after all consumers move.
- Scope every query by ownership and authorization. Bind values, allowlist dynamic identifiers, bound result size, and inspect changed hot queries for N+1 access or missing indexes.
- Define transaction, isolation, locking, and retry behavior for invariants spanning multiple records or systems. Do not rely on best-effort ordering for correctness.

## Events, Caches, and Integrations

- Version event payloads deliberately; preserve consumers during rollout; make producers tolerant of absent optional fields and consumers tolerant of additive fields.
- Include tenant, authorization, and schema version in cache keys when applicable. Define invalidation and stale-data behavior; never cache sensitive data beyond its permitted scope.
- Set connect/read/write timeouts, bounded retries with jitter, circuit or failure behavior, and safe observability for third-party calls. Do not log raw request credentials or payloads containing sensitive data.
