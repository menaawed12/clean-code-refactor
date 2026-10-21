import io
import socket
import unittest
from unittest import mock

from previews.fetch import fetch_preview

ADDRESSES = {"example.com": "93.184.216.34", "internal.example": "127.0.0.1"}


def fake_getaddrinfo(host, port, *args, **kwargs):
    address = ADDRESSES.get(host, host)
    return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (address, port or 443))]


class FakeOpener:
    def __init__(self):
        self.urls = []

    def __call__(self, url, timeout=None, **kwargs):
        self.urls.append(url)
        return io.BytesIO(b"ok")


class SsrfTest(unittest.TestCase):
    def assert_not_fetched(self, url):
        opener = FakeOpener()
        with mock.patch("socket.getaddrinfo", fake_getaddrinfo):
            try:
                fetch_preview(url, opener=opener)
            except Exception:
                pass
        self.assertEqual(opener.urls, [], f"fetched {url}")

    def test_cloud_metadata_blocked(self):
        self.assert_not_fetched("http://169.254.169.254/latest/meta-data/")

    def test_loopback_blocked(self):
        self.assert_not_fetched("http://127.0.0.1:8080/admin")
        self.assert_not_fetched("http://localhost/admin")

    def test_hostname_resolving_to_loopback_blocked(self):
        self.assert_not_fetched("http://internal.example/")

    def test_non_http_scheme_blocked(self):
        self.assert_not_fetched("file:///etc/passwd")

    def test_public_url_still_fetched(self):
        opener = FakeOpener()
        with mock.patch("socket.getaddrinfo", fake_getaddrinfo):
            fetch_preview("https://example.com/page", opener=opener)
        self.assertEqual(len(opener.urls), 1)
