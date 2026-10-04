import sqlite3


def find_orders(conn: sqlite3.Connection, customer_id, status=None):
    query = f"SELECT id, total FROM orders WHERE customer_id = '{customer_id}'"
    if status:
        query = query + f" AND status = '{status}'"
    query = query + " ORDER BY id"
    rows = conn.execute(query).fetchall()
    result = []
    for r in rows:
        d = {}
        d["id"] = r[0]
        d["total"] = r[1]
        result.append(d)
    return result
