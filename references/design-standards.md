# Design Standards Checks

Apply this checklist to changed code when the effective policy enables the `design` check, and the accessibility section when it enables `accessibility`. Design findings are usually **major** or **minor**. Use the principles to judge a change, not to justify new layers: the smallest design that keeps responsibilities clear wins, and a refactor never adds an abstraction that has only one implementation and no test or boundary need.

## SOLID

| Principle | Check in changed code | Smell that signals a violation |
| --- | --- | --- |
| Single Responsibility | Each class, module, or function has one reason to change and one level of abstraction. | Names with "and", "Manager", "Util", or "Helper"; functions that validate, persist, and notify at once. |
| Open/Closed | New variants are added by adding code (a new strategy, handler, or table entry), not by editing a growing conditional. | `switch` or `if` chains on a type code repeated in several places. |
| Liskov Substitution | Subtypes honor the base contract: no stronger preconditions, weaker postconditions, new exceptions, or ignored methods. | Overrides that throw "not supported", type checks on the concrete subclass. |
| Interface Segregation | Callers depend on the narrow interface they use. | Large interfaces with methods most implementers stub out; test doubles that implement unrelated methods. |
| Dependency Inversion | Domain logic depends on abstractions it owns; infrastructure implements them. Dependencies are passed in, not constructed inside. | `new`/direct construction of database, HTTP, clock, or file-system clients inside domain code; hard-to-test global state. |

## Clean Architecture and Modularity

- **Dependency rule:** source dependencies point inward, from frameworks and I/O to application services to domain. Domain code imports no web framework, ORM, HTTP client, or UI library.
- Keep the layers the repository already has (for example, controller, service, repository; or ports and adapters; or feature modules). Do not invent a new layering scheme in a refactor; follow the nearest existing module.
- Keep framework types (request objects, ORM entities, UI events) at the edges. Map them to domain types at the boundary.
- No cycles between modules or packages. Use the repository's dependency-rule tooling when configured (for example ArchUnit, dependency-cruiser, import-linter, NetArchTest, or ESLint boundaries).
- Favor high cohesion and low coupling: things that change together live together; modules communicate through small, explicit interfaces.
- Prefer composition over inheritance. Inheritance more than two levels deep in new code needs a reason.
- Apply DRY to knowledge, not to text; KISS and YAGNI to everything else. Prefer the simplest structure that passes the tests.
- Respect the effective `gates.cognitiveComplexityMax` (default 15) for changed functions, as reported by the repository's analyzer. Without an analyzer, count nesting and branching by hand and split functions that are clearly over the limit.

## API Design

Follow the guidelines the repository or organization has adopted (for example the Google API Improvement Proposals, the Microsoft REST API Guidelines, the Zalando RESTful API Guidelines, or an internal style guide). Without one, check:

- **Resources and methods:** nouns for resources, plural collection names, consistent casing. HTTP methods follow RFC 9110 semantics: `GET` is safe and cacheable, `PUT` and `DELETE` are idempotent, `POST` creates or performs actions, `PATCH` applies partial updates.
- **Status codes:** `201` with `Location` for creation, `204` for no content, `400` for invalid input, `401` versus `403` correctly, `404` without revealing existence when authorization fails, `409` for conflicts, `422` for semantic validation where the API already uses it, `429` with `Retry-After` for rate limits. Never `200` with an error body.
- **Errors:** one consistent error format, preferably RFC 9457 Problem Details (`application/problem+json`), with a stable machine-readable type and no stack traces or internal identifiers.
- **Collections:** pagination by default with a maximum page size; cursor-based pagination for large or changing data; stable ordering; filtering and sorting through allowlisted fields.
- **Idempotency and concurrency:** idempotency keys for retried `POST` operations that create side effects; `ETag` with `If-Match` for optimistic concurrency.
- **Compatibility and versioning:** additive changes only within a version; removing or renaming fields, changing types, or tightening validation is a breaking change that needs a new version and a deprecation period (`Deprecation` and `Sunset` headers where used).
- **Contracts:** keep the OpenAPI, AsyncAPI, GraphQL, or protobuf definition in sync with the code, and validate requests and responses against it in tests where the project does. Lint it with the configured linter (for example Spectral, buf, or graphql-schema-linter).
- **GraphQL and gRPC:** for GraphQL, limit query depth and cost, use connections for pagination, and authorize in resolvers; for gRPC and protobuf, never reuse or renumber field numbers and use the standard status codes.

## Accessibility and UI Design

Apply when the change touches user interface code and the effective policy enables `accessibility`. Meet the effective `standards.wcagLevel` of WCAG 2.2 (AA by default). Each level includes the ones below it.

**Level A (always):**

- Text alternatives for meaningful images and icons (1.1.1); empty `alt` for decorative ones.
- Semantic structure: headings, lists, landmarks, tables with headers, and form labels exposed to assistive technology (1.3.1).
- Every function is operable by keyboard with no keyboard trap (2.1.1, 2.1.2). Use native `button`, `a`, and form elements before ARIA; a clickable `div` needs a role, `tabindex`, and key handling, so prefer a `button`.
- Focus order follows meaning (2.4.3); link purpose is clear in context (2.4.4); the page has a title (2.4.2) and a language (3.1.1).
- Inputs have labels or instructions (3.3.2), and errors are identified in text (3.3.1).
- Every control has an accessible name, role, and state (4.1.2) that matches its visible label (2.5.3).
- Information is not conveyed by color alone (1.4.1).

**Level AA (default):**

- Contrast of at least 4.5:1 for text and 3:1 for large text (1.4.3), and 3:1 for UI components and focus indicators (1.4.11).
- Content reflows at 320 CSS pixels wide without two-dimensional scrolling (1.4.10) and survives 200% text resize (1.4.4) and increased text spacing (1.4.12).
- A visible focus indicator (2.4.7) that is not hidden by sticky content (2.4.11).
- Status messages are announced without moving focus (4.1.3), for example with `role="status"` or `aria-live`.
- Error suggestions are given (3.3.3), and legal, financial, or data-changing submissions can be reviewed, corrected, or reversed (3.3.4).
- The WCAG 2.2 additions: dragging has a single-pointer alternative (2.5.7), targets are at least 24 by 24 CSS pixels or spaced (2.5.8), help appears in a consistent place (3.2.6), information is not requested twice in one process (3.3.7), and authentication needs no cognitive test without an alternative such as paste or a password manager (3.3.8).

**Level AAA (when required):** contrast of 7:1 (1.4.6), focus not obscured at all (2.4.12), target size of 44 by 44 CSS pixels (2.5.5), and authentication with no cognitive test at all (3.3.9).

Beyond conformance:

- Follow the WAI-ARIA Authoring Practices for custom widgets (dialogs, menus, tabs, comboboxes): roles, keyboard interaction, and focus management. Return focus to the trigger when a dialog closes.
- Respect `prefers-reduced-motion` and `prefers-color-scheme` where the design system supports them.
- Use the design system's tokens and components for color, spacing, type, and states instead of hard-coded values, so contrast and consistency hold across themes.
- Every view that loads data has loading, empty, error, and success states.
- Do not hard-code user-facing strings, date formats, or text direction when the project is localized.
- Run the configured accessibility tooling (for example axe-core, eslint-plugin-jsx-a11y, Lighthouse, pa11y, or platform accessibility scanners) and list the criteria that still need a manual check with a keyboard and a screen reader.
