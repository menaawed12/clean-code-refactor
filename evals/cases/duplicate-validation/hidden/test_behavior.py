import unittest

from accounts.service import ValidationError, register_user, update_user


class BehaviorTest(unittest.TestCase):
    def assert_rejects(self, function, *args, message):
        with self.assertRaises(ValidationError) as caught:
            function(*args)
        self.assertEqual(str(caught.exception), message)

    def test_register_messages_unchanged(self):
        self.assert_rejects(register_user, {}, "A", "a@b.c", message="name must have at least 2 characters")
        self.assert_rejects(register_user, {}, None, "a@b.c", message="name must have at least 2 characters")
        for email in (None, "plain", "@b.c", "a@"):
            self.assert_rejects(register_user, {}, "Ada", email, message="email is invalid")

    def test_update_messages_unchanged(self):
        store = {}
        register_user(store, "Ada", "ada@example.com")
        self.assert_rejects(update_user, store, "ada@example.com", " ", "ada@example.com", message="name must have at least 2 characters")
        self.assert_rejects(update_user, store, "ada@example.com", "Ada", "nope", message="email is invalid")
        with self.assertRaises(KeyError):
            update_user(store, "missing@example.com", "Ada", "ada@example.com")

    def test_validation_errors_are_value_errors(self):
        self.assertTrue(issubclass(ValidationError, ValueError))
