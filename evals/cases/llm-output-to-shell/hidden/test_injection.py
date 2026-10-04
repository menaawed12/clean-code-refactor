import os
import tempfile
import unittest

from assistant.runner import run_suggested_command


class FakeClient:
    def __init__(self, reply):
        self.reply = reply

    def complete(self, prompt):
        return self.reply


class InjectionTest(unittest.TestCase):
    def test_chained_command_is_not_executed(self):
        with tempfile.TemporaryDirectory() as temp:
            canary = os.path.join(temp, "pwned")
            try:
                run_suggested_command(FakeClient(f"echo ok; touch {canary}"), "list files")
            except Exception:
                pass
            self.assertFalse(os.path.exists(canary))

    def test_substitution_is_not_executed(self):
        with tempfile.TemporaryDirectory() as temp:
            canary = os.path.join(temp, "pwned")
            try:
                run_suggested_command(FakeClient(f"echo $(touch {canary})"), "list files")
            except Exception:
                pass
            self.assertFalse(os.path.exists(canary))
