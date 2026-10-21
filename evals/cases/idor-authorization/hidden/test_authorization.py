import unittest

from documents.service import PermissionDenied, get_document


def store():
    return {"d1": {"owner": "alice", "title": "Plan", "body": "secret plan"}}


class AuthorizationTest(unittest.TestCase):
    def test_other_user_cannot_read(self):
        with self.assertRaises((PermissionDenied, LookupError)):
            get_document(store(), "mallory", "d1")

    def test_owner_still_reads(self):
        self.assertEqual(get_document(store(), "alice", "d1")["body"], "secret plan")
