# Screen Time for Omarchy

Daily screen time per app, in your Omarchy bar. Click the widget for a popup with a donut chart of the day's apps, a week-by-week trend you can page back through, a few insights, and a yearly overview with month-by-month bars and highlights.

Fully local: it reads which window is focused, adds up the time, and saves it to a file on your machine. It makes no network requests.

## Install

```bash
omarchy plugin add https://github.com/nabdalla-prog/Rimuru-screentime.git --enable
```

Update later with `omarchy plugin update`. To remove: `omarchy plugin remove rimuru.screentime`.

Needs Omarchy with Hyprland, a Nerd Font (for the icon) and `python3` (already on Omarchy). Without `python3` it still tracks, but terminals show under the terminal's own name instead of the command running in it.

## Use

**In the bar:** left click opens the popup, right click switches between icon + time and icon only.

**In the popup:**

- **Donut and list:** the biggest six apps plus "Other" (apps under 3% are folded into it). Hover a slice or a row to spotlight it. *Show more* lists every app that's in "Other".
- **Week trend:** one Monday-to-Sunday page at a time, with the date range and ISO week number (`Aug 31 – Sep 6, 2026 · W36`). The arrows or the mouse wheel page back through up to 52 weeks, as far as your history goes. Click a day to inspect it (the donut, total and insights follow), then click it again, or *Back to today*, to return. Click the week's total to flip between time and its share of the week's 168 hours.
- **Insights:** the day's top app, how it compares with the day before, and the busiest day of the week on screen.
- **Yearly overview:** click *Year ›* (or the hourglass) for a bar per month and a set of highlights for that year, with arrows to go back through every recorded year:
  - *Days tracked* out of the days measured. A year is measured from Jan 1, or from your first recorded day if you started mid-year, up to today (or Dec 31).
  - *Average day*, on days you used the computer.
  - *Longest streak* of consecutive days in use, and *longest break* of consecutive days off, each with its dates.
  - *Peak day* and *busiest week* (Monday to Sunday; needs two weeks of data).
  - *Top months*, and a *weekday rhythm* chart of your average time on each weekday.

| Key | Action |
|---|---|
| `←` `→` (or `h` `l`) | Previous / next day, following it across weeks |
| `[` `]` | Older / newer week |
| `t` | Back to today |
| `y` | Open / close the yearly overview (there, `←` `→` or `[` `]` change the year) |
| `m` | Show more / less apps |
| `s` | Week total: time / share of the week |
| `↑` `↓` (or `k` `j`) | Scroll, if the popup is taller than the screen |
| `Esc` | Leave the yearly overview, or close the popup |

## What is tracked

- Time is counted per app once per second while its window has focus.
- **Terminals** are filed under the command running in them (`nvim`, `btop`, `claude`), not the terminal's name, and follow along as you start and stop commands. A bare shell prompt counts as "Terminal". If a terminal has several tabs, the window title is used to pick the right one.
- **Steam games** show their title instead of `steam_app_730`. Non-Steam shortcuts such as Battle.net use the window title.
- **Browsers** are folded to one name (`brave-browser` and `brave` are both "Brave"), and **Chromium web apps** ("install as app") are filed under their site, the same across profiles.
- Nothing is counted while the session is locked, while the screensaver or a desktop portal dialog has focus, when no window has focus, for apps you ignore, or while the machine is asleep. Time that crosses midnight is split between the two days.

History is stored at `~/.local/share/omarchy-screentime/history.json`. The last 365 days are kept in full (time per app). Older days are rolled into an archive that keeps just each day's total, forever, so the yearly overview can always go back to your first day. Only the per-app breakdown of old days is forgotten. Ignoring an app hides its time on recent days but can't be applied to archived days, which are totals only. Delete the file to reset. If the file ever becomes unreadable, a copy is kept next to it as `history.json.corrupt-<timestamp>` and tracking starts fresh.

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

Other commands: `open`, `close`, `toggle` and `year` (open straight on the yearly overview), all bindable to a key, and `status`.

## Security

Omarchy plugins run inside the shell with your user's permissions and are not sandboxed, so read the code before you install any of them. This one is small: `js/Model.js` (pure logic), `qml/Service.qml` (tracking and saving), `qml/BarWidget.qml`, `qml/Panel.qml`, `qml/Dashboard.qml`, `qml/YearView.qml` and `qml/components/` (UI) and `python/resolve_app.py` (looks up the terminal command or Steam title; it only reads `/proc`, `hyprctl activewindow` and Steam's `appmanifest` files, and writes nothing). The other commands it runs are `mkdir -p` and `cp` on its own data folder, and `omarchy-shell lock isLocked` to see whether the screen is locked.

## Development

```bash
node --test tests/                    # unit tests for js/Model.js
python3 -m unittest discover -s tests # unit tests for python/resolve_app.py
omarchy plugin validate .             # check the manifest
ln -s "$PWD" ~/.config/omarchy/plugins/rimuru.screentime
omarchy-shell shell rescanPlugins && omarchy plugin enable rimuru.screentime
```

Omarchy reloads plugin code when files change inside `~/.config/omarchy/plugins/`, but a symlinked checkout isn't watched, and `qml/Service.qml` stays loaded across reloads. So after editing any QML, run `omarchy restart shell` (it briefly blinks the bar).
