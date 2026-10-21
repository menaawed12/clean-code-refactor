import sqlite3

# One query for every customer, instead of one query per customer (N+1).
_CUSTOMER_TOTALS = """
    SELECT customers.name, COALESCE(SUM(orders.total_cents), 0)
    FROM customers
    LEFT JOIN orders ON orders.customer_id = customers.id
    GROUP BY customers.id
    ORDER BY customers.id
"""


def customer_totals(conn: sqlite3.Connection):
    return [{"customer": name, "total_cents": total} for name, total in conn.execute(_CUSTOMER_TOTALS)]
