Scope: reports/summary.py readability cleanup.
Findings:
- [major] reports/summary.py:7 — performance [N+1, CWE-1073]: one orders query ran per customer, so the report issued N+1 queries. Replaced with a single LEFT JOIN with SUM, which keeps customers without orders at 0 and the id order.
Verification: python -m unittest discover -s tests -t . (pass).
