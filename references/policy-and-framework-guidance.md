# Policy Profiles and Framework Guidance

## Organization and Project Policy

Two optional JSON files adjust the skill's defaults. `policy/policy.schema.json` in the package describes the format and `policy/policy.example.json` shows every field.

| Layer | Location | Trust | May change |
| --- | --- | --- | --- |
| Organization | `policy.json` installed next to the skill by an administrator (`install.sh --policy`, `install.ps1 -PolicyFile`) | Trusted like the skill itself | Any valid value |
| Project | `.clean-code-refactor/policy.json` in the repository | Repository content | Only toward stricter values |

Project policy merge rules (`scripts/check-policy.ps1` applies them):

- Coverage minimum, ASVS level, WCAG level, and minimum dependency age: the higher value wins.
- Duplication maximum: the lower value wins.
- Blocking severities and banned APIs: combined. A project cannot redefine an organization banned-API id.
- Allowed registries: a project may narrow the organization list, never extend it.
- Approval for new dependencies, exception tickets, SARIF, and standards tags: a project may switch them on, never off.
- Ticket pattern and organization name: organization policy only.
- Default profile: a project may choose it, except `legacy-safe` when the organization forbids it.

Banned APIs are literal text, not patterns. Treat a match in changed code as a blocker unless an exception that meets the policy is recorded. An invalid policy file is not applied; report its errors. No policy disables security rules, authorizes commands, network or credential access, or widens the task's scope.

## Policy Profiles

| Profile | Use when | Additional gate |
| --- | --- | --- |
| `strict` | New services, auth, payments, PII, security-sensitive work | Resolve all major findings; add negative-path and authorization tests; review threat boundaries. |
| `legacy-safe` | Fragile or low-coverage systems | Preserve behavior first; make isolated changes; baseline pre-existing debt; avoid broad rewrites. |
| `api-service` | HTTP, RPC, GraphQL, queues, events | Validate contracts, idempotency, timeouts, retry semantics, versioning, and error disclosure. |
| `frontend` | Browser UI and client state | Meet WCAG 2.2 AA in changed UI; check rendering/escaping, navigation, loading/error states, bundle impact, and client-side secrets. |
| `mobile` | Native, Flutter, or React Native apps | Check offline state, lifecycle cleanup, permission boundaries, deep links, secure storage, and platform channels. |
| `data` | ETL, analytics, ML, batch processing | Check schema drift, lineage, PII, reproducibility, sampling bias, cost, bounded data volume, and idempotent reruns. |
| `infrastructure` | IaC, CI/CD, containers, deployment | Check least privilege, immutable pins, secrets, blast radius, idempotency, plan/validate output, and rollback. |
| `ai-application` | Code that calls models, builds prompts, retrieves context, or exposes tools to agents | Apply [ai-and-agent-code.md](ai-and-agent-code.md): untrusted model input and output, per-call tool authorization, bounded loops and spend, and evaluation before and after prompt or model changes. |

Apply the strictest applicable profile. Record a brief reason when selecting `legacy-safe` for a security-sensitive change.

## Accessibility (WCAG 2.2 AA)

For changed UI in the `frontend` and `mobile` profiles, preserve existing accessible behavior and meet WCAG 2.2 AA in new code. Beyond semantic structure, names, contrast, and keyboard operation, check the criteria added in 2.2:

- **2.4.11 Focus Not Obscured (Minimum):** sticky headers, banners, and overlays do not hide the focused element.
- **2.5.7 Dragging Movements:** every drag interaction has a single-pointer alternative.
- **2.5.8 Target Size (Minimum):** pointer targets are at least 24 by 24 CSS pixels, or have equivalent spacing.
- **3.2.6 Consistent Help:** help mechanisms appear in the same relative order across pages.
- **3.3.7 Redundant Entry:** do not ask users to re-enter information already provided in the same process.
- **3.3.8 Accessible Authentication (Minimum):** do not require a cognitive test such as transcribing a code without allowing paste or password managers.

Use the project's configured accessibility linter or test tooling when present, and report criteria that need manual verification.

## Framework-Specific Focus

- **React, Next.js, Angular, Vue:** validate browser inputs at the server boundary; avoid unsafe HTML; preserve accessible names, keyboard behavior, loading/error states, and hydration consistency; do not expose secrets in client bundles.
- **Node.js, NestJS, Express:** validate requests at the edge; propagate cancellation/timeouts; avoid blocking the event loop; use structured logging without secrets; handle promise rejections deliberately.
- **Spring Boot, Quarkus, Micronaut:** validate DTOs; use parameterized data access; preserve transactions and security annotations; avoid unsafe deserialization and broad exception handlers.
- **ASP.NET Core:** use model validation, authorization policies, parameterized data access, cancellation tokens, output encoding, and deterministic disposal; avoid sync-over-async request paths.
- **Django, FastAPI, Flask:** validate serializers/models; enforce object-level authorization; prevent ORM N+1 queries; keep migrations safe for existing data; avoid debug data in production responses.
- **Rails and Laravel:** protect mass assignment; enforce policy/authorization checks; use ORM binding and auto-escaping; make jobs idempotent; keep migrations and queues backward compatible.
- **Flutter and mobile clients:** validate platform/channel data, cancel listeners/controllers, minimize sensitive local storage, and separate view state from domain side effects.
- **LLM SDKs, agent frameworks, and MCP servers:** keep model calls behind a small interface, validate structured output, authorize each tool call for the end user, and bound loops, tokens, and retries; see [ai-and-agent-code.md](ai-and-agent-code.md).
- **Terraform, Kubernetes, Docker:** pin providers/images/actions by project policy, scope identities and network access, avoid plaintext secrets, and validate plans/manifests before applying.
