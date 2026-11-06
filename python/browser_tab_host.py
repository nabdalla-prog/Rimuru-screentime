#!/usr/bin/env python3
"""Chromium native-messaging host for the focused tab, plus user-level installer."""

import json
import os
from pathlib import Path
import re
import struct
import sys
import tempfile
import time


HOST_NAME = "rimuru.screentime.tabs"
STATE = Path.home() / ".local/share/omarchy-screentime/browser-tab.json"
BROWSERS = {
    "brave": "BraveSoftware/Brave-Browser",
    "brave-nightly": "BraveSoftware/Brave-Browser-Nightly",
    "brave-beta": "BraveSoftware/Brave-Browser-Beta",
    "chromium": "chromium",
    "chrome": "google-chrome",
    "vivaldi": "vivaldi",
    "edge": "microsoft-edge",
}
STATE_REFRESH_SECONDS = 20


def install(browser, extension_id, config_home=None):
    if browser not in BROWSERS:
        raise ValueError("browser must be one of: " + ", ".join(BROWSERS))
    if not re.fullmatch(r"[a-p]{32}", extension_id):
        raise ValueError("extension ID must be the 32-letter ID shown by Chromium")
    target = (config_home or Path.home() / ".config") / BROWSERS[browser] / "NativeMessagingHosts" / (HOST_NAME + ".json")
    manifest = {
        "name": HOST_NAME,
        "description": "Local active-tab bridge for Rimuru Screen Time",
        "path": str(Path(__file__).resolve()),
        "type": "stdio",
        "allowed_origins": ["chrome-extension://" + extension_id + "/"],
    }
    if target.exists():
        old = json.loads(target.read_text())
        if old.get("name") != HOST_NAME or old.get("path") != manifest["path"]:
            raise ValueError("refusing to replace a different native host: " + str(target))
        manifest["allowed_origins"] = list(dict.fromkeys(old.get("allowed_origins", []) + manifest["allowed_origins"]))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(manifest, indent=2) + "\n")
    print("Installed " + str(target))


def run_host(state_path=STATE, source=None):
    source = source or sys.stdin.buffer
    last_identity = None
    last_write = 0
    while True:
        length_bytes = source.read(4)
        if not length_bytes:
            return
        if len(length_bytes) != 4:
            return
        length = struct.unpack("=I", length_bytes)[0]
        if length > 8192:
            return
        payload = source.read(length)
        if len(payload) != length:
            return
        try:
            message = json.loads(payload)
        except (ValueError, UnicodeDecodeError):
            continue
        if not isinstance(message, dict):
            continue
        active = message.get("active") is True
        host = message.get("host", "")
        title_key = message.get("titleKey", "")
        if active:
            if not isinstance(host, str) or len(host) > 253 or not re.fullmatch(r"[a-z0-9.-]+", host):
                continue
            if host.startswith("www.") or any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
                                              for label in host.split(".")):
                continue
            if not isinstance(title_key, str) or not re.fullmatch(r"title:[0-9a-f]{1,8}:[0-9a-f]{1,8}", title_key):
                continue
        identity = (active, host, title_key) if active else (False,)
        now = time.time()
        if identity == last_identity and now - last_write < STATE_REFRESH_SECONDS:
            continue
        state = {"active": active, "at": int(now * 1000)}
        if active:
            state.update({"host": host, "titleKey": title_key})
        # The plugin keeps this folder private (0700); create it that way too.
        state_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=".browser-tab-", dir=state_path.parent)
        try:
            with os.fdopen(descriptor, "w") as output:
                json.dump(state, output)
                output.write("\n")
            os.replace(temporary, state_path)
            last_identity = identity
            last_write = now
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--install":
        install(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 2 and sys.argv[1] == "--help":
        print("usage: browser_tab_host.py --install brave|brave-nightly|brave-beta|chromium|chrome|vivaldi|edge EXTENSION_ID")
    else:
        run_host()
