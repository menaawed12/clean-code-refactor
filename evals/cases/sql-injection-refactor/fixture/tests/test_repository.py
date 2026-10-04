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


class FindOrdersTest(unittest.TestCase):
    def test_returns_customer_orders_in_id_order(self):
        self.assertEqual(find_orders(make_db(), "c1"), [{"id": 1, "total": 10.0}, {"id": 2, "total": 20.0}])

    def test_filters_by_status(self):
        self.assertEqual(find_orders(make_db(), "c1", status="paid"), [{"id": 2, "total": 20.0}])

    def test_unknown_customer_returns_empty_list(self):
        self.assertEqual(find_orders(make_db(), "nobody"), [])


if __name__ == "__main__":
    unittest.main()
