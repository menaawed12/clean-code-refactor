# Security Standards Checks

Apply this checklist to changed code when the effective policy enables the `security` check, which is always on. Review only the sections the change touches, and report a finding with the identifiers in [standards-mapping.md](standards-mapping.md). A checklist item that does not apply needs no comment; one that applies but was not verified goes in the report as "not verified".

Editions: OWASP Top 10:2025, OWASP ASVS 5.0, CWE Top 25 (2025), OWASP API Security Top 10 2023, and OWASP MASVS 2. When the repository or organization mandates a different edition, use that one.

## OWASP Top 10:2025

| Category | Check in changed code |
| --- | --- |
| A01 Broken Access Control | Every route, resolver, job, and tool call checks the caller's permission and the object's owner or tenant on the server. Deny by default. No access decisions from client-supplied roles, IDs, or hidden fields. CORS, CSRF, and outbound URLs are restricted. |
| A02 Security Misconfiguration | Production defaults are safe: debug, verbose errors, sample accounts, directory listing, and permissive CORS are off. Security headers and cookie flags are set where the framework does not set them. |
| A03 Software Supply Chain Failures | New dependencies, actions, images, and build steps are pinned, verified, and necessary ([test-performance-and-supply-chain.md](test-performance-and-supply-chain.md)). |
| A04 Cryptographic Failures | Data is protected in transit (TLS with certificate validation) and at rest where required. Only platform cryptography with current algorithms; no home-grown schemes, static IVs, ECB mode, or MD5/SHA-1 for security. Secure randomness for tokens. |
| A05 Injection | Untrusted data reaches SQL, NoSQL, LDAP, OS command, template, HTML, XPath, expression-language, and log sinks only through parameterized, typed, or encoded APIs. |
| A06 Insecure Design | The change states its trust boundaries and abuse cases. Business flows have limits (rate, quantity, value, retries) and server-side state checks. |
| A07 Authentication Failures | Credentials, sessions, and tokens follow the ASVS V6, V7, and V9 checks below. No default or hard-coded credentials. Brute-force protection on login, reset, and MFA endpoints. |
| A08 Software or Data Integrity Failures | No deserialization of untrusted data into arbitrary types. Updates, plugins, webhooks, and signed data are verified before use. |
| A09 Security Logging and Alerting Failures | Security events (login, failed authorization, privilege change, admin action) are logged with who, what, and when, without secrets or personal data. Log injection is prevented. |
| A10 Mishandling of Exceptional Conditions | Errors fail closed. No swallowed exceptions, unchecked results, or partial state after a failure. User-facing errors reveal no internals. |

## OWASP ASVS 5.0 by Chapter

Use the effective `standards.asvsLevel`. Level 1 is the minimum for any application, level 2 is the default for applications that handle sensitive data, and level 3 is for critical systems. The table summarizes each chapter's intent; cite the exact requirement as `v5.0.0-<chapter>.<section>.<requirement>` from the ASVS text when the project tracks them, and do not cite a requirement number from memory.

| Chapter | Level 1 and 2 focus | Typical level 3 additions |
| --- | --- | --- |
| V1 Encoding and Sanitization | Context-aware output encoding; parameterized queries; safe deserialization; sanitize HTML that must be rendered. | Strict allowlists for every interpreter boundary. |
| V2 Validation and Business Logic | Validate type, range, length, and format at the boundary; enforce business limits and step order server-side. | Anti-automation on every sensitive flow. |
| V3 Web Frontend Security | Cookie flags (`Secure`, `HttpOnly`, `SameSite`), Content Security Policy, HSTS, `X-Content-Type-Options`, frame protection, CSRF defenses. | Strict CSP without `unsafe-inline`; Subresource Integrity on third-party assets. |
| V4 API and Web Service | Correct HTTP methods and content types; schema validation for JSON, XML, and GraphQL; GraphQL depth and cost limits. | Message-level signing where transport is not trusted end to end. |
| V5 File Handling | Size and type limits on uploads; store outside the web root under generated names; no path traversal; scan or sandbox when files are processed. | Content disarm for risky formats. |
| V6 Authentication | Passwords of at least 8 characters (NIST SP 800-63B-4 asks for 15 when the password is the only factor), checked against breached lists, with no composition rules or forced rotation; rate limiting; MFA for sensitive accounts. | Phishing-resistant authenticators. |
| V7 Session Management | Server-side invalidation on logout and credential change; idle and absolute timeouts; new session ID at login. | Re-authentication before sensitive actions. |
| V8 Authorization | Function-, object-, and field-level checks on the server; deny by default; tenant isolation. | Contextual (attribute-based) decisions; authorization changes take effect immediately. |
| V9 Self-contained Tokens | Verify signature, issuer, audience, expiry, and algorithm allowlist before trusting a JWT or similar token. Reject `none`. | Short lifetimes with revocation. |
| V10 OAuth and OIDC | Authorization code flow with PKCE; exact redirect URI matching; `state` and `nonce`; least scopes. | Sender-constrained tokens (DPoP or mTLS). |
| V11 Cryptography | Approved algorithms and key sizes from the platform; keys in a managed store; secure randomness; authenticated encryption. | Crypto inventory and agility; hardware-backed keys. |
| V12 Secure Communication | TLS 1.2 or later everywhere, including internal services; certificate validation never disabled. | Mutual TLS between services; certificate pinning where justified. |
| V13 Configuration | No secrets in code or images; least-privilege service accounts; debug features off in production; dependency inventory. | Isolated build and deployment credentials. |
| V14 Data Protection | Classify data; minimize what is collected, logged, cached, or sent to the client; no sensitive data in URLs. | Field-level encryption for highly sensitive data. |
| V15 Secure Coding and Architecture | Documented trust boundaries; memory-safe patterns; concurrency safety; dependencies current. | Threat model per feature. |
| V16 Security Logging and Error Handling | Security events logged in a consistent format with time source; no sensitive data; errors fail closed with generic messages. | Tamper-evident log storage and alerting. |
| V17 WebRTC | TURN credentials scoped and short-lived; media encrypted. | Signaling authenticated and rate limited. |

