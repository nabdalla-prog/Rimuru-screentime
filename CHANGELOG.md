# Changelog

All notable changes to this plugin. Versions follow `manifest.json`; each is a tagged release on GitHub.

## [0.6.1] - 2026-09-20

### Added
- The plugin now notices when a newer version has been installed while the old one is still running (Omarchy keeps a plugin loaded until the shell restarts) and shows a notice in the bar tooltip and at the top of the popup asking for `omarchy restart shell`.
- Screenshots, a Requirements section with tested versions, update and remove instructions, a Troubleshooting table and a Known limitations section in the README.
- `tools/preview.sh`, which renders the popup on its own with made-up data.
- Community files (`CONTRIBUTING`, `SECURITY`, `CODE_OF_CONDUCT`, issue and pull request templates) and a GitHub Actions workflow that runs the tests.

### Changed
- Every read of the tracking service falls back to a default and calls to newer service functions are guarded, so the popup and bar can't be broken by an older service running beside newer files. The widget and service also agree on a contract level (`apiLevel`) and the popup says so when they don't.
- The README no longer claims plugin code hot-reloads: it doesn't, a restart is needed.

## [0.6.0] - 2026-09-20

### Added
- An optional faint background picture behind the popup: off, a built-in original slime drawing (the default, at the faintest strength), or a picture you choose by path. Strength (three levels, always a watermark), fill or fit, and a status message if a file can't be loaded.
- A Background card in the settings, and `omarchy-shell rimuru.screentime background off|slime|/path`.

### Fixed
- A path starting with `~/` was read as `/…` when the home folder was unknown.

## [0.5.0] - 2026-09-20

### Added
- A settings menu (gear, the `c` key, or `omarchy-shell rimuru.screentime settings`): icon-only mode, insights and yearly-overview toggles, playful extras, weekly graph reach (12, 24, 36 or 52 weeks), storage readout, daily goal, ignored apps with tap-to-ignore suggestions, custom app names, and *Reset today* / *Wipe all history* behind repeated confirmation.
- Key hints (`f`), day keys `1`–`7`, a ★ on the busiest week, a *recharge month* card in the yearly view, a first-run hint, and an hourglass that turns over on the hour.

## [0.4.0] - 2026-09-20

### Added
- A yearly overview: a bar per month and highlights (days tracked, average day, longest streak and break, peak day, busiest week, top months, weekday rhythm), with paging through every recorded year. Open it with *Year ›*, the hourglass, `y`, or `omarchy-shell rimuru.screentime year`.
- A permanent per-day archive: days older than 365 are no longer dropped, their totals are kept forever. `history.json` is now version 2; older files load unchanged.

## [0.3.0] - 2026-09-20

### Added
- A donut chart of the day's apps with a legend that highlights in step with it, a *Show more* list, a week-by-week trend that pages back through up to 52 weeks with day inspection, and insights (top app, comparison with the day before, busiest day).
- Keyboard control of the popup.

## [0.2.0] - 2026-09-20

### Added
- Terminals are filed under the command running in them, Steam games show their title, browsers and Chromium web apps are folded to one name, ignored apps and custom names, and a daily goal with a ✓ in the bar.
- Time that crosses midnight is split between the two days; the screensaver and desktop portals are never counted.

## [0.1.0] - 2026-09-20

### Added
- First release: today's total per app in the bar, with a popup breakdown and a 7-day strip. Local-only history, paused while locked. Plugin id `rimuru.screentime`.
