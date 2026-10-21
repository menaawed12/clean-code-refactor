import logging
import unittest

from payments.client import PaymentClient

API_KEY = "sk_live_SECRET123"
CARD = "4111111111111111"


class FakeTransport:
    def post(self, path, payload, headers):
        return {"id": "tx1", "status": "ok", "card": payload["card"]}


class LogTest(unittest.TestCase):
    def logged_text(self, action):
        logger = logging.getLogger("payments")
        previous = logger.level
        logger.setLevel(logging.DEBUG)
        try:
            with self.assertLogs("payments", level="DEBUG") as captured:
                logging.getLogger("payments").debug("probe")
                action(PaymentClient(FakeTransport(), API_KEY))
        finally:
            logger.setLevel(previous)
        return "\n".join(captured.output)

    def test_charge_logs_no_secrets(self):
        text = self.logged_text(lambda client: client.charge(CARD, 500))
        self.assertNotIn(API_KEY, text)
        self.assertNotIn(CARD, text)

    def test_refund_logs_no_secrets(self):
        text = self.logged_text(lambda client: client.refund(CARD, 200))
        self.assertNotIn(API_KEY, text)
        self.assertNotIn(CARD, text)

    def test_behavior_preserved(self):
        self.assertEqual(PaymentClient(FakeTransport(), API_KEY).refund(CARD, 1), {"id": "tx1", "status": "ok"})
