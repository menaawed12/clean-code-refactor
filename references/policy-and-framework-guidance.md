# Policy Profiles and Framework Guidance

## Policy Profiles

| Profile | Use when | Additional gate |
| --- | --- | --- |
| `strict` | New services, auth, payments, PII, security-sensitive work | Resolve all major findings; add negative-path and authorization tests; review threat boundaries. |
| `legacy-safe` | Fragile or low-coverage systems | Preserve behavior first; make isolated changes; baseline pre-existing debt; avoid broad rewrites. |
| `api-service` | HTTP, RPC, GraphQL, queues, events | Validate contracts, idempotency, timeouts, retry semantics, versioning, and error disclosure. |
| `frontend` | Browser UI and client state | Check accessibility, rendering/escaping, navigation, loading/error states, bundle impact, and client-side secrets. |
| `mobile` | Native, Flutter, or React Native apps | Check offline state, lifecycle cleanup, permission boundaries, deep links, secure storage, and platform channels. |
| `data` | ETL, analytics, ML, batch processing | Check schema drift, lineage, PII, reproducibility, sampling bias, cost, bounded data volume, and idempotent reruns. |
| `infrastructure` | IaC, CI/CD, containers, deployment | Check least privilege, immutable pins, secrets, blast radius, idempotency, plan/validate output, and rollback. |

Apply the strictest applicable profile. Record a brief reason when selecting `legacy-safe` for a security-sensitive change.

## Framework-Specific Focus

- **React, Next.js, Angular, Vue:** validate browser inputs at the server boundary; avoid unsafe HTML; preserve accessible names, keyboard behavior, loading/error states, and hydration consistency; do not expose secrets in client bundles.
- **Node.js, NestJS, Express:** validate requests at the edge; propagate cancellation/timeouts; avoid blocking the event loop; use structured logging without secrets; handle promise rejections deliberately.
- **Spring Boot, Quarkus, Micronaut:** validate DTOs; use parameterized data access; preserve transactions and security annotations; avoid unsafe deserialization and broad exception handlers.
- **ASP.NET Core:** use model validation, authorization policies, parameterized data access, cancellation tokens, output encoding, and deterministic disposal; avoid sync-over-async request paths.
- **Django, FastAPI, Flask:** validate serializers/models; enforce object-level authorization; prevent ORM N+1 queries; keep migrations safe for existing data; avoid debug data in production responses.
- **Rails and Laravel:** protect mass assignment; enforce policy/authorization checks; use ORM binding and auto-escaping; make jobs idempotent; keep migrations and queues backward compatible.
- **Flutter and mobile clients:** validate platform/channel data, cancel listeners/controllers, minimize sensitive local storage, and separate view state from domain side effects.
- **Terraform, Kubernetes, Docker:** pin providers/images/actions by project policy, scope identities and network access, avoid plaintext secrets, and validate plans/manifests before applying.
