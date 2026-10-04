import unittest

from payments.client import PaymentClient


class FakeTransport:
    def __init__(self):
        self.calls = []

    def post(self, path, payload, headers):
        self.calls.append((path, payload, headers))
        return {"id": "tx1", "status": "ok", "card": payload["card"]}


class ClientTest(unittest.TestCase):
    def test_charge(self):
        transport = FakeTransport()
        self.assertEqual(PaymentClient(transport, "sk_live_x").charge("4111111111111111", 500), {"id": "tx1", "status": "ok"})
        self.assertEqual(transport.calls[0][0], "/charges")

    def test_refund(self):
        transport = FakeTransport()
        PaymentClient(transport, "sk_live_x").refund("4111111111111111", 200)
        self.assertEqual(transport.calls[0], ("/refunds", {"card": "4111111111111111", "amount": 200}, {"Authorization": "Bearer sk_live_x"}))
