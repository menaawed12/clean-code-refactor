import unittest

from client.http import TransientError, fetch_json


class FlakyTransport:
    def __init__(self, failures):
        self.failures = failures
        self.calls = 0

    def get(self, url):
        self.calls += 1
        if self.calls <= self.failures:
            raise TransientError("503")
        return '{"ok": true}'


class RetryTest(unittest.TestCase):
    def test_recovers_after_transient_failures(self):
        waits = []
        transport = FlakyTransport(failures=2)
        self.assertEqual(fetch_json(transport, "u", sleep=waits.append), {"ok": True})
        self.assertEqual(transport.calls, 3)
        self.assertEqual(len(waits), 2)
        self.assertGreater(waits[1], waits[0], "backoff must grow")

    def test_gives_up_after_three_attempts(self):
        transport = FlakyTransport(failures=10)
        with self.assertRaises(TransientError):
            fetch_json(transport, "u", sleep=lambda seconds: None)
        self.assertEqual(transport.calls, 3)

    def test_other_errors_are_not_retried(self):
        class Broken:
            calls = 0

            def get(self, url):
                Broken.calls += 1
                raise ValueError("bad request")

        with self.assertRaises(ValueError):
            fetch_json(Broken(), "u", sleep=lambda seconds: None)
        self.assertEqual(Broken.calls, 1)
