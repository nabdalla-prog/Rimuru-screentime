# Screen Time for Omarchy

Daily screen time per app, in your Omarchy bar. Click the widget for a popup with today's total, a per-app breakdown and the last seven days.

Fully local: it reads which window is focused, adds up the time, and saves it to a file on your machine. It makes no network requests.

## Install

```bash
omarchy plugin add https://github.com/nabdalla-prog/Rimuru-screentime.git --enable
```

Update later with `omarchy plugin update`. To remove: `omarchy plugin remove nabdalla.screentime`.

## Use

| Action | Result |
|---|---|
| Left click | Open / close the popup |
| Right click | Switch between icon + time and icon only |
| `Esc` | Close the popup |

Bindable from a keyboard shortcut: `omarchy-shell nabdalla.screentime toggle` (also `open`, `close`, `status`).

## What is tracked

- Time is counted per app, using the window's class (e.g. `brave-browser`), once per second while that window has focus.
- Nothing is counted when the session is locked, while the screensaver is showing, when no window has focus, or while the machine is asleep.
- A terminal counts as one app. It does not look inside the terminal to see which program is running.

History is stored at `~/.local/share/omarchy-screentime/history.json`, one entry per day, and the last 365 days are kept. Delete the file to reset. If the file ever becomes unreadable, a copy is kept next to it as `history.json.corrupt-<timestamp>` and tracking starts fresh.

## Security

Omarchy plugins run inside the shell with your user's permissions and are not sandboxed, so read the code before you install any of them. This one is small: `js/Model.js` (pure logic), `qml/Service.qml` (tracking and saving), `qml/BarWidget.qml` and `qml/Panel.qml` (UI). The only commands it runs are `mkdir -p` and `cp` on its own data folder, and `omarchy-shell lock isLocked` to see whether the screen is locked.

## Development

```bash
node --test tests/          # unit tests for js/Model.js
omarchy plugin validate .   # check the manifest
ln -s "$PWD" ~/.config/omarchy/plugins/nabdalla.screentime
omarchy-shell shell rescanPlugins && omarchy plugin enable nabdalla.screentime
```

Saved changes to the widget and panel reload automatically. `qml/Service.qml` stays loaded across hot-reloads, so changes to it need `omarchy restart shell`.
