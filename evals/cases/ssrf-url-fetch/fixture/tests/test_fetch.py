import io
import unittest

from previews.fetch import fetch_preview


class FakeOpener:
    def __init__(self):
        self.urls = []

    def __call__(self, url, timeout):
        self.urls.append(url)
        return io.BytesIO(b"<html>hello</html>")


class FetchTest(unittest.TestCase):
    def test_returns_preview_text(self):
        self.assertEqual(fetch_preview("https://93.184.216.34/page", opener=FakeOpener()), "<html>hello</html>")
