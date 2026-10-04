# Standards Mapping

Use this table to tag findings with public identifiers so reviewers and tools can trace them. Tag a finding only when the identifier fits the evidence; an approximate tag is worse than none. Prefer the most specific CWE.

Editions referenced: OWASP Top 10:2025, CWE Top 25 (2025), OWASP Top 10 for LLM Applications 2025, OWASP Top 10 for Agentic Applications 2026, OWASP ASVS 5.0, NIST SP 800-218 Secure Software Development Framework (latest revision), SLSA v1.2, and WCAG 2.2. When the repository or organization mandates a different edition, use that one.

## Rule Areas to Identifiers

| Rule area in this skill | OWASP Top 10:2025 | Typical CWE (2025 Top 25 in bold) |
| --- | --- | --- |
| Missing or incorrect authorization, object ownership, cross-tenant access | A01 Broken Access Control | **CWE-862**, **CWE-863**, **CWE-639**, **CWE-284** |
| Externally controlled URLs and server-side fetches | A01 Broken Access Control | **CWE-918** |
| Cross-site request forgery on state-changing requests | A01 Broken Access Control | **CWE-352** |
| Insecure defaults, debug output, permissive configuration | A02 Security Misconfiguration | CWE-1188, CWE-489 |
| Unpinned, unreviewed, or hallucinated dependencies; unsigned artifacts | A03 Software Supply Chain Failures | CWE-1104, CWE-494, CWE-829 |
| Weak or home-grown cryptography, disabled certificate validation, predictable randomness | A04 Cryptographic Failures | CWE-327, CWE-295, CWE-338 |
| SQL, OS command, code, and template injection | A05 Injection | **CWE-89**, **CWE-78**, **CWE-77**, **CWE-94** |
| Unencoded output in HTML or the DOM | A05 Injection | **CWE-79** |
| Missing threat boundaries, unsafe business flows, missing rate limits | A06 Insecure Design | **CWE-770**, CWE-841 |
| Missing authentication, weak session or credential handling | A07 Authentication Failures | **CWE-306**, CWE-287, CWE-798 |
| Unsafe deserialization, unverified updates or data | A08 Software or Data Integrity Failures | **CWE-502**, CWE-345 |
| Secrets or personal data in logs; missing audit events | A09 Security Logging and Alerting Failures | **CWE-200**, CWE-532, CWE-778 |
| Swallowed errors, fail-open handling, unchecked return values, resource exhaustion | A10 Mishandling of Exceptional Conditions | CWE-390, CWE-252, CWE-636, CWE-755 |
| Path traversal and unrestricted uploads | A01 / A05 | **CWE-22**, **CWE-434** |
| Missing boundary validation | A05 / A06 | **CWE-20** |
| Memory safety in C, C++, Objective-C, and unsafe Rust | (not ranked) | **CWE-787**, **CWE-125**, **CWE-416**, **CWE-120**, **CWE-121**, **CWE-122**, **CWE-476** |

## AI and Agent Code

| Concern ([ai-and-agent-code.md](ai-and-agent-code.md)) | LLM 2025 | Agentic 2026 |
| --- | --- | --- |
| Direct and indirect prompt injection, goal hijack | LLM01 Prompt Injection | ASI01 Agent Goal Hijack |
| Secrets or personal data reaching prompts, outputs, or logs | LLM02 Sensitive Information Disclosure, LLM07 System Prompt Leakage | — |
| Model, SDK, tool, or MCP server provenance | LLM03 Supply Chain | ASI04 Agentic Supply Chain Vulnerabilities |
| Poisoned training data, retrieval corpora, or memory | LLM04 Data and Model Poisoning, LLM08 Vector and Embedding Weaknesses | ASI06 Memory and Context Poisoning |
| Model output reaching code, query, HTML, or shell sinks | LLM05 Improper Output Handling | ASI05 Unexpected Code Execution |
| Over-broad tools, missing per-call authorization | LLM06 Excessive Agency | ASI02 Tool Misuse and Exploitation, ASI03 Identity and Privilege Abuse |
| Unverified generated content presented as fact | LLM09 Misinformation | ASI09 Human-Agent Trust Exploitation |
| Unbounded tokens, loops, retries, or spend | LLM10 Unbounded Consumption | ASI08 Cascading Failures |
| Agent-to-agent messages without authentication | — | ASI07 Insecure Inter-Agent Communication |
| Agents acting outside their mandate without monitoring | — | ASI10 Rogue Agents |

## Process and Delivery Frameworks

- **OWASP ASVS 5.0:** use its requirement IDs when a project has adopted an ASVS level; it is the verification checklist behind the Top 10 categories above.
- **NIST SSDF (SP 800-218):** practice groups PO (prepare the organization), PS (protect the software), PW (produce well-secured software), and RV (respond to vulnerabilities). Supply-chain and release findings usually map to PS; code-level findings to PW.
- **SLSA v1.2:** the Build track (provenance and build integrity) and the Source track (version control, history integrity, and review). Cite the level a delivery change affects.
- **WCAG 2.2:** cite success criteria by number (for example, 2.4.11 Focus Not Obscured, 2.5.8 Target Size) for accessibility findings in the `frontend` and `mobile` profiles.
