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

// ---- Calendar helpers ---------------------------------------------------------

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
// Weeks run Monday to Sunday.
var WEEK_LETTERS = ["M", "T", "W", "T", "F", "S", "S"]
var DAY_MS = 86400000
var WEEK_HOURS_MS = 168 * 3600000

// "YYYY-MM-DD" -> local midnight, or null.
function parseKey(key) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key))
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function addDays(d, n) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
}

function mondayOf(d) {
  return addDays(d, -((d.getDay() + 6) % 7))
}

// ISO 8601 week number (the week containing the year's first Thursday is 1).
function isoWeek(date) {
  var d = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7))
  var week1 = new Date(d.getFullYear(), 0, 4)
  return 1 + Math.round(((d - week1) / DAY_MS - 3 + ((week1.getDay() + 6) % 7)) / 7)
}

// Whole weeks from the week containing `date` to the current week (>= 0).
function weeksBack(now, date) {
  var diff = mondayOf(startOfDay(now)) - mondayOf(startOfDay(date))
  return Math.max(0, Math.round(diff / (7 * DAY_MS)))
}

// How many weeks the trend can page back: as far as recorded history goes,
// at most `cap` weeks in total (so cap - 1 pages back from this week).
function maxBack(days, now, cap) {
  var first = null
  for (var key in days) if (first === null || key < first) first = key
  var d = first === null ? null : parseKey(first)
  if (!d) return 0
  return Math.min(Math.max(0, cap - 1), weeksBack(now, d))
}

// The day `delta` days from `key`, kept between the oldest day the trend can
// show and today.
function shiftDay(key, delta, todayKey, oldestKey) {
  var d = parseKey(key)
  var today = parseKey(todayKey)
  if (!d || !today) return key
  var next = dayKey(addDays(d, delta))
  if (next > todayKey) return todayKey
  if (oldestKey && next < oldestKey) return oldestKey
  return next
}

// "Today", "Yesterday" or "Sat, Sep 19".
function dayTitle(key, todayKey) {
  if (key === todayKey) return "Today"
  var d = parseKey(key)
  var today = parseKey(todayKey)
  if (!d || !today) return String(key)
  if (dayKey(addDays(today, -1)) === key) return "Yesterday"
  return WEEKDAYS[d.getDay()] + ", " + MONTHS[d.getMonth()] + " " + d.getDate()
}

// "Aug 31 \u2013 Sep 6, 2026 \u00b7 W36". A week that straddles New Year names
// both years.
function weekLabel(monday) {
  var sunday = addDays(monday, 6)
  var from = MONTHS[monday.getMonth()] + " " + monday.getDate()
  var to = MONTHS[sunday.getMonth()] + " " + sunday.getDate()
  var range = monday.getFullYear() === sunday.getFullYear()
    ? from + " \u2013 " + to + ", " + sunday.getFullYear()
    : from + ", " + monday.getFullYear() + " \u2013 " + to + ", " + sunday.getFullYear()
  return range + " \u00b7 W" + isoWeek(monday)
}

// One Monday-to-Sunday page of the trend, `back` weeks before this one. Days
// after today are marked `future` and count as zero. Ignored apps are left
// out. `rel` scales each bar against the busiest day on the page; `share` is
// the week's total as a fraction of its 168 hours.
function weekPage(days, now, back, ignored, names) {
  var today = startOfDay(now)
  var monday = mondayOf(addDays(today, -7 * back))
  var out = []
  var total = 0
  var max = 0
  for (var i = 0; i < 7; i++) {
    var d = addDays(monday, i)
    var key = dayKey(d)
    var future = d > today
    var day = !future && days[key] ? visibleDay(days[key], ignored, names) : null
    var ms = day ? day.total : 0
    total += ms
    max = Math.max(max, ms)
    out.push({ key: key, weekday: WEEKDAYS[d.getDay()], letter: WEEK_LETTERS[i], ms: ms, today: d.getTime() === today.getTime(), future: future })
  }
  return {
    back: back,
    label: weekLabel(monday),
    total: total,
    share: total / WEEK_HOURS_MS,
    days: out.map(function (e) {
      return { key: e.key, weekday: e.weekday, letter: e.letter, ms: e.ms, today: e.today, future: e.future, rel: max > 0 ? e.ms / max : 0 }
    })
  }
}

// ---- Insights and chart slices ---------------------------------------------------

var DASH = "\u2014"

// Three rows for the selected day: its top app, how it compares with the day
// before, and the busiest day of the week on screen. Missing data shows a dash.
function dayInsights(days, key, todayKey, page, ignored, names) {
  var day = days[key] ? visibleDay(days[key], ignored, names) : null
  var rows = day ? topApps(day, 100000, names) : []
  var top = rows.length > 0 ? rows[0].name + " \u00b7 " + fmt(rows[0].ms) : DASH

  var d = parseKey(key)
  var prevDate = d ? addDays(d, -1) : null
  var prev = prevDate && days[dayKey(prevDate)] ? visibleDay(days[dayKey(prevDate)], ignored, names) : null
  var versus = DASH
  if (prev) {
    var diff = (day ? day.total : 0) - prev.total
    versus = diff === 0 ? "same" : (diff > 0 ? "+" : "\u2212") + fmt(Math.abs(diff))
  }

  var busiest = DASH
  var best = null
  for (var i = 0; i < page.days.length; i++)
    if (page.days[i].ms > 0 && (best === null || page.days[i].ms > best.ms)) best = page.days[i]
  if (best) busiest = best.weekday + " \u00b7 " + fmt(best.ms)

  return [
    { label: "Top app", value: top },
    { label: key === todayKey || !prevDate ? "vs yesterday" : "vs " + WEEKDAYS[prevDate.getDay()], value: versus },
    { label: "Busiest day", value: busiest }
  ]
}

// Slices for the donut: the biggest `maxApps` apps that hold at least
// `minShare` of the day, with everything else folded into one "Other". Each
// slice carries where it starts and how far it sweeps, as fractions of a turn.
function donutSlices(day, names, maxApps, minShare) {
  var rows = topApps(day, 100000, names)
  var head = []
  var rest = 0
  var total = 0
  for (var i = 0; i < rows.length; i++) {
    total += rows[i].ms
    if (head.length < maxApps && rows[i].share >= minShare) head.push(rows[i])
    else rest += rows[i].ms
  }
  var slices = head.map(function (r) {
    return { name: r.name, ms: r.ms, share: r.share, other: false }
  })
  if (rest > 0) slices.push({ name: "Other", ms: rest, share: total > 0 ? rest / total : 0, other: true })
  var start = 0
  for (var j = 0; j < slices.length; j++) {
    slices[j].index = j
    slices[j].startFrac = start
    slices[j].sweepFrac = slices[j].share
    start += slices[j].share
  }
  return slices
}
