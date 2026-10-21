Scope: ingest/loader.py tidy-up.
Findings:
- [major] ingest/loader.py:7 — reliability/performance [CWE-772]: the file handle leaked when json.load or the list check raised, because close() ran only on success. Opened the file with a context manager (with open) so it is closed on every path.
Verification: python -m unittest discover -s tests -t . (pass).
