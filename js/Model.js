.pragma library

// Pure logic for the screen-time plugin: no QML, no I/O, so it can be unit
// tested with plain Node (see tests/model.test.js).
//
// History shape: { "<YYYY-MM-DD>": { total: <ms>, apps: { "<appId>": <ms> } } }
// All durations are integer milliseconds. Day keys use the local timezone.

var KEEP_DAYS = 365

function pad(n) {
  return n < 10 ? "0" + n : "" + n
}

function dayKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function newDay() {
  return { total: 0, apps: {} }
}

function validMs(v) {
  return typeof v === "number" && isFinite(v) && v >= 0
}

// Parse the history file. Returns { ok: true, days } or { ok: false } when the
// file is unreadable, so the caller can set it aside instead of overwriting it.
// Blank text is a valid, empty history. Entries that don't look right are
// dropped rather than trusted, and each day's total is recomputed from its apps
// so a hand-edited or half-written file can never show inconsistent numbers.
function parseHistory(text) {
  if (text === undefined || text === null || String(text).trim() === "")
    return { ok: true, days: {} }

  var raw
  try {
    raw = JSON.parse(text)
  } catch (e) {
    return { ok: false }
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw))
    return { ok: false }

  var source = raw.days
  if (source === undefined) return { ok: true, days: {} }
  if (!source || typeof source !== "object" || Array.isArray(source))
    return { ok: false }

  var days = {}
  for (var key in source) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) continue
    var entry = source[key]
    if (!entry || typeof entry !== "object" || !entry.apps || typeof entry.apps !== "object")
      continue
    var day = newDay()
    for (var app in entry.apps) {
      var ms = entry.apps[app]
      if (!validMs(ms) || ms === 0) continue
      day.apps[app] = Math.round(ms)
      day.total += Math.round(ms)
    }
    days[key] = day
  }
  return { ok: true, days: days }
}

function serialize(days) {
  return JSON.stringify({ version: 1, days: days }, null, 2) + "\n"
}

// Returns a new history with `ms` added to `app` on day `key`. The input is
// never mutated: QML bindings only re-evaluate when the property is replaced.
function addTime(days, key, app, ms) {
  if (!app || !validMs(ms) || ms === 0) return days
  var next = Object.assign({}, days)
  var prev = days[key] || newDay()
  var apps = Object.assign({}, prev.apps)
  apps[app] = (apps[app] || 0) + ms
  next[key] = { total: prev.total + ms, apps: apps }
  return next
}

// Drops days older than `keepDays` before `now`.
function pruneDays(days, keepDays, now) {
  var cutoff = dayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - keepDays))
  var next = {}
  for (var key in days)
    if (key >= cutoff) next[key] = days[key]
  return next
}

// "<1m", "42m", "2h", "2h 5m". Whole minutes, rounded down.
function fmt(ms) {
  if (!validMs(ms) || ms === 0) return "0m"
  var minutes = Math.floor(ms / 60000)
  if (minutes < 1) return "<1m"
  var h = Math.floor(minutes / 60)
  var m = minutes % 60
  if (h === 0) return m + "m"
  return m === 0 ? h + "h" : h + "h " + m + "m"
}

var WEB_PREFIX = "web:"
var REVERSE_DNS = /^(org|com|io|net|dev|app|me|de|fr)\./i

// Window class -> something readable. "org.gnome.Nautilus" -> "Nautilus",
// "brave-browser" -> "Brave Browser". Names that already look deliberate are
// left alone: anything with a capital letter or a space ("Half-Life 2",
// "GitHub", "VLC") and hostnames ("web.whatsapp.com"). Only plain lowercase
// ids get prettified, one word at a time.
function displayName(appId) {
  var id = String(appId || "").trim()
  if (id === "") return "Unknown"
  if (id.indexOf(WEB_PREFIX) === 0) return id.slice(WEB_PREFIX.length) || "Unknown"
  if (REVERSE_DNS.test(id)) id = id.slice(id.lastIndexOf(".") + 1)
  if (/[A-Z\s]/.test(id) || id.indexOf(".") !== -1) return id
  var words = id.split(/[-_]+/).filter(function (w) { return w !== "" })
  if (words.length === 0) return "Unknown"
  return words.map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
}

// ---- App identity ---------------------------------------------------------

var TERMINAL_CLASSES = [
  "foot", "footclient", "alacritty", "kitty", "ghostty", "wezterm", "konsole",
  "gnome-terminal", "tilix", "xfce4-terminal", "termite", "st", "xterm", "urxvt",
  "org.omarchy.terminal", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
  "org.wezfurlong.wezterm", "org.gnome.terminal", "org.gnome.console",
  "org.kde.konsole", "com.raggesilver.blackbox", "dev.warp.warp",
  "io.elementary.terminal"
]

