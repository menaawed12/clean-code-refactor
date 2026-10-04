# AI, LLM, and Agent Code

Read this when the changed code calls a language model, builds prompts, retrieves context for a model, defines tools or MCP servers, or runs an agent loop. It covers the application code being refactored. For how the coding agent following this skill treats untrusted input, see [agent-security.md](agent-security.md).

Identifiers in brackets refer to the OWASP Top 10 for LLM Applications 2025 (`LLM01`–`LLM10`) and the OWASP Top 10 for Agentic Applications 2026 (`ASI01`–`ASI10`). Cite them in findings; [standards-mapping.md](standards-mapping.md) lists the rest.

## Trust Model

- A prompt is not a security control. Instructions such as "never reveal X" or "only call Y for admins" can be overridden by injected text; enforce the rule in code at the tool, data, or authorization boundary. [LLM01, ASI01]
- Everything a model reads can carry instructions: user messages, retrieved documents, web pages, tool results, file contents, emails, and memory. Treat all of it as untrusted data, the same as a request body. [LLM01, ASI01, ASI06]
- Model output is untrusted input to whatever consumes it next. It inherits the trust level of the least trusted content in the context window that produced it. [LLM05]

## Output Handling at Sinks

- Never pass model output to `eval`, a shell, a SQL string, a template, `innerHTML`, a redirect, a file path, or a deserializer. Use the same parameterized or encoded sink the code would use for user input. [LLM05, ASI05]
- Request structured output with a schema, then validate it in code: types, ranges, enums, lengths, and referenced IDs the caller is authorized to use. Reject or repair invalid output explicitly; do not coerce it silently.
- Run model-generated code only in an isolated sandbox with no credentials, deny-by-default network access, resource limits, and a timeout. Prefer not running it at all. [ASI05]
- Render model text as text. When rich output is required, sanitize with an established, context-appropriate library and block automatic loading of model-supplied URLs (images, links) that could exfiltrate data. [LLM02, LLM05]

## Tools, Agency, and Authorization

- Give each agent or tool the narrowest capability that completes the task: specific operations instead of generic `run_sql`, `http_request`, or `execute` tools; read-only where possible. [LLM06, ASI02]
- Authorize every tool call in code against the end user's identity and permissions, not the agent's service identity. Use short-lived, scoped credentials; never let the model choose which credential to use. [ASI03]
- Validate tool arguments as untrusted input: allowlist identifiers, constrain paths to a root, restrict outbound URLs to approved hosts to prevent server-side request forgery (CWE-918), and bound sizes. [ASI02]
- Require explicit human confirmation for irreversible, costly, or externally visible actions (payments, deletions, sending messages, merging code), and show the user what will actually happen. [ASI09]
- Bound agent loops: maximum steps, tool calls, wall-clock time, and spend per task, with a defined stop state. Make side-effecting tools idempotent or deduplicated so retries do not repeat actions. [LLM10, ASI08]

## MCP Servers and Tool Integrations

- Authenticate clients and authorize each tool invocation; do not expose a tool to every connected client by default.
- Do not pass a client's token through to downstream services. Obtain a separate credential scoped to the downstream call, so the server cannot become a confused deputy.
- Treat tool descriptions, names, and results from third-party servers as untrusted content: they can contain injected instructions. Pin and review the servers and versions the application trusts. [ASI04]
- Validate every input against the declared schema, return only the data the caller is authorized to see, and log invocations without logging secrets.

## Data, Secrets, and Retrieval

- Keep secrets, credentials, and internal-only rules out of prompts and system prompts; assume the full context can be extracted. [LLM02, LLM07]
- Apply authorization when retrieving context: filter documents, embeddings, and memory by tenant and user permission before they reach the model, not after. [LLM08]
- Validate and attribute writes to long-lived memory or vector stores; do not let one user's content become another user's instructions. Expire or scope conversational memory. [ASI06]
- Redact personal data and secrets from prompts, logs, traces, and evaluation datasets unless the data flow is approved.

## Reliability, Cost, and Supply Chain

- Set timeouts, bounded retries with backoff for rate limits and transient errors, and maximum input and output token counts. Handle refusals, truncated output, and empty responses as explicit states. [LLM10]
- Pin model identifiers and SDK versions. Changing the model, temperature, system prompt, or tool set changes behavior, so it is never a "refactor"; treat it as a product change with its own evaluation. [LLM03, ASI04]
- Load model weights only from verified sources in safe formats (for example, safetensors rather than pickle), and verify checksums or signatures. [LLM03]
- Tell users when content is machine-generated, and add checks or citations where wrong answers cause harm. [LLM09]

## Refactoring and Testing Rules

- Keep prompt templates as versioned, reviewable assets, separate from transport and I/O code. Build prompts with structure (roles, delimiters, data fields), not string concatenation of untrusted text into instructions.
- Isolate model calls behind a small interface so tests can substitute a deterministic fake. Unit tests must not call a live model.
- When changing prompts, tools, or model parameters, run the project's evaluation set before and after, and include adversarial cases: injected instructions in retrieved content, cross-tenant retrieval, malformed tool arguments, and excessive-loop scenarios.
- Report AI-specific findings with the LLM or ASI identifier, the sink or tool affected, and the enforcement point added in code.
