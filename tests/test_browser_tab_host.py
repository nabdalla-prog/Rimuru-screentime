import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "python/browser_tab_host.py"
SPEC = importlib.util.spec_from_file_location("browser_tab_host", SOURCE)
host = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(host)


def frame(message):
    payload = json.dumps(message).encode()
    return struct.pack("=I", len(payload)) + payload


class BrowserTabHostTests(unittest.TestCase):
    def test_installer_registers_only_the_given_extension_and_preserves_existing_ids(self):
        first = "a" * 32
        second = "b" * 32
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            host.install("brave-nightly", first, config)
            path = config / "BraveSoftware/Brave-Browser-Nightly/NativeMessagingHosts/rimuru.screentime.tabs.json"
            manifest = json.loads(path.read_text())
            self.assertEqual(manifest["path"], str(SOURCE))
            self.assertEqual(manifest["allowed_origins"], ["chrome-extension://" + first + "/"])
            host.install("brave-nightly", second, config)
            self.assertEqual(len(json.loads(path.read_text())["allowed_origins"]), 2)

    def test_framed_active_tab_is_saved_locally(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "browser-tab.json"
            host.run_host(path, io.BytesIO(frame({"active": True, "host": "github.com", "titleKey": "title:abc:123"})))
            state = json.loads(path.read_text())
            self.assertEqual(state["host"], "github.com")
            self.assertEqual(state["titleKey"], "title:abc:123")
            self.assertNotIn("title", state)
            self.assertTrue(state["active"])
            self.assertIsInstance(state["at"], int)

    def test_invalid_host_does_not_replace_last_good_state(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "browser-tab.json"
            stream = io.BytesIO(frame({"active": True, "host": "github.com", "titleKey": "title:abc:123"}) +
                                frame({"active": True, "host": "../../bad", "titleKey": "title:abc:123"}))
            host.run_host(path, stream)
            self.assertEqual(json.loads(path.read_text())["host"], "github.com")

    def test_inactive_message_clears_tab(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "browser-tab.json"
            host.run_host(path, io.BytesIO(frame({"active": False})))
            self.assertEqual(json.loads(path.read_text())["active"], False)

    def test_unchanged_state_refreshes_slowly_and_changes_write_immediately(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "browser-tab.json"
            github = {"active": True, "host": "github.com", "titleKey": "title:abc:123"}
            youtube = {"active": True, "host": "youtube.com", "titleKey": "title:abc:123"}
            new_title = {"active": True, "host": "youtube.com", "titleKey": "title:def:456"}
            messages = [github, github, github, github, youtube, new_title, new_title, {"active": False}, {"active": False}]
            times = [100, 102, 119, 120, 121, 122, 123, 124, 125]
            stream = io.BytesIO(b"".join(frame(message) for message in messages))
            with patch.object(host.time, "time", side_effect=times), patch.object(host.os, "replace", wraps=host.os.replace) as replace:
                host.run_host(path, stream)
            self.assertEqual(replace.call_count, 5)
            self.assertEqual(json.loads(path.read_text()), {"active": False, "at": 124000})


if __name__ == "__main__":
    unittest.main()
