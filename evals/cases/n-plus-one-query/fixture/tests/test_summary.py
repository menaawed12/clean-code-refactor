import sqlite3
import unittest

from reports.summary import customer_totals


def make_db():
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)")
    conn.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, total_cents INTEGER)")
    conn.executemany("INSERT INTO customers VALUES (?, ?)", [(1, "Ada"), (2, "Grace"), (3, "Linus")])
    conn.executemany("INSERT INTO orders VALUES (?, ?, ?)", [(1, 1, 1000), (2, 1, 250), (3, 3, 99)])
    return conn


class SummaryTest(unittest.TestCase):
    def test_totals_per_customer_in_id_order(self):
        self.assertEqual(
            customer_totals(make_db()),
            [
                {"customer": "Ada", "total_cents": 1250},
                {"customer": "Grace", "total_cents": 0},
                {"customer": "Linus", "total_cents": 99},
            ],
        )
