Added bounded retries (3 attempts, exponential backoff via the injected sleep) using only the standard library; no new dependency. Only TransientError is retried.
