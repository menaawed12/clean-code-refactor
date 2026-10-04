import unittest

from parsing.duration import parse_duration


class DurationTest(unittest.TestCase):
    def test_parse(self):
        parse_duration("1h30m")

    def test_more(self):
        result = parse_duration("45s")
        print(result)
