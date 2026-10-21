import sqlite3
import unittest

from reports.summary import customer_totals


def make_db(customers):
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)")
    conn.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, total_cents INTEGER)")
    conn.executemany("INSERT INTO customers VALUES (?, ?)", [(i, f"c{i}") for i in range(1, customers + 1)])
    conn.executemany(
        "INSERT INTO orders (customer_id, total_cents) VALUES (?, ?)",
        [(i, cents) for i in range(1, customers + 1, 2) for cents in (100, 23)],
    )
    return conn


class QueryCountTest(unittest.TestCase):
    def test_query_count_does_not_grow_with_customers(self):
        conn = make_db(50)
        statements = []
        conn.set_trace_callback(statements.append)
        result = customer_totals(conn)
        selects = [s for s in statements if s.lstrip().upper().startswith(("SELECT", "WITH"))]
        self.assertLessEqual(len(selects), 2, f"{len(selects)} queries for 50 customers")
        self.assertEqual(len(result), 50)

    def test_behavior_is_preserved(self):
        result = customer_totals(make_db(4))
        self.assertEqual(
            result,
            [
                {"customer": "c1", "total_cents": 123},
                {"customer": "c2", "total_cents": 0},
                {"customer": "c3", "total_cents": 123},
                {"customer": "c4", "total_cents": 0},
            ],
        )
