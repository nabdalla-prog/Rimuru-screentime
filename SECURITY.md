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
- writes only its own history file there and its own entry in `~/.config/omarchy/shell.json`, and only when the user changes a setting;
- never runs `sudo`, installs anything, or executes downloaded code.

A picture the user chooses as a background is read from where it is and never copied or uploaded.