// Terminals report their own class, which says nothing about what you are
// doing in them, so those windows get resolved to the foreground command.
function isTerminalClass(cls) {
  return TERMINAL_CLASSES.indexOf(String(cls || "").toLowerCase()) !== -1
}

// Steam games report "steam_app_<appid>" (or a slug for non-Steam shortcuts).
function isSteamClass(cls) {
  return /^steam_app_/i.test(String(cls || ""))
}

// Windows that are the system rather than something the user is using.
function isSystemWindow(cls) {
  var c = String(cls || "").toLowerCase()
  return c === "org.omarchy.screensaver"
    || c.indexOf("xdg-desktop-portal") === 0
    || c.indexOf("org.freedesktop.impl.portal") === 0
}

var SHELLS = { bash: 1, sh: 1, zsh: 1, fish: 1, dash: 1, nu: 1, ksh: 1, tcsh: 1, csh: 1, xonsh: 1 }

// Browsers report a binary or class that varies by package; fold to one name.
var BROWSER_ALIASES = {
  "zen-bin": "zen", "zen_browser": "zen", "zen": "zen", "app.zen_browser.zen": "zen",
  "firefox": "firefox", "librewolf": "librewolf", "waterfox": "waterfox",
  "tor-browser": "tor-browser", "mullvad-browser": "mullvad-browser",
  "google-chrome": "google-chrome", "chrome": "google-chrome",
  "chromium": "chromium", "brave": "brave", "brave-browser": "brave",
  "vivaldi": "vivaldi", "vivaldi-stable": "vivaldi",
  "microsoft-edge": "microsoft-edge", "edge": "microsoft-edge"
}

// Chromium "install as app" windows: chrome-<host>__<path>-<Profile>. The
// profile suffix makes the same site look different per profile, so fold to
// the host. Without the suffix a dot is required, which keeps plain browser
// classes like "brave-browser" out.
var WEBAPP_WITH_PROFILE = /^(?:chrome|chromium|brave|msedge|vivaldi)-([a-z0-9](?:[a-z0-9.-]*[a-z0-9])?)__.*-(?:Default|Profile_\d+)$/i
var WEBAPP_DOTTED = /^(?:chrome|chromium|brave|msedge|vivaldi)-([a-z0-9-]+(?:\.[a-z0-9-]+)+)$/i

function webAppHost(cls) {
  var m = WEBAPP_WITH_PROFILE.exec(cls) || WEBAPP_DOTTED.exec(cls)
  return m ? m[1].toLowerCase() : null
}

// The key a window's time is filed under. `resolved` is what the resolver
// found (the command running in a terminal, or a Steam game's title); without
// it the window class is used. A bare shell prompt files under "terminal".
function canonicalApp(cls, resolved) {
  var name = String(resolved || "").trim()
  if (name !== "") {
    if (SHELLS[name.toLowerCase()]) return "terminal"
    return BROWSER_ALIASES[name.toLowerCase()] || name
  }
  name = String(cls || "").trim()
  if (name === "") return ""
  var host = webAppHost(name)
  if (host) return WEB_PREFIX + host
  return BROWSER_ALIASES[name.toLowerCase()] || name
}

// Re-files stored time under today's naming rules, so history recorded before
// a rule existed (say "brave-browser" before browsers were folded) merges with
// new time instead of showing as a second row.
function normalizeKeys(days) {
  var out = {}
  for (var key in days) {
    var day = newDay()
    for (var app in days[key].apps) {
      var name = canonicalApp(app, "") || app
      day.apps[name] = (day.apps[name] || 0) + days[key].apps[app]
      day.total += days[key].apps[app]
    }
    out[key] = day
  }
  return out
}

// ---- Settings -------------------------------------------------------------

function splitEntries(v) {
  if (Array.isArray(v)) return v.map(String)
  if (typeof v === "string") return v.split(/[,\n]/)
  return []
}

// Ignored apps: an array or a comma/newline separated string. Lowercased and
// de-duplicated, since matching is case-insensitive.
function parseList(v) {
  var seen = {}
  var out = []
  splitEntries(v).forEach(function (raw) {
    var item = raw.trim().toLowerCase()
    if (item !== "" && !seen[item]) { seen[item] = true; out.push(item) }
  })
  return out
}

// Custom names: an object, or "app=Name, other=Name" (also as an array of
// those). Keys are lowercased; empty names and keys are dropped.
function parseNames(v) {
  var out = {}
  function put(k, name) {
    k = String(k).trim().toLowerCase()
    name = String(name).trim().slice(0, 40)
    if (k !== "" && name !== "") out[k] = name
  }
  if (v && typeof v === "object" && !Array.isArray(v)) {
    for (var k in v) put(k, v[k])
  } else {
    splitEntries(v).forEach(function (pair) {
      var i = pair.indexOf("=")
      if (i > 0) put(pair.slice(0, i), pair.slice(i + 1))
    })
  }
  return out
}