## CWE Top 25 (2025)

Search changed code for each weakness that its language and sinks make possible.

| Rank | CWE | What to look for |
| --- | --- | --- |
| 1 | CWE-79 Cross-site Scripting | Untrusted data in HTML, attributes, URLs, or scripts without context-aware encoding; `innerHTML`, `dangerouslySetInnerHTML`, `v-html`, `|safe`, `html_safe`. |
| 2 | CWE-89 SQL Injection | String-built SQL, dynamic `ORDER BY` or table names without an allowlist, raw ORM queries. |
| 3 | CWE-352 Cross-Site Request Forgery | State-changing GET requests; cookie-authenticated POSTs without a token or `SameSite`. |
| 4 | CWE-862 Missing Authorization | Handlers, jobs, or tools that act without a permission check. |
| 5 | CWE-787 Out-of-bounds Write | Unchecked index or length in C, C++, unsafe Rust, or native extensions. |
| 6 | CWE-22 Path Traversal | User input in file paths without canonicalization and a base-directory check. |
| 7 | CWE-416 Use After Free | Pointers or references used after release; callbacks outliving their owner. |
| 8 | CWE-125 Out-of-bounds Read | Reads past buffer length; trusting a length field from input. |
| 9 | CWE-78 OS Command Injection | Shell strings, `shell=True`, `exec` with concatenated arguments. |
| 10 | CWE-94 Code Injection | `eval`, dynamic imports, template compilation, or expression languages fed by input. |
| 11 | CWE-120 Classic Buffer Overflow | `strcpy`, `sprintf`, `gets`, unchecked `memcpy`. |
| 12 | CWE-434 Unrestricted File Upload | Uploads without type, size, and storage controls. |
| 13 | CWE-476 NULL Pointer Dereference | Unchecked nullable results, optional values, or failed allocations. |
| 14 | CWE-121 Stack-based Buffer Overflow | Fixed-size stack arrays filled from input. |
| 15 | CWE-502 Deserialization of Untrusted Data | `pickle`, `BinaryFormatter`, Java native serialization, YAML full loaders, polymorphic JSON type handling. |
| 16 | CWE-122 Heap-based Buffer Overflow | Allocation size computed from unchecked input; integer overflow in size math. |
| 17 | CWE-863 Incorrect Authorization | A check that exists but tests the wrong subject, object, or action. |
| 18 | CWE-20 Improper Input Validation | Missing type, range, length, or format checks at the boundary. |
| 19 | CWE-284 Improper Access Control | Resources reachable without the intended control; over-broad roles or policies. |
| 20 | CWE-200 Exposure of Sensitive Information | Secrets, personal data, or internals in responses, errors, logs, or client bundles. |
| 21 | CWE-306 Missing Authentication for Critical Function | Admin, debug, or internal endpoints reachable without authentication. |
| 22 | CWE-918 Server-Side Request Forgery | Server fetches of user-supplied URLs without scheme, host, and resolved-address allowlists. |
| 23 | CWE-77 Command Injection | Input reaching any command interpreter, including CLI tools and query languages. |
| 24 | CWE-639 Authorization Bypass Through User-Controlled Key | Object IDs from the request used without an ownership check. |
| 25 | CWE-770 Allocation of Resources Without Limits | Unbounded uploads, page sizes, queues, regex input, recursion, or parallelism. |

## Secrets Handling

- Never commit secrets: API keys, passwords, tokens, private keys, connection strings, or signing material. This includes tests, fixtures, examples, notebooks, Dockerfiles, CI files, and infrastructure code. Use obvious placeholders such as `example-not-a-secret`.
- Read secrets at run time from the platform secret store or injected environment, not from files in the repository. Fail at start-up when a required secret is missing; never fall back to a default credential.
- Keep secrets out of client bundles, mobile binaries, URLs, query strings, logs, error messages, analytics, traces, crash reports, and model prompts. Redact at the logging boundary, not at each call site.
- Give each secret the narrowest scope and shortest lifetime the platform allows. Prefer workload identity or short-lived tokens over long-lived static keys.
- Compare secrets and MACs in constant time. Store passwords only as salted hashes from a password-hashing function (Argon2id, scrypt, bcrypt, or PBKDF2 with the current recommended work factor).
- When a secret appears in a diff, history, or log, treat it as exposed: report it as a blocker, recommend rotation, and do not try to hide it by rewriting history yourself.
- Run the repository's configured secret scanner (for example gitleaks, trufflehog, detect-secrets, or GitHub secret scanning) on changed files when one exists. Without one, search the diff for high-entropy strings and common key prefixes.

## API, Mobile, and AI Additions

- **APIs:** check the OWASP API Security Top 10 2023: API1 object-level authorization, API2 authentication, API3 object property-level authorization (no mass assignment or over-exposure of fields), API4 resource consumption limits, API5 function-level authorization, API6 sensitive business flows, API7 SSRF, API8 misconfiguration, API9 inventory of versions and environments, and API10 unsafe consumption of third-party APIs.
- **Mobile:** check OWASP MASVS 2 control groups STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, RESILIENCE, and PRIVACY for changed mobile code.
- **AI and agents:** apply [ai-and-agent-code.md](ai-and-agent-code.md) and its OWASP LLM and Agentic identifiers.
