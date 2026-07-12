# Language and Runtime Hardening

Read only the sections relevant to the changed files. Prefer the repository's configured compiler, formatter, linter, test runner, and security scanner; use the rules below to review what those tools cannot prove.

## Universal Review

- Preserve public contracts, authorization, data ownership, idempotency, transaction boundaries, and observability before extracting or moving code.
- Treat all external values as hostile until validated for expected type, range, length, format, ownership, and state. Encode for the output context; validation is not HTML, SQL, shell, or URL encoding.
- Use parameter binding or safe framework APIs for data and command sinks. Do not construct executable strings from untrusted values.
- Define timeouts, retries, cancellation, rate limits, and failure behavior for network, queue, filesystem, and third-party operations. Make retries safe to repeat.
- Close, release, or cancel resources deterministically. Bound memory, recursion, concurrency, query size, file size, and pagination.
- Never log credentials, tokens, session identifiers, raw secrets, payment data, or unnecessary PII. Use approved secret storage and least-privilege identities.
- Review licenses, maintained status, integrity hashes/lockfiles, and security advisories before adding dependencies. Do not run installation scripts from untrusted sources.

## Python and Django

- Keep Python code compatible with the repository's declared interpreter. Type public interfaces and complex values where types make nullability, shape, or ownership clearer; do not use `Any` to bypass a design problem.
- Use context managers for files, locks, and clients. Avoid `eval`, `exec`, `pickle` for untrusted data, unsafe YAML loaders, and passing untrusted strings to a shell.
- Use ORM expressions, validated serializer/form input, and parameterized database APIs; never assemble SQL with interpolation. Prevent N+1 queries where a request iterates related data.
- Keep migrations append-only, reversible where practical, and safe for existing rows. Make multi-record updates atomic when partial state violates an invariant.

## JavaScript and TypeScript

- Enable and respect the repository's strictness settings. Represent nullable and discriminated states explicitly; do not use `any`, unsafe assertions, or `@ts-ignore` to conceal an incomplete model.
- Validate data crossing runtime boundaries: HTTP, `postMessage`, storage, environment variables, files, webhooks, and JSON. Types disappear at runtime.
- Avoid `eval`, `Function`, string-based timers, unsafe dynamic imports, and untrusted `child_process` arguments. Prefer structured APIs and allowlists.
- Treat `innerHTML`, `dangerouslySetInnerHTML`, DOM URL sinks, redirects, and regular expressions as security-sensitive. Sanitize only with an established, context-appropriate library when raw HTML is required.
- Await promises deliberately; propagate cancellation with `AbortSignal` where supported; clean up subscriptions, timers, observers, and effects.

## Java and Kotlin

- Use parameterized queries and framework query builders. Avoid native Java deserialization for untrusted input and restrict polymorphic JSON binding.
- Close streams, sockets, statements, and transactions with language-native resource management. Set client timeouts and preserve interrupt/cancellation behavior.
- Make optionality explicit, validate at boundaries, and avoid Kotlin `!!` except after a proven invariant.
- Do not use reflection, class loading, process execution, or path construction on untrusted values without a narrow allowlist and authorization review.

## C# and .NET

- Use strongly typed models, nullable reference annotations, parameterized commands, and output encoding in the appropriate rendering context.
- Make asynchronous code asynchronous end-to-end; avoid `.Result` and `.Wait()` in request paths. Pass cancellation tokens through I/O operations.
- Dispose `IDisposable` and `IAsyncDisposable` resources deterministically. Avoid unsafe binary deserialization and untrusted reflection or process execution.

## Go

- Check and propagate errors with context; do not discard them. Pass `context.Context` through request-bound work and honor cancellation and deadlines.
- Close files, response bodies, rows, and channels correctly. Avoid goroutine leaks by defining ownership, termination, and bounded concurrency.
- Use parameterized database calls, `html/template` for HTML, and argument arrays rather than shell command strings. Validate paths before filesystem access.

## Rust

- Favor type states, ownership, and `Result` propagation over `unwrap` or `expect` in production request or service paths. Give errors useful context without exposing secrets.
- Minimize `unsafe`; isolate it behind a small API with a documented safety contract, tests, and review. Avoid unchecked indexing and integer conversions.
- Bound async tasks and channels, honor cancellation, and avoid blocking work on async executors.

## C and C++

- Prefer memory-safe language features and libraries. Use RAII in C++, explicit ownership in C, checked sizes, and bounded operations; never rely on implicit null termination or integer wraparound.
- Avoid unsafe copying, formatting, and parsing APIs. Validate lengths and indexes before use; treat signed/unsigned conversions and allocator boundaries as high risk.
- Compile with the project's highest practical warnings and use configured sanitizers, static analyzers, and fuzz/property tests for changed parsing or boundary logic.

## PHP, Ruby, and Swift

- Use strict or explicit types where supported and validate at the request boundary. Apply server-side authorization and protect mass assignment with allowlisted attributes.
- Bind SQL parameters and use auto-escaping templates. Do not interpolate user input into queries, shell commands, paths, regexes, or redirects.
- Avoid `unserialize`, `Marshal.load`, `eval`, force unwraps, force casts, dynamic loading, and process execution on untrusted data. Use maintained serializers with restricted types.
- Propagate cancellation through asynchronous work and release external resources predictably.

## SQL and Data Access

- Bind values; never concatenate values into SQL, query-language expressions, or ORM raw fragments. Permit dynamic identifiers only from a fixed allowlist.
- Apply ownership and authorization filters in every query path, including counts, aggregates, exports, background jobs, and cache keys.
- Use transactions for state transitions that must succeed or fail together. Define isolation and locking expectations for concurrent writes.
- Add indexes only from observed query patterns and verify query plans for material performance work. Avoid unbounded queries and exports.

## Shell, CI, and Infrastructure as Code

- Quote variables, avoid `eval`, use argument arrays where available, validate paths, and avoid downloading-and-executing remote content. Do not echo secrets or trace sensitive commands.
- Give CI jobs and deployment identities least privilege. Pin actions, images, and tool versions by immutable reference or the repository's approved policy.
- Keep secrets out of source, state, logs, artifacts, and client bundles. Encrypt state, restrict remote access, and protect production changes with review.
- Make infrastructure changes idempotent, explicit about destructive actions, and tested with the platform's plan/validate mechanism before apply.

## Security-Sensitive Changes Checklist

For authentication, authorization, cryptography, uploads, webhooks, public endpoints, payment/PII, parsers, or external integrations:

1. Identify the assets, attacker-controlled inputs, trust boundaries, and privileged sinks.
2. Confirm authentication, authorization, validation, output encoding, rate limiting, audit logging, and error disclosure at each boundary.
3. Add focused tests for rejection paths and cross-user access where relevant.
4. Run configured SAST, dependency, secret, and infrastructure scans; review results instead of suppressing them broadly.
5. Document residual risk and the explicit reason for any narrowly scoped suppression.
