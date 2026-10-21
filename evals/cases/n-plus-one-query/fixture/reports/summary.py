import sqlite3


def customer_totals(conn: sqlite3.Connection):
    customers = conn.execute("SELECT id, name FROM customers ORDER BY id").fetchall()
    out = []
    for c in customers:
        rows = conn.execute("SELECT total_cents FROM orders WHERE customer_id = ?", (c[0],)).fetchall()
        t = 0
        for r in rows:
            t = t + r[0]
        out.append({"customer": c[1], "total_cents": t})
    return out
