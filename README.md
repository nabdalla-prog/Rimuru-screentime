# Screen Time for Omarchy

Daily screen time per app, in your Omarchy bar. Click the widget for a popup with today's total, a per-app breakdown and the last seven days.

Fully local: it reads which window is focused, adds up the time, and saves it to a file on your machine. It makes no network requests.

## Install

```bash
omarchy plugin add https://github.com/nabdalla-prog/Rimuru-screentime.git --enable
```

Update later with `omarchy plugin update`. To remove: `omarchy plugin remove rimuru.screentime`.

Needs Omarchy with Hyprland, a Nerd Font (for the icon) and `python3` (already on Omarchy). Without `python3` it still tracks, but terminals show under the terminal's own name instead of the command running in it.

## Use

| Action | Result |
|---|---|
| Left click | Open / close the popup |
| Right click | Switch between icon + time and icon only |
| `Esc` | Close the popup |

## What is tracked

- Time is counted per app once per second while its window has focus.
- **Terminals** are filed under the command running in them (`nvim`, `btop`, `claude`), not the terminal's name, and follow along as you start and stop commands. A bare shell prompt counts as "Terminal". If a terminal has several tabs, the window title is used to pick the right one.
- **Steam games** show their title instead of `steam_app_730`. Non-Steam shortcuts such as Battle.net use the window title.
- **Browsers** are folded to one name (`brave-browser` and `brave` are both "Brave"), and **Chromium web apps** ("install as app") are filed under their site, the same across profiles.
- Nothing is counted while the session is locked, while the screensaver or a desktop portal dialog has focus, when no window has focus, for apps you ignore, or while the machine is asleep. Time that crosses midnight is split between the two days.

History is stored at `~/.local/share/omarchy-screentime/history.json`, one entry per day, and the last 365 days are kept. Delete the file to reset. If the file ever becomes unreadable, a copy is kept next to it as `history.json.corrupt-<timestamp>` and tracking starts fresh.

## Settings

Three optional settings live in this widget's entry in `~/.config/omarchy/shell.json`, and can be changed with commands (a settings menu is planned):

```bash
omarchy-shell rimuru.screentime goal 6              # daily goal in hours, 0 = off
omarchy-shell rimuru.screentime ignore rofi         # never count this app (and hide its past time)
omarchy-shell rimuru.screentime unignore rofi
omarchy-shell rimuru.screentime rename zen Browser  # show an app under your own name
omarchy-shell rimuru.screentime rename zen ""       # remove the custom name
omarchy-shell rimuru.screentime apps                # today's apps, to see the names to use
```

- **Goal:** once today reaches it, a ✓ appears in the bar. The tooltip shows the time left, and the popup shows a progress bar.
- **Ignore / rename:** use the name shown in the popup (`Brave`, `Nvim`) or the raw window class (`brave-browser`); case doesn't matter. Apps renamed to the same name are merged into one row.

The same settings can be written by hand:

```json
{ "id": "rimuru.screentime", "dailyGoalHours": 6, "ignoredApps": ["rofi", "wofi"], "appNames": { "zen": "Browser" } }
```

Other commands: `open`, `close`, `toggle` (bindable to a key) and `status`.

## Security

Omarchy plugins run inside the shell with your user's permissions and are not sandboxed, so read the code before you install any of them. This one is small: `js/Model.js` (pure logic), `qml/Service.qml` (tracking and saving), `qml/BarWidget.qml` and `qml/Panel.qml` (UI) and `python/resolve_app.py` (looks up the terminal command or Steam title; it only reads `/proc`, `hyprctl activewindow` and Steam's `appmanifest` files, and writes nothing). The other commands it runs are `mkdir -p` and `cp` on its own data folder, and `omarchy-shell lock isLocked` to see whether the screen is locked.

## Development

```bash
node --test tests/                    # unit tests for js/Model.js
python3 -m unittest discover -s tests # unit tests for python/resolve_app.py
omarchy plugin validate .             # check the manifest
ln -s "$PWD" ~/.config/omarchy/plugins/rimuru.screentime
omarchy-shell shell rescanPlugins && omarchy plugin enable rimuru.screentime
```

Saved changes to the widget and panel reload automatically. `qml/Service.qml` stays loaded across hot-reloads, so changes to it need `omarchy restart shell`.
