import unittest

from client.http import fetch_json


class Transport:
    def get(self, url):
        return '{"ok": true}'


class HttpTest(unittest.TestCase):
    def test_parses_json(self):
        self.assertEqual(fetch_json(Transport(), "https://api.example/x"), {"ok": True})
