import unittest

from parsing.duration import parse_duration


class DurationTest(unittest.TestCase):
    def test_combined_units(self):
        self.assertEqual(parse_duration("1h30m"), 5400)

    def test_single_units(self):
        self.assertEqual(parse_duration("45s"), 45)
        self.assertEqual(parse_duration("2m"), 120)

    def test_rejects_invalid_input(self):
        for text in ("", "90", "1x", "h1", "1h 30m", None):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_duration(text)
