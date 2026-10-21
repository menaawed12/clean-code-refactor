import unittest

from documents.service import PermissionDenied, delete_document, get_document


def store():
    return {"d1": {"owner": "alice", "title": "Plan", "body": "secret plan"}, "d2": {"owner": "bob", "title": "Notes", "body": "notes"}}


class ServiceTest(unittest.TestCase):
    def test_owner_reads_document(self):
        self.assertEqual(get_document(store(), "alice", "d1"), {"id": "d1", "title": "Plan", "body": "secret plan"})

    def test_only_owner_deletes(self):
        with self.assertRaises(PermissionDenied):
            delete_document(store(), "bob", "d1")
