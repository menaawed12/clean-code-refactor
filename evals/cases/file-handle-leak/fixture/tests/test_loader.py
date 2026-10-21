import json
import tempfile
import unittest
from pathlib import Path

from ingest.loader import load_records


class LoaderTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, content):
        path = self.root / name
        path.write_text(json.dumps(content), encoding="utf-8")
        return path

    def test_concatenates_records_in_order(self):
        first = self.write("a.json", [{"id": 1}])
        second = self.write("b.json", [{"id": 2}, {"id": 3}])
        self.assertEqual(load_records([first, second]), [{"id": 1}, {"id": 2}, {"id": 3}])

    def test_rejects_a_file_that_is_not_a_list(self):
        bad = self.write("bad.json", {"id": 1})
        with self.assertRaisesRegex(ValueError, "expected a list of records"):
            load_records([bad])
