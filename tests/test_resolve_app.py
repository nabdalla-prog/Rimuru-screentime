"""Run with: python3 -m unittest discover -s tests"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), os.pardir, "python"))

import resolve_app as R  # noqa: E402


class ProcessName(unittest.TestCase):
    def test_plain_command(self):
        self.assertEqual(R.process_name(["nvim", "notes.md"], "nvim"), "nvim")
        self.assertEqual(R.process_name(["/usr/bin/btop"], "btop"), "btop")

    def test_login_shell_marker_is_stripped(self):
        self.assertEqual(R.process_name(["-bash"], "bash"), "bash")

    def test_interpreter_running_a_script_is_named_after_the_script(self):
        self.assertEqual(R.process_name(["node", "/opt/x/bin/claude"], "node"), "claude")
        self.assertEqual(R.process_name(["python3", "/opt/x/tool.py", "--x"], "python3"), "tool")
        self.assertEqual(R.process_name(["bash", "./deploy.sh"], "bash"), "deploy")

    def test_interpreter_alone_or_with_flags_keeps_its_name(self):
        self.assertEqual(R.process_name(["python3"], "python3"), "python3")
        self.assertEqual(R.process_name(["python3", "-m", "http.server"], "python3"), "python3")
        self.assertEqual(R.process_name(["node", "--version"], "node"), "node")

    def test_falls_back_to_comm(self):
        self.assertEqual(R.process_name([], "kworker"), "kworker")
        self.assertEqual(R.process_name(["", ""], "sleep"), "sleep")
        self.assertEqual(R.process_name(["/"], "init"), "init")

    def test_output_is_one_clean_line(self):
        self.assertEqual(R.clean("a\nb\x00c"), "abc")
        self.assertEqual(len(R.clean("x" * 500)), R.MAX_NAME)


class PickCandidate(unittest.TestCase):
    # (tty, command, created, last_input)
    def test_none_and_single(self):
        self.assertIsNone(R.pick_candidate([], "t"))
        one = (1, "nvim", 10.0, 5.0)
        self.assertEqual(R.pick_candidate([one], ""), one)

    def test_windows_match_ptys_in_creation_order(self):
        old = (2, "claude", 100.0, 1.0)  # created first
        new = (0, "hermes", 200.0, 9.0)  # created later, lower tty number
        # Title and recent input both point at "hermes"; order wins.
        self.assertEqual(R.pick_candidate([new, old], "hermes", (0, 2)), old)
        self.assertEqual(R.pick_candidate([new, old], "claude", (1, 2)), new)

    def test_position_is_ignored_when_counts_differ(self):
        a, b = (1, "bash", 1.0, 1.0), (2, "nvim", 2.0, 1.0)
        # 3 windows but 2 ptys (or tabs): fall through to the other rules.
        self.assertEqual(R.pick_candidate([a, b], "", (0, 3)), b)
        self.assertEqual(R.pick_candidate([a, b], "", (5, 2)), b)  # out of range
        self.assertEqual(R.pick_candidate([a, b], "", None), b)

    def test_title_match_when_position_unknown(self):
        c = [(1, "bash", 1.0, 1.0), (2, "nvim", 2.0, 1.0), (3, "btop", 3.0, 1.0)]
        self.assertEqual(R.pick_candidate(c, "btop", None)[1], "btop")
        self.assertEqual(R.pick_candidate(c, "NVIM main.py", None)[1], "nvim")

    def test_prefers_a_running_command_over_an_idle_shell(self):
        c = [(1, "bash", 1.0, 99.0), (2, "nvim", 2.0, 1.0)]
        self.assertEqual(R.pick_candidate(c, "unrelated", None)[1], "nvim")

    def test_then_the_most_recently_typed_into(self):
        c = [(1, "nvim", 1.0, 10.0), (2, "btop", 2.0, 50.0)]
        self.assertEqual(R.pick_candidate(c, "", None)[1], "btop")

    def test_stable_when_nothing_distinguishes_them(self):
        c = [(9, "bash", 1.0, 1.0), (4, "zsh", 1.0, 1.0)]
        self.assertEqual(R.pick_candidate(c, "", None)[0], 4)


class WindowPosition(unittest.TestCase):
    CLIENTS = [
        {"pid": 7, "address": "0xa"},
        {"pid": 9, "address": "0xb"},
        {"pid": 7, "address": "0xc"},
        "junk",
    ]

    def test_index_among_windows_of_the_same_process(self):
        self.assertEqual(R.window_position(self.CLIENTS, 7, "0xa"), (0, 2))
        self.assertEqual(R.window_position(self.CLIENTS, 7, "0xc"), (1, 2))
        self.assertEqual(R.window_position(self.CLIENTS, 9, "0xb"), (0, 1))

    def test_unknown_window_or_process(self):
        self.assertIsNone(R.window_position(self.CLIENTS, 7, "0xzz"))
        self.assertIsNone(R.window_position(self.CLIENTS, 1, "0xa"))
        self.assertIsNone(R.window_position([], 7, "0xa"))


class PtsNumber(unittest.TestCase):
    def test_decodes_tty_nr(self):
        self.assertEqual(R.pts_number((136 << 8) | 0), 0)
        self.assertEqual(R.pts_number((136 << 8) | 2), 2)
        self.assertEqual(R.pts_number((137 << 8) | 5), 256 + 5)


class Steam(unittest.TestCase):
    def test_class_parsing(self):
        self.assertEqual(R.steam_app_key("steam_app_730"), "730")
        self.assertEqual(R.steam_app_key("steam_app_battlenet"), "battlenet")
        self.assertIsNone(R.steam_app_key("steam"))
        self.assertIsNone(R.steam_app_key(""))
        self.assertIsNone(R.steam_app_key(None))

    def test_acf_name(self):
        text = '"AppState"\n{\n\t"appid"\t\t"730"\n\t"name"\t\t"Counter-Strike 2"\n}'
        self.assertEqual(R.parse_acf_name(text), "Counter-Strike 2")
        self.assertIsNone(R.parse_acf_name("nothing here"))
        self.assertIsNone(R.parse_acf_name(""))

    def test_title_from_manifest_then_window_title(self):
        with tempfile.TemporaryDirectory() as root:
            with open(os.path.join(root, "appmanifest_413150.acf"), "w") as fh:
                fh.write('"AppState"\n{\n\t"name"\t\t"Stardew Valley"\n}\n')
            self.assertEqual(R.steam_title("steam_app_413150", "ignored", [root]), "Stardew Valley")
            # Unknown numeric id: nothing better than the class.
            self.assertIsNone(R.steam_title("steam_app_999", "ignored", [root]))
            # Non-Steam shortcut slug: use the window title.
            self.assertEqual(R.steam_title("steam_app_battlenet", "  Diablo IV ", [root]), "Diablo IV")
            self.assertIsNone(R.steam_title("steam_app_battlenet", "", [root]))
            self.assertIsNone(R.steam_title("firefox", "x", [root]))


class ProcTree(unittest.TestCase):
    """Reads the real /proc, so these only check shape, not particular pids."""

    def test_own_process_is_in_the_tree(self):
        tree = R.process_tree()
        self.assertIn(os.getpid(), tree)
        self.assertEqual(tree[os.getpid()][0], os.getppid())

    def test_descendants_excludes_the_root_and_finds_children(self):
        tree = R.process_tree()
        below = R.descendants(tree, os.getppid())
        self.assertNotIn(os.getppid(), below)
        self.assertIn(os.getpid(), below)

    def test_unreadable_pid_is_none(self):
        self.assertIsNone(R.read_stat(2**30))


if __name__ == "__main__":
    unittest.main()
