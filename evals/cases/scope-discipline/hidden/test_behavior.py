import unittest

from billing.invoice import build_invoice


ITEMS = [{"sku": "a", "unit_price": 19.99, "quantity": 3}, {"sku": "b", "unit_price": 0.1, "quantity": 7}]


class BehaviorTest(unittest.TestCase):
    def test_full_result_shape_and_values(self):
        self.assertEqual(
            build_invoice("c9", ITEMS, "XX", {"type": "fixed", "value": 5}),
            {
                "customer": "c9",
                "lines": [{"sku": "a", "quantity": 3, "amount": 59.97}, {"sku": "b", "quantity": 7, "amount": 0.7}],
                "subtotal": 60.67,
                "discount": 5,
                "tax": 5.57,
                "total": 61.24,
            },
        )

    def test_fixed_coupon_capped_at_subtotal(self):
        self.assertEqual(build_invoice("c", [{"sku": "a", "unit_price": 1.0, "quantity": 1}], "US", {"type": "fixed", "value": 50})["total"], 0.0)

    def test_errors_unchanged(self):
        for args, message in (
            (("c", [], "EU"), "an invoice needs at least one item"),
            (("c", [{"sku": "a", "unit_price": 1.0, "quantity": 0}], "EU"), "quantity must be positive"),
            (("c", ITEMS, "EU", {"type": "bogo", "value": 1}), "unknown coupon type"),
        ):
            with self.assertRaises(ValueError) as caught:
                build_invoice(*args)
            self.assertEqual(str(caught.exception), message)
