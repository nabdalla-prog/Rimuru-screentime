# Security policy

## Reporting a vulnerability

Please report security problems privately rather than in a public issue: use GitHub's [private vulnerability reporting](https://github.com/nabdalla-prog/Rimuru-screentime/security/advisories/new) on this repository. Include what you found, how to reproduce it, and the plugin version (`omarchy-shell rimuru.screentime status`).

This is a small volunteer project. Expect a first reply within about a week. Reports are fixed on `main` and credited in the changelog unless you prefer to stay anonymous.

## Supported versions

Only the latest release is supported.

## What the plugin does, for reviewers

Omarchy plugins run inside the shell with your user's permissions and are not sandboxed. This one:

- makes **no network requests** and contains no telemetry;
- reads the focused window's class through Quickshell, and `/proc`, `hyprctl activewindow` and Steam `appmanifest` files (in `python/resolve_app.py`, which writes nothing);
- runs only `mkdir -p` and `cp` on its own data folder (`~/.local/share/omarchy-screentime/`), `omarchy-shell lock isLocked` and `python3`;
- writes its own history file there automatically and updates its own entry in `~/.config/omarchy/shell.json` when the user changes a setting;
- never runs `sudo`, installs anything, or executes downloaded code.

The optional Chromium companion is separate from the shell plugin. Its extension reads the active tab's URL hostname and hashes its title locally to match the focused window. It sends only that hostname and hash through Chromium native messaging to `python/browser_tab_host.py`. It does not send page titles, full URLs or page contents. The host writes a local `browser-tab.json` state file; when explicitly run with `--install`, it writes a user-level native messaging manifest for the selected browser. It never runs `sudo`.

A picture the user chooses as a background is read from where it is and never copied or uploaded.
