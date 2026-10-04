import unittest

from accounts.service import ValidationError, register_user, update_user


class ServiceTest(unittest.TestCase):
    def test_register_normalizes_email(self):
        store = {}
        self.assertEqual(register_user(store, " Ada ", "Ada@Example.com"), {"name": "Ada", "email": "ada@example.com"})

    def test_update_changes_email(self):
        store = {}
        register_user(store, "Ada", "ada@example.com")
        update_user(store, "ada@example.com", "Ada L", "ada.l@example.com")
        self.assertIn("ada.l@example.com", store)

    def test_register_rejects_duplicate(self):
        store = {}
        register_user(store, "Ada", "ada@example.com")
        with self.assertRaises(ValidationError):
            register_user(store, "Ada", "ADA@example.com")
