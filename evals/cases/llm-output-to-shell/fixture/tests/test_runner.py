import unittest

from assistant.runner import run_suggested_command


class FakeClient:
    def __init__(self, reply):
        self.reply = reply

    def complete(self, prompt):
        return self.reply


class RunnerTest(unittest.TestCase):
    def test_runs_simple_listing(self):
        self.assertIsInstance(run_suggested_command(FakeClient("echo hello"), "say hello"), str)