// Daily goal in whole hours, 0 = off.
function parseGoal(v) {
  var n = Math.floor(Number(v))
  if (!isFinite(n) || n < 0) return 0
  return Math.min(n, 24)
}

// What the user sees for a key: their custom name, else a readable default.
function displayLabel(key, names) {
  var fallback = displayName(key)
  if (!names) return fallback
  return names[String(key).toLowerCase()] || names[fallback.toLowerCase()] || fallback
}

// True when an app is on the ignore list. The user may have typed the stored
// key, the class, the readable name or their own custom name for it.
function isIgnored(list, names, key, cls) {
  if (!list || list.length === 0) return false
  var candidates = [key, cls, displayName(key), displayLabel(key, names)]
  for (var i = 0; i < candidates.length; i++) {
    var c = String(candidates[i] || "").toLowerCase()
    if (c !== "" && list.indexOf(c) !== -1) return true
  }
  return false
}

// A day without its ignored apps, with the total recomputed. Ignoring an app
// hides its past time as well as stopping new time.
function visibleDay(day, list, names) {
  if (!day || !list || list.length === 0) return day
  var out = newDay()
  for (var app in day.apps) {
    if (isIgnored(list, names, app, app)) continue
    out.apps[app] = day.apps[app]
    out.total += day.apps[app]
  }
  return out
}

function goalProgress(totalMs, hours) {
  var goalMs = parseGoal(hours) * 3600000
  if (goalMs <= 0) return { enabled: false, goalMs: 0, ratio: 0, reached: false, remainingMs: 0 }
  return {
    enabled: true,
    goalMs: goalMs,
    ratio: Math.min(1, totalMs / goalMs),
    reached: totalMs >= goalMs,
    remainingMs: Math.max(0, goalMs - totalMs)
  }
}

// ---- Time ------------------------------------------------------------------

// Splits [fromMs, toMs) at local midnights so a stretch that crosses one is
// credited to both days. Capped so a bad clock jump can't loop for long.
function splitByDay(fromMs, toMs) {
  var out = []
  var cursor = fromMs
  for (var guard = 0; cursor < toMs && guard < 400; guard++) {
    var d = new Date(cursor)
    var next = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime()
    var end = Math.min(next, toMs)
    if (end <= cursor) break
    out.push({ key: dayKey(d), ms: end - cursor })
    cursor = end
  }
  return out
}

// ---- Views for the panel -----------------------------------------------------

// Rows for the per-app list, largest first. Apps that end up with the same
// readable name (say two browsers both renamed "Browser") are merged. `share`
// is the fraction of the day's total, `rel` the fraction of the biggest row
// (for bar lengths). When there are more than `limit` rows the tail is folded
// into one "Other" row so the list stays a fixed height.
function topApps(day, limit, names) {
  if (!day || !day.apps) return []
  var merged = {}
  var rows = []
  for (var app in day.apps) {
    var name = displayLabel(app, names)
    if (!merged[name]) {
      merged[name] = { app: app, name: name, ms: 0 }
      rows.push(merged[name])
    }
    merged[name].ms += day.apps[app]
  }
  rows.sort(function (a, b) { return b.ms - a.ms || (a.name < b.name ? -1 : 1) })

  if (rows.length > limit) {
    var rest = rows.slice(limit - 1)
    var other = 0
    for (var i = 0; i < rest.length; i++) other += rest[i].ms
    rows = rows.slice(0, limit - 1)
    rows.push({ app: "", name: "Other", ms: other, other: true })
  }

  // "Other" can outgrow the apps ranked above it, so scale bars to the true max.
  var total = 0
  var max = 0
  for (var t = 0; t < rows.length; t++) {
    total += rows[t].ms
    max = Math.max(max, rows[t].ms)
  }
  return rows.map(function (r) {
    return {
      app: r.app,
      name: r.name,
      ms: r.ms,
      other: r.other === true,
      share: total > 0 ? r.ms / total : 0,
      rel: max > 0 ? r.ms / max : 0
    }
  })
}

var WEEKDAY_LETTERS = ["S", "M", "T", "W", "T", "F", "S"]

// The last `n` days ending today, oldest first, for the trend strip. Ignored
// apps are left out of each day's total.
function recentDays(days, now, n, ignored, names) {
  var out = []
  var max = 0
  for (var i = n - 1; i >= 0; i--) {
    var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
    var key = dayKey(d)
    var day = days[key] ? visibleDay(days[key], ignored, names) : null
    var ms = day ? day.total : 0
    max = Math.max(max, ms)
    out.push({ key: key, ms: ms, label: WEEKDAY_LETTERS[d.getDay()], today: i === 0 })
  }
  return out.map(function (e) {
    return { key: e.key, ms: e.ms, label: e.label, today: e.today, rel: max > 0 ? e.ms / max : 0 }
  })
}
