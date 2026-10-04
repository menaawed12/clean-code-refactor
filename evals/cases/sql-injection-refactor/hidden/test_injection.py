import sqlite3
import unittest

from orders.repository import find_orders


def make_db():
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id TEXT, status TEXT, total REAL)")
    conn.executemany(
        "INSERT INTO orders VALUES (?, ?, ?, ?)",
        [(1, "c1", "open", 10.0), (2, "c1", "paid", 20.0), (3, "c2", "open", 30.0)],
    )
    return conn


class InjectionTest(unittest.TestCase):
    def test_customer_id_is_not_interpreted_as_sql(self):
        try:
            rows = find_orders(make_db(), "x' OR '1'='1")
        except sqlite3.Error:
            rows = []
        self.assertEqual(rows, [])

    def test_status_is_not_interpreted_as_sql(self):
        try:
            rows = find_orders(make_db(), "c1", status="open' OR customer_id = 'c2")
        except sqlite3.Error:
            rows = []
        self.assertEqual(rows, [])

    def test_behavior_is_preserved(self):
        self.assertEqual(find_orders(make_db(), "c1", status="open"), [{"id": 1, "total": 10.0}])
