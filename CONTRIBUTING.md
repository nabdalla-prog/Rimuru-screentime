# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a problem

Run `omarchy-shell rimuru.screentime status` and paste its one line into the issue, along with your Omarchy version (`cat /usr/share/omarchy/version`), what you did and what you expected. The [issue forms](https://github.com/nabdalla-prog/Rimuru-screentime/issues/new/choose) ask for these. For a security problem see [SECURITY.md](SECURITY.md) instead of opening a public issue.

## The ground rules

- **Local only.** The plugin makes no network requests, has no telemetry and never will.
- **Its own files only.** It writes to `~/.local/share/omarchy-screentime/` and to its own entry in `shell.json`, and only when the user changes something.
- **No third-party artwork.** Don't add images from an anime, game or other property. The built-in slime is an original drawing. Pictures a user chooses stay on their machine.
- **Keep it small and readable.** Match the surrounding code's style and comment density.

## Layout

| Path | What it is |
|---|---|
| `js/Model.js` | All the logic that doesn't touch the shell: time math, formatting, week and year statistics, settings parsing. Unit tested. |
| `qml/Service.qml` | The tracker: watches the focused window, saves history, pauses while locked. |
| `qml/BarWidget.qml`, `qml/Panel.qml` | The bar button and the popup shell. |
| `qml/Dashboard.qml`, `YearView.qml`, `SettingsView.qml`, `components/` | The popup's content. They don't depend on the shell, so they can be previewed on their own. |
| `python/resolve_app.py` | Finds the command running in a terminal, and Steam titles. |
| `tools/` | `preview.sh` renders the popup with made-up data. |

## Setting up

```bash
git clone https://github.com/nabdalla-prog/Rimuru-screentime.git
cd Rimuru-screentime
ln -s "$PWD" ~/.config/omarchy/plugins/rimuru.screentime
omarchy-shell shell rescanPlugins && omarchy plugin enable rimuru.screentime
```

The shell keeps a plugin's code running until it restarts, so after editing any file run `omarchy restart shell`.

## Testing

```bash
node --test tests/                     # logic, versions, changelog
python3 -m unittest discover -s tests  # the terminal resolver
omarchy plugin validate .              # the manifest
tools/preview.sh today out.png         # see the popup with made-up data
```

Add a test with any change to `js/Model.js` or `python/resolve_app.py`. Things worth knowing when writing QML here:

- An inline `component X: Item {}` can't see ids from the file it's in. Put reusable pieces in their own file under `qml/components/`.
- A `Shape`'s stroke colour may not repaint when it changes after the first draw (themes load asynchronously), so the donut carries each slice's colour inside the slice data.
- Read anything from the service with a fallback: an older service may lack newer properties.

## Branches and releases

`main` is what every user installs and updates to, so it only ever holds tagged releases. Work on the `dev` branch (or a feature branch) and open pull requests against `dev`.

To release, on `dev`:

1. Bump the version in `manifest.json` **and** `js/Model.js` (a test checks they match).
2. Add a `## [x.y.z]` entry to `CHANGELOG.md` (a test checks it exists).
3. Run all the tests, then merge `dev` into `main`, tag it `vx.y.z`, and create a GitHub release with the changelog entry as its notes.

If what the popup or bar reads from or calls on the service changes, also bump `apiLevel` in `qml/Service.qml` and `requiredApiLevel` in `qml/BarWidget.qml` (a test checks they match).
