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

var REVERSE_DNS = /^(org|com|io|net|dev|app|me|de|fr)\./i

// Window class -> something readable. "org.gnome.Nautilus" -> "Nautilus",
// "brave-browser" -> "Brave Browser". Only the first letter of each word is
// touched, so names like "VLC" or "GitHub" survive.
function displayName(appId) {
  var id = String(appId || "").trim()
  if (id === "") return "Unknown"
  if (REVERSE_DNS.test(id)) id = id.slice(id.lastIndexOf(".") + 1)
  var words = id.split(/[-_\s]+/).filter(function (w) { return w !== "" })
  if (words.length === 0) return "Unknown"
  return words.map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
}

// Rows for the per-app list, largest first. `share` is the fraction of the
// day's total, `rel` the fraction of the biggest row (for bar lengths). When
// there are more than `limit` apps the tail is folded into one "Other" row so
// the list stays a fixed height.
function topApps(day, limit) {
  if (!day || !day.apps) return []
  var rows = []
  for (var app in day.apps)
    rows.push({ app: app, ms: day.apps[app] })
  rows.sort(function (a, b) { return b.ms - a.ms || (a.app < b.app ? -1 : 1) })

  if (rows.length > limit) {
    var rest = rows.slice(limit - 1)
    var other = 0
    for (var i = 0; i < rest.length; i++) other += rest[i].ms
    rows = rows.slice(0, limit - 1)
    rows.push({ app: "", ms: other, other: true })
  }

  // "Other" can outgrow the apps ranked above it, so scale bars to the true max.
  var total = day.total || 0
  var max = 0
  for (var j = 0; j < rows.length; j++) max = Math.max(max, rows[j].ms)
  return rows.map(function (r) {
    return {
      app: r.app,
      name: r.other ? "Other" : displayName(r.app),
      ms: r.ms,
      other: r.other === true,
      share: total > 0 ? r.ms / total : 0,
      rel: max > 0 ? r.ms / max : 0
    }
  })
}

var WEEKDAY_LETTERS = ["S", "M", "T", "W", "T", "F", "S"]

// The last `n` days ending today, oldest first, for the trend strip.
function recentDays(days, now, n) {
  var out = []
  var max = 0
  for (var i = n - 1; i >= 0; i--) {
    var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
    var key = dayKey(d)
    var ms = days[key] ? days[key].total : 0
    max = Math.max(max, ms)
    out.push({ key: key, ms: ms, label: WEEKDAY_LETTERS[d.getDay()], today: i === 0 })
  }
  return out.map(function (e) {
    return { key: e.key, ms: e.ms, label: e.label, today: e.today, rel: max > 0 ? e.ms / max : 0 }
  })
}
