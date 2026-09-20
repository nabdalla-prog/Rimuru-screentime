#!/usr/bin/env python3
"""Name what the focused window is really showing, when its class isn't enough.

The compositor reports a terminal as "ghostty" and a Steam game as
"steam_app_730". For screen time we want "nvim" and "Counter-Strike 2".

Run with no arguments. It asks Hyprland for the focused window and prints one
line: the command in the terminal's foreground, or the Steam game's title. It
prints nothing when there is nothing better than the window class, and the
caller then falls back to the class. It never writes anything.

Terminals: find the ptys under the terminal's process and report the
foreground process group of the right one, which is the command you would see
running. Terminals like Ghostty run every window in one process, so there can
be several ptys and the process alone doesn't say which window is focused. Then
(1) if the process has as many windows as ptys, they are matched in creation
order (Hyprland lists windows oldest first, and each pty records when it was
created); otherwise (2) a pty whose command name appears in the window title;
otherwise (3) a running command over an idle shell, then the pty typed into most
recently.
"""

import json
import os
import re
import subprocess
import sys

# Programs that are only a launcher for the thing the user actually ran:
# `node /usr/bin/claude` should read as "claude".
INTERPRETERS = {
    "node", "nodejs", "python", "python3", "ruby", "perl", "deno", "bun",
    "bash", "sh", "zsh", "fish", "dash",
}

SHELLS = {"bash", "sh", "zsh", "fish", "dash", "nu", "ksh", "tcsh", "csh", "xonsh"}

MAX_DEPTH = 6
MAX_NAME = 64

STEAM_CLASS = re.compile(r"^steam_app_(.+)$", re.IGNORECASE)
ACF_NAME = re.compile(r'"name"\s*"([^"]*)"')
LIBRARY_PATH = re.compile(r'"path"\s*"([^"]*)"')

STEAM_ROOTS = [
    "~/.steam/steam/steamapps",
    "~/.local/share/Steam/steamapps",
    "~/.steam/root/steamapps",
    "~/.var/app/com.valvesoftware.Steam/.steam/steam/steamapps",
]


# ---- Pure decisions (unit tested) ---------------------------------------------


def clean(name):
    """One printable line, so output can never smuggle in newlines."""
    name = "".join(ch for ch in str(name) if ch.isprintable()).strip()
    return name[:MAX_NAME]


def process_name(args, comm):
    """Display name for a process from its argv and its kernel comm.

    "-bash" is a login shell, "/usr/bin/nvim" is nvim, and an interpreter that
    was given a script ("node /x/bin/claude", "python3 tool.py") is named after
    the script. An interpreter alone, or given only flags, keeps its own name.
    """
    args = [a for a in args if a != ""]
    if not args:
        return clean(comm)
    first = os.path.basename(args[0]).lstrip("-")
    if not first:
        return clean(comm)
    if first.lower() in INTERPRETERS and len(args) > 1 and not args[1].startswith("-"):
        script = os.path.basename(args[1])
        script = re.sub(r"\.(js|mjs|cjs|py|rb|pl|sh)$", "", script)
        if script:
            return clean(script)
    return clean(first)


def pick_candidate(candidates, title, position=None):
    """Choose one candidate when a terminal process owns several ptys.

    candidates: (tty, command_name, created, last_input) tuples.
    position:   (index, count) of the focused window among this process's
                windows in creation order, or None if unknown.
    """
    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0]
    if position is not None:
        index, count = position
        if count == len(candidates) and 0 <= index < count:
            return sorted(candidates, key=lambda c: (c[2], c[0]))[index]
    lowered = (title or "").lower()
    if lowered:
        matches = [c for c in candidates if c[1] and c[1].lower() in lowered]
        if matches:
            return sorted(matches)[0]
    running = [c for c in candidates if c[1].lower() not in SHELLS] or candidates
    return sorted(running, key=lambda c: (-c[3], c[0]))[0]


def window_position(clients, pid, address):
    """(index, count) of a window among the windows of process `pid`, in the
    order Hyprland lists them (oldest first), or None if it isn't found."""
    same = [c for c in clients if isinstance(c, dict) and c.get("pid") == pid]
    for index, client in enumerate(same):
        if client.get("address") == address:
            return index, len(same)
    return None


def pts_number(tty_nr):
    """/dev/pts/N number from a /proc tty_nr (majors 136-143 cover 256 each)."""
    major = (tty_nr >> 8) & 0xFFF
    minor = (tty_nr & 0xFF) | ((tty_nr >> 12) & 0xFFF00)
    return (major - 136) * 256 + minor


def steam_app_key(window_class):
    """The part after steam_app_, or None if this isn't a Steam window."""
    m = STEAM_CLASS.match(window_class or "")
    return m.group(1) if m else None


def parse_acf_name(text):
    """Game title from an appmanifest_*.acf file, or None."""
    m = ACF_NAME.search(text or "")
    return clean(m.group(1)) or None if m else None


