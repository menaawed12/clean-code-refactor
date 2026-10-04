import unittest

from textkit.slug import slug, slug_with_prefix


class BehaviorTest(unittest.TestCase):
    def test_slug_edge_cases(self):
        self.assertEqual(slug("---"), "")
        self.assertEqual(slug("Ünïcode Title 2"), "n-code-title-2")

    def test_prefix_edge_cases(self):
        self.assertEqual(slug_with_prefix("post", "!!!"), "post")
        self.assertEqual(slug_with_prefix("p", " A  B "), "p-a-b")
