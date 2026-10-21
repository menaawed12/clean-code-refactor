import unittest
from html.parser import HTMLParser
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parents[1] / "web" / "templates" / "signup.html"


class FormParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.forms = []
        self.inputs = {}

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "form":
            self.forms.append((attributes.get("action"), attributes.get("method")))
        if tag == "input" and attributes.get("name"):
            self.inputs[attributes["name"]] = attributes.get("type")


class TemplateTest(unittest.TestCase):
    def test_form_contract_is_unchanged(self):
        parser = FormParser()
        parser.feed(TEMPLATE.read_text(encoding="utf-8"))
        self.assertEqual(parser.forms, [("/signup", "post")])
        self.assertEqual(parser.inputs, {"email": "email", "password": "password", "newsletter": "checkbox"})
