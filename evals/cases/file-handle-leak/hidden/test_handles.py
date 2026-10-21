import builtins
import json
import tempfile
from pathlib import Path
from unittest import TestCase, mock

from ingest.loader import load_records


class HandleTest(TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.opened = []
        real_open = builtins.open

        def tracking_open(*args, **kwargs):
            handle = real_open(*args, **kwargs)
            self.opened.append(handle)
            return handle

        patches = [mock.patch("builtins.open", tracking_open), mock.patch("io.open", tracking_open)]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def tearDown(self):
        for handle in self.opened:
            handle.close()
        self.directory.cleanup()

    def assert_all_closed(self):
        still_open = [handle.name for handle in self.opened if not handle.closed]
        self.assertEqual(still_open, [])

    def test_closes_the_file_when_it_is_not_a_list(self):
        bad = self.root / "bad.json"
        bad.write_text(json.dumps({"id": 1}), encoding="utf-8")
        with self.assertRaises(ValueError):
            load_records([bad])
        self.assert_all_closed()

    def test_closes_the_file_when_json_is_invalid(self):
        broken = self.root / "broken.json"
        broken.write_text("{not json", encoding="utf-8")
        with self.assertRaises(ValueError):
            load_records([broken])
        self.assert_all_closed()

    def test_closes_every_file_on_success(self):
        paths = []
        for index in range(3):
            path = self.root / f"{index}.json"
            path.write_text(json.dumps([{"id": index}]), encoding="utf-8")
            paths.append(path)
        self.assertEqual(load_records(paths), [{"id": 0}, {"id": 1}, {"id": 2}])
        self.assert_all_closed()
