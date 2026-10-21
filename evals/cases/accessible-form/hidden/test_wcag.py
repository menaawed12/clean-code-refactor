import unittest
from html.parser import HTMLParser
from pathlib import Path

TEMPLATE = Path("web/templates/signup.html")
UNLABELED_TYPES = {"hidden", "submit", "button", "reset", "image"}


class AccessibilityParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.lang = None
        self.images_without_alt = 0
        self.inputs = []
        self.label_for = set()
        self.open_labels = 0
        self.clickable_non_controls = 0
        self.submit_controls = 0

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "html":
            self.lang = attributes.get("lang")
        elif tag == "img" and "alt" not in attributes:
            self.images_without_alt += 1
        elif tag == "label":
            self.open_labels += 1
            if attributes.get("for"):
                self.label_for.add(attributes["for"])
        elif tag == "input":
            kind = (attributes.get("type") or "text").lower()
            if kind in ("submit", "image"):
                self.submit_controls += 1
            elif kind not in UNLABELED_TYPES:
                named = bool(attributes.get("aria-label") or attributes.get("aria-labelledby"))
                self.inputs.append((attributes.get("id"), named or self.open_labels > 0))
        elif tag == "button" and (attributes.get("type") or "submit").lower() == "submit":
            self.submit_controls += 1
        if "onclick" in attributes and tag not in ("button", "a", "input"):
            self.clickable_non_controls += 1

    def handle_endtag(self, tag):
        if tag == "label" and self.open_labels:
            self.open_labels -= 1


def parse():
    parser = AccessibilityParser()
    parser.feed(TEMPLATE.read_text(encoding="utf-8"))
    return parser


class WcagTest(unittest.TestCase):
    def test_page_language_is_set(self):  # 3.1.1
        self.assertTrue(parse().lang)

    def test_images_have_text_alternatives(self):  # 1.1.1
        self.assertEqual(parse().images_without_alt, 0)

    def test_every_input_has_a_label(self):  # 1.3.1, 3.3.2, 4.1.2
        parser = parse()
        unlabeled = [input_id for input_id, labeled in parser.inputs if not labeled and input_id not in parser.label_for]
        self.assertEqual(unlabeled, [])

    def test_submit_is_a_keyboard_operable_control(self):  # 2.1.1, 4.1.2
        parser = parse()
        self.assertEqual(parser.clickable_non_controls, 0)
        self.assertGreaterEqual(parser.submit_controls, 1)
