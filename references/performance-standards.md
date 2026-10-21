# Performance Standards Checks

Apply this checklist to changed code when the effective policy enables the `performance` check. Performance findings are usually **major**; one that lets a single request exhaust memory, connections, or CPU is a security finding as well (CWE-400, CWE-770, A06:2025). Measure before claiming an improvement, and never trade correctness, security, or readability for an unmeasured gain.

## Core Web Vitals (browser UI)

Google's thresholds for a "good" experience, measured at the 75th percentile of page loads on mobile and desktop separately. A stricter budget in the effective policy (`standards.webVitals`) replaces them.

| Metric | Measures | Good | Common causes in code |
| --- | --- | --- | --- |
| Largest Contentful Paint (LCP) | Loading | 2.5 s or less | Render-blocking scripts and styles, client-only rendering of the main content, lazy-loading the hero image, unoptimized images, slow server response. |
| Interaction to Next Paint (INP) | Responsiveness | 200 ms or less | Long tasks on the main thread, heavy event handlers, synchronous layout reads after writes, large re-renders, unvirtualized long lists. |
| Cumulative Layout Shift (CLS) | Visual stability | 0.1 or less | Images, ads, and embeds without reserved dimensions; content injected above existing content; late web fonts without `font-display` and fallback metrics. |

In changed UI code:

- Give images and embeds explicit `width` and `height` or an `aspect-ratio`. Serve modern formats at the displayed size with `srcset`. Do not lazy-load the LCP image; give it `fetchpriority="high"` when the framework does not.
- Keep main-thread tasks under 50 ms. Split or defer work with the framework's scheduling APIs, debounce input handlers, and move heavy computation to a worker.
- Avoid layout thrashing: batch DOM reads before writes. Animate `transform` and `opacity`, not layout properties.
- Check the bundle-size impact of new dependencies and imports. Prefer route-level code splitting and tree-shakeable imports. Do not ship server-only code or large data to the client.
- Preserve server rendering, streaming, and caching headers the framework already provides.
- Verify with the project's configured tooling (Lighthouse CI, web-vitals reporting, bundle analyzer, or framework build output) and report which metrics were measured in the lab and which need field data.

Mobile apps use platform equivalents: cold-start time, frame time (16 ms at 60 Hz), and Application Not Responding (ANR) rate on Android. Keep I/O and parsing off the UI thread.

## Algorithmic Complexity

- State the time and space complexity of changed loops over data whose size the caller or user controls. Flag anything worse than O(n log n) on such data unless the input is provably bounded and small.
- Watch for hidden quadratic work: membership tests on lists inside loops, repeated string concatenation in loops in languages where strings are immutable, `array.includes`/`indexOf`/`find` inside a loop, nested scans to join two collections, and sorting inside a loop. Use a set, map, index, or builder.
- Do not recompute an invariant value in a loop. Hoist it, or compute it once and pass it in.
- Bound recursion depth and prefer iteration for input-driven depth.
- Keep regular expressions linear on untrusted input: no nested or overlapping quantifiers (ReDoS, CWE-1333). Use the platform's timeout or a linear-time engine when available.
- Do not optimize code that is not on a measured hot path at the expense of clarity; report the trade-off instead.

## Data Access and I/O

- **N+1 queries:** a query or remote call inside a loop over results is a defect. Fetch related data in one batched query, a join, or the ORM's eager-loading API (`select_related`/`prefetch_related`, `include`, `JOIN FETCH`, `Include`, `preload`). Prove the query count with the test suite's query counter or logging when one exists.
- Paginate or stream every collection whose size is not fixed. Set a maximum page size on the server.
- Select only the columns you need. Check that new filters, joins, and sort orders are backed by an index; review the query plan for changed hot queries.
- Batch writes, and keep transactions short. Never hold a transaction or lock open across a network call.
- Reuse connections through the configured pool; never open a client or connection per request or per loop iteration.
- Set timeouts on every network, database, and queue call. Retries are bounded, use backoff with jitter, and apply only to idempotent operations.
- Cache only with a defined key, size bound, time to live, and invalidation path. Include tenant and authorization context in the key.

## Memory and Resource Leaks

- Every acquired resource has one owner and deterministic release on every path, including errors: `with` in Python, `try-with-resources` in Java, `using`/`await using` in C#, `defer` in Go, RAII and `Drop` in C++ and Rust, `try`/`finally` elsewhere.
- Remove event listeners, observers, subscriptions, intervals, timers, and animation frames when their component, controller, or connection ends. In React, return a cleanup from effects; in Angular, unsubscribe or use the async pipe; in mobile apps, follow lifecycle callbacks.
- Bound every cache, buffer, queue, map used as a cache, and in-memory collection that grows with traffic. Prefer weak references only where the platform documents them for that purpose.
- Do not capture large objects or request-scoped data in long-lived closures, static fields, singletons, or module-level state.
- Stream large files and responses instead of reading them whole. Release native buffers, file handles, and GPU resources promptly.
- Stop background tasks, threads, goroutines, and coroutines on shutdown and cancellation; join or await them. Do not fire and forget work that can fail silently.
- Close HTTP response bodies, database cursors, and result sets, even when the content is not read.

## Concurrency and Throughput

- Never block an event loop or UI thread with synchronous I/O, CPU-heavy work, or `sleep`. Never block on asynchronous work from synchronous code (sync-over-async).
- Bound parallelism with a pool, semaphore, or worker limit. Unbounded fan-out exhausts sockets, memory, and downstream capacity.
- Keep lock scopes small and acquire locks in a consistent order. Do not perform I/O while holding a lock.
- Apply back-pressure: reject or queue work with a bound when a consumer is slower than its producer.

## Measuring

Use the repository's benchmarks, profilers, load tests, and query counters when they exist. Report the measurement, the environment, and the before-and-after numbers. When nothing can be measured, describe the expected complexity change and mark the performance claim as unverified.
