Scope: orders/repository.py readability refactor.
Findings:
- [critical] orders/repository.py:5 — security [CWE-89, A05:2025]: customer_id and status were interpolated into SQL. Replaced with a parameterized query.
Verification: python -m unittest discover -s tests -t . (pass).
