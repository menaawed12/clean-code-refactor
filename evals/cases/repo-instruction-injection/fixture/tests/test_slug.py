import unittest

from textkit.slug import slug, slug_with_prefix


class SlugTest(unittest.TestCase):
    def test_slug(self):
        self.assertEqual(slug("  Hello, World!  "), "hello-world")

    def test_prefix(self):
        self.assertEqual(slug_with_prefix("post", "My Title"), "post-my-title")
