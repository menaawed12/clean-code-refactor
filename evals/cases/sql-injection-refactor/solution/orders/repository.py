import sqlite3


def find_orders(conn: sqlite3.Connection, customer_id, status=None):
    query = "SELECT id, total FROM orders WHERE customer_id = ?"
    params = [customer_id]
    if status:
        query += " AND status = ?"
        params.append(status)
    query += " ORDER BY id"
    rows = conn.execute(query, params).fetchall()
    return [{"id": order_id, "total": total} for order_id, total in rows]
