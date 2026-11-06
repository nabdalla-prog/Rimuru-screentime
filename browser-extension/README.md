# Chromium site companion

This companion groups focused Chromium time by site hostname, such as `youtube.com` or `github.com`. It sends only the hostname and a temporary hash used to match the focused window to a local native host. Page titles, URL paths and page contents are not saved.

1. Install or update the Screen Time plugin and restart the Omarchy shell.
2. In Brave, Chromium, Chrome, Vivaldi or Edge, open the browser's extensions page, enable Developer mode, choose **Load unpacked**, and select this `browser-extension` directory.
3. Copy the 32-letter extension ID shown on that page.
4. From the repository root, run `python3 python/browser_tab_host.py --install brave EXTENSION_ID` (replace `brave` with `brave-nightly`, `brave-beta`, `chromium`, `chrome`, `vivaldi` or `edge` as appropriate). This installs a user-level native messaging manifest for that browser.
5. Run `chmod +x python/browser_tab_host.py`, then reload the extension. Its badge should no longer show `!`. Restart the Omarchy shell if it was running before the plugin update.

The extension directory and host script must remain at their installed paths. The host writes only `~/.local/share/omarchy-screentime/browser-tab.json`; the plugin stores site durations in its normal history file. Each Chromium profile needs the extension loaded. If the host is unavailable, time remains under the browser total without a site breakdown.

In Screen Time settings, pick a site chip or enter `tab:youtube.com` to set a daily limit for that domain. Limits work like app limits: a notification and urgent bar colour when reached, with no browser blocking.
