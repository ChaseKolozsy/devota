import importlib.util
import tempfile
import unittest
from pathlib import Path


SERVER_PATH = Path(__file__).with_name("devota_server.py")
SPEC = importlib.util.spec_from_file_location("devota_server_compose", SERVER_PATH)
devota_server = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(devota_server)


class TerminalComposeTests(unittest.TestCase):
    def setUp(self):
        devota_server.COMPOSE_QUEUE.clear()
        devota_server.COMPOSE_TOKEN[0] = ""

    def test_a_proposed_command_is_handed_over_once(self):
        sent = devota_server.propose_terminal_command(
            {"text": "  gh auth status  ", "label": "Claude"}, now=1000)
        taken = devota_server.take_terminal_commands(now=1001)["items"]
        self.assertEqual([(i["id"], i["text"], i["label"]) for i in taken],
                         [(sent["id"], "gh auth status", "Claude")])
        self.assertEqual(devota_server.take_terminal_commands(now=1002)["items"], [])

    def test_commands_expire_and_are_bounded(self):
        devota_server.propose_terminal_command({"text": "old"}, now=0)
        for i in range(devota_server.COMPOSE_MAX_PENDING + 5):
            devota_server.propose_terminal_command({"text": f"cmd {i}"}, now=devota_server.COMPOSE_TTL_SECONDS + i)
        items = devota_server.take_terminal_commands(now=devota_server.COMPOSE_TTL_SECONDS + 30)["items"]
        self.assertEqual(len(items), devota_server.COMPOSE_MAX_PENDING)
        self.assertNotIn("old", [i["text"] for i in items])

    def test_rejects_empty_multiline_and_oversized(self):
        for bad in ({}, {"text": "  "}, {"text": "a\nb"}, {"text": "x" * (devota_server.COMPOSE_MAX_CHARS + 1)}):
            with self.assertRaises(ValueError):
                devota_server.propose_terminal_command(bad)

    def test_loopback_or_the_token_may_propose(self):
        allowed = devota_server.compose_sender_allowed
        self.assertTrue(allowed("127.0.0.1", None))
        self.assertTrue(allowed("::1", None))
        self.assertTrue(allowed("::ffff:127.0.0.1", None))
        # Through a port proxy every sender looks like the proxy host.
        self.assertFalse(allowed("172.26.64.1", None))
        with tempfile.TemporaryDirectory() as tmp:
            token = devota_server.load_compose_token(Path(tmp))
            path = devota_server.compose_token_path(Path(tmp))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(devota_server.load_compose_token(Path(tmp)), token)
        self.assertTrue(allowed("172.26.64.1", token))
        self.assertFalse(allowed("172.26.64.1", token[:-1] + "x"))
        self.assertFalse(allowed("172.26.64.1", ""))


if __name__ == "__main__":
    unittest.main()