def steam_title(window_class, window_title, roots):
    """Title for a Steam window: manifest name for numeric ids, else the window
    title (non-Steam shortcuts like Battle.net report a slug, not an id)."""
    key = steam_app_key(window_class)
    if key is None:
        return None
    if not key.isdigit():
        return clean(window_title) or None
    for root in roots:
        try:
            with open(os.path.join(root, f"appmanifest_{key}.acf"), encoding="utf-8", errors="replace") as fh:
                title = parse_acf_name(fh.read())
        except OSError:
            continue
        if title:
            return title
    return None


# ---- /proc and Hyprland ------------------------------------------------------


def read_stat(pid):
    """(ppid, session, tty_nr, tpgid) from /proc/<pid>/stat, or None."""
    try:
        with open(f"/proc/{pid}/stat", "rb") as fh:
            data = fh.read().decode(errors="replace")
        fields = data[data.rindex(")") + 1 :].split()
        return int(fields[1]), int(fields[3]), int(fields[4]), int(fields[5])
    except (OSError, ValueError, IndexError):
        return None


def read_name(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            args = fh.read().decode(errors="replace").split("\0")
    except OSError:
        args = []
    try:
        with open(f"/proc/{pid}/comm") as fh:
            comm = fh.read().strip()
    except OSError:
        comm = ""
    return process_name(args, comm)


def process_tree():
    """{pid: (ppid, session, tty_nr, tpgid)} for everything readable."""
    tree = {}
    for entry in os.listdir("/proc"):
        if entry.isdigit():
            stat = read_stat(int(entry))
            if stat:
                tree[int(entry)] = stat
    return tree


def descendants(tree, root_pid):
    """Pids below root_pid (not root itself), up to MAX_DEPTH generations."""
    kids = {}
    for pid, (ppid, _s, _t, _g) in tree.items():
        kids.setdefault(ppid, []).append(pid)
    found, frontier = [], [root_pid]
    for _ in range(MAX_DEPTH):
        frontier = [k for p in frontier for k in kids.get(p, [])]
        found.extend(frontier)
        if not frontier:
            break
    return found


def pty_times(tty_nr):
    """(created, last_input) of a pty from its device node. The node is created
    when the pty is allocated; its atime moves when the program reads input."""
    try:
        st = os.stat(f"/dev/pts/{pts_number(tty_nr)}")
    except OSError:
        return 0.0, 0.0
    return st.st_ctime, st.st_atime


def terminal_command(terminal_pid, window_title, locate=None):
    """The foreground command in a terminal window, or None. `locate` returns
    (index, count) for the focused window; it is only called when needed."""
    tree = process_tree()
    ptys = {}
    for pid in descendants(tree, terminal_pid):
        _ppid, _session, tty, tpgid = tree[pid]
        # Only ptys (majors 136-143); a terminal started from a tty, or a
        # daemon, would otherwise report that tty's foreground instead.
        if tty and tpgid > 0 and 136 <= ((tty >> 8) & 0xFFF) <= 143:
            ptys[tty] = tpgid
    candidates = []
    for tty, tpgid in ptys.items():
        name = read_name(tpgid)
        if name:
            created, seen = pty_times(tty)
            candidates.append((tty, name, created, seen))
    position = locate() if locate and len(candidates) > 1 else None
    chosen = pick_candidate(candidates, window_title, position)
    return chosen[1] if chosen else None


def active_window():
    out = subprocess.run(
        ["hyprctl", "activewindow", "-j"],
        check=False, capture_output=True, text=True, timeout=2,
    ).stdout
    info = json.loads(out)
    return info if isinstance(info, dict) else {}


def clients():
    out = subprocess.run(
        ["hyprctl", "clients", "-j"],
        check=False, capture_output=True, text=True, timeout=2,
    ).stdout
    data = json.loads(out)
    return data if isinstance(data, list) else []


def steam_roots():
    roots = [os.path.expanduser(r) for r in STEAM_ROOTS]
    # Extra libraries (other drives) are listed in libraryfolders.vdf.
    for root in list(roots):
        try:
            with open(os.path.join(root, "libraryfolders.vdf"), encoding="utf-8", errors="replace") as fh:
                for path in LIBRARY_PATH.findall(fh.read()):
                    extra = os.path.join(path, "steamapps")
                    if extra not in roots:
                        roots.append(extra)
        except OSError:
            continue
    return roots


def main():
    try:
        window = active_window()
    except (ValueError, OSError, subprocess.SubprocessError):
        return
    window_class = str(window.get("class") or "")
    window_title = window.get("title") if isinstance(window.get("title"), str) else ""

    if steam_app_key(window_class) is not None:
        name = steam_title(window_class, window_title, steam_roots())
    else:
        try:
            pid = int(window.get("pid") or 0)
        except (TypeError, ValueError):
            pid = 0
        def locate():
            try:
                return window_position(clients(), pid, window.get("address"))
            except (ValueError, OSError, subprocess.SubprocessError):
                return None

        name = terminal_command(pid, window_title, locate) if pid > 0 else None

    if name:
        print(name)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # never crash the caller; it falls back to the class
        print(f"resolve_app: {exc}", file=sys.stderr)
