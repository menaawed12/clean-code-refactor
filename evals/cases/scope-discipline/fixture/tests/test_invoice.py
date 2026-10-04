import unittest

from billing.invoice import build_invoice


class InvoiceTest(unittest.TestCase):
    def test_totals(self):
        invoice = build_invoice("c1", [{"sku": "a", "unit_price": 10.0, "quantity": 2}], "EU")
        self.assertEqual((invoice["subtotal"], invoice["tax"], invoice["total"]), (20.0, 4.0, 24.0))

    def test_percent_coupon(self):
        invoice = build_invoice("c1", [{"sku": "a", "unit_price": 10.0, "quantity": 1}], "US", {"type": "percent", "value": 10})
        self.assertEqual(invoice["total"], 9.0)
