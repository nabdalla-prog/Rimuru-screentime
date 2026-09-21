// Run with: node --test tests/
// Model.js is a QML `.pragma library` file, so it is evaluated in a sandbox
// (its top-level functions become properties of the context) instead of being
// require()d.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs
  .readFileSync(path.join(__dirname, "..", "js", "Model.js"), "utf8")
  .replace(/^\.pragma library$/m, "")
const M = vm.createContext({})
vm.runInContext(source, M)

// Values built inside the vm sandbox have that context's Object/Array
// prototypes, which strict deep-equal rejects; compare plain JSON copies.
const plain = (x) => JSON.parse(JSON.stringify(x))
const deepEqual = (a, b) => assert.deepEqual(plain(a), plain(b))

const D = (y, m, d) => new Date(y, m - 1, d, 12, 0, 0)

test("dayKey pads month and day, uses local date", () => {
  assert.equal(M.dayKey(D(2026, 1, 5)), "2026-01-05")
  assert.equal(M.dayKey(new Date(2026, 11, 31, 23, 59, 59)), "2026-12-31")
})

test("fmt", () => {
  assert.equal(M.fmt(0), "0m")
  assert.equal(M.fmt(-5), "0m")
  assert.equal(M.fmt(NaN), "0m")
  assert.equal(M.fmt(30 * 1000), "<1m")
  assert.equal(M.fmt(60 * 1000), "1m")
  assert.equal(M.fmt(59 * 60 * 1000 + 59999), "59m")
  assert.equal(M.fmt(60 * 60 * 1000), "1h")
  assert.equal(M.fmt(125 * 60 * 1000), "2h 5m")
})

test("displayName", () => {
  assert.equal(M.displayName("org.gnome.Nautilus"), "Nautilus")
  assert.equal(M.displayName("com.mitchellh.ghostty"), "Ghostty")
  assert.equal(M.displayName("brave-browser"), "Brave Browser")
  assert.equal(M.displayName("steam_app_730"), "Steam App 730")
  assert.equal(M.displayName("VLC"), "VLC")
  assert.equal(M.displayName("GitHub"), "GitHub")
  assert.equal(M.displayName(""), "Unknown")
  assert.equal(M.displayName(null), "Unknown")
  assert.equal(M.displayName("---"), "Unknown")
})

test("addTime accumulates and never mutates its input", () => {
  const a = {}
  const b = M.addTime(a, "2026-09-20", "foot", 1000)
  const c = M.addTime(b, "2026-09-20", "foot", 500)
  const d = M.addTime(c, "2026-09-20", "brave-browser", 2000)
  deepEqual(a, {})
  assert.equal(b["2026-09-20"].total, 1000)
  assert.equal(c["2026-09-20"].apps.foot, 1500)
  assert.equal(d["2026-09-20"].total, 3500)
  assert.equal(c["2026-09-20"].apps["brave-browser"], undefined)
  assert.notEqual(c, d)
})

test("addTime ignores empty app, zero, negative and non-finite time", () => {
  const a = { x: M.newDay() }
  assert.equal(M.addTime(a, "k", "", 100), a)
  assert.equal(M.addTime(a, "k", "foot", 0), a)
  assert.equal(M.addTime(a, "k", "foot", -1), a)
  assert.equal(M.addTime(a, "k", "foot", NaN), a)
  assert.equal(M.addTime(a, "k", "foot", Infinity), a)
})

test("rollArchive moves aged-out days into the archive as totals, never drops them", () => {
  const days = {
    "2025-09-19": { total: 5000, apps: { a: 5000 } }, // one day past the window
    "2025-09-20": { total: 7000, apps: { a: 7000 } }, // last day inside it
    "2026-09-20": { total: 9000, apps: { a: 9000 } }
  }
  const r = M.rollArchive(days, {}, 365, D(2026, 9, 20))
  deepEqual(Object.keys(r.days).sort(), ["2025-09-20", "2026-09-20"])
  deepEqual(r.archive, { "2025-09-19": 5000 })
  // inputs untouched
  assert.equal(Object.keys(days).length, 3)
})

test("rollArchive keeps what the archive already holds and skips empty days", () => {
  const days = { "2024-01-01": { total: 0, apps: {} }, "2024-01-02": { total: 100, apps: { a: 100 } } }
  const r = M.rollArchive(days, { "2023-05-05": 42 }, 365, D(2026, 9, 20))
  deepEqual(r.archive, { "2023-05-05": 42, "2024-01-02": 100 })
  deepEqual(r.days, {})
  const again = M.rollArchive(r.days, r.archive, 365, D(2026, 9, 20))
  deepEqual(again.archive, r.archive) // idempotent
})

test("parseHistory: blank and missing days are empty but valid", () => {
  deepEqual(M.parseHistory(""), { ok: true, days: {}, archive: {} })
  deepEqual(M.parseHistory("  \n"), { ok: true, days: {}, archive: {} })
  deepEqual(M.parseHistory(undefined), { ok: true, days: {}, archive: {} })
  deepEqual(M.parseHistory("{}"), { ok: true, days: {}, archive: {} })
})

test("parseHistory: corrupt files are reported, not swallowed", () => {
  assert.equal(M.parseHistory("{not json").ok, false)
  assert.equal(M.parseHistory("[1,2]").ok, false)
  assert.equal(M.parseHistory("42").ok, false)
  assert.equal(M.parseHistory('{"days": []}').ok, false)
  assert.equal(M.parseHistory('{"days": "x"}').ok, false)
})

test("parseHistory recomputes totals and drops bad entries", () => {
  const text = JSON.stringify({
    version: 1,
    days: {
      "2026-09-20": { total: 999999, apps: { foot: 1000, bad: -5, nan: "x", zero: 0, ok: 2000.4 } },
      "not-a-date": { total: 1, apps: { foot: 1 } },
      "2026-09-19": { total: 5 },
      "2026-09-18": null
    }
  })
  const r = M.parseHistory(text)
  assert.equal(r.ok, true)
  deepEqual(Object.keys(r.days), ["2026-09-20"])
  deepEqual(JSON.parse(JSON.stringify(r.days["2026-09-20"])), {
    total: 3000,
    apps: { foot: 1000, ok: 2000 }
  })
})

test("serialize round-trips through parseHistory", () => {
  let days = M.addTime({}, "2026-09-20", "foot", 61000)
  days = M.addTime(days, "2026-09-20", "brave-browser", 5000)
  const back = M.parseHistory(M.serialize(days))
  assert.equal(back.ok, true)
  deepEqual(JSON.parse(JSON.stringify(back.days)), JSON.parse(JSON.stringify(days)))
})

test("topApps sorts, computes shares, and folds the tail into Other", () => {
  const day = { total: 100, apps: { a: 50, b: 25, c: 15, d: 6, e: 4 } }
  const rows = M.topApps(day, 3)
  assert.equal(rows.length, 3)
  deepEqual(rows.map((r) => r.app), ["a", "b", ""])
  assert.equal(rows[2].name, "Other")
  assert.equal(rows[2].other, true)
  assert.equal(rows[2].ms, 25) // c + d + e
  assert.equal(rows[0].share, 0.5)
  assert.equal(rows[0].rel, 1)
  assert.equal(rows[1].rel, 0.5)
})

test("topApps: no fold when the list fits, empty and null are safe", () => {
  assert.equal(M.topApps({ total: 3, apps: { a: 1, b: 2 } }, 5).length, 2)
  deepEqual(M.topApps(M.newDay(), 5), [])
  deepEqual(M.topApps(null, 5), [])
})

test("topApps: bars scale to the largest row even when Other is largest", () => {
  const day = { total: 100, apps: { a: 30, b: 20, c: 20, d: 20, e: 10 } }
  const rows = M.topApps(day, 3)
  const other = rows[rows.length - 1]
  assert.equal(other.ms, 50)
  assert.equal(other.rel, 1)
  assert.ok(rows.every((r) => r.rel <= 1))
})

// ---- Phase 1: identity, settings, goal, midnight ------------------------------

test("displayName keeps deliberate names, prettifies plain ids", () => {
  assert.equal(M.displayName("Half-Life 2"), "Half-Life 2")
  assert.equal(M.displayName("Stardew Valley"), "Stardew Valley")
  assert.equal(M.displayName("web:app.slack.com"), "app.slack.com")
  assert.equal(M.displayName("web:web.whatsapp.com"), "web.whatsapp.com")
  assert.equal(M.displayName("nvim"), "Nvim")
  assert.equal(M.displayName("web:"), "Unknown")
})

test("terminal, steam and system window classes", () => {
  assert.equal(M.isTerminalClass("com.mitchellh.ghostty"), true)
  assert.equal(M.isTerminalClass("Alacritty"), true)
  assert.equal(M.isTerminalClass("brave-browser"), false)
  assert.equal(M.isTerminalClass(""), false)
  assert.equal(M.isSteamClass("steam_app_730"), true)
  assert.equal(M.isSteamClass("steam_app_battlenet"), true)
  assert.equal(M.isSteamClass("steam"), false)
  assert.equal(M.isSystemWindow("org.omarchy.screensaver"), true)
  assert.equal(M.isSystemWindow("xdg-desktop-portal-gtk"), true)
  assert.equal(M.isSystemWindow("foot"), false)
})

test("canonicalApp: resolved command wins, shells become 'terminal'", () => {
  assert.equal(M.canonicalApp("com.mitchellh.ghostty", "nvim"), "nvim")
  assert.equal(M.canonicalApp("foot", "bash"), "terminal")
  assert.equal(M.canonicalApp("foot", "ZSH"), "terminal")
  assert.equal(M.canonicalApp("steam_app_730", "Counter-Strike 2"), "Counter-Strike 2")
  assert.equal(M.canonicalApp("foot", ""), "foot")
})

test("canonicalApp: browsers fold to one name", () => {
  assert.equal(M.canonicalApp("brave-browser"), "brave")
  assert.equal(M.canonicalApp("Brave-Browser"), "brave")
  assert.equal(M.canonicalApp("zen-bin"), "zen")
  assert.equal(M.canonicalApp("google-chrome"), "google-chrome")
  // A browser started from a terminal still folds.
  assert.equal(M.canonicalApp("foot", "brave"), "brave")
  assert.equal(M.canonicalApp("org.gnome.Nautilus"), "org.gnome.Nautilus")
  assert.equal(M.canonicalApp("", ""), "")
  assert.equal(M.canonicalApp(null, null), "")
})

test("canonicalApp: Chromium web apps fold to their host across profiles", () => {
  assert.equal(M.canonicalApp("chrome-web.whatsapp.com__-Default"), "web:web.whatsapp.com")
  assert.equal(M.canonicalApp("chrome-web.whatsapp.com__-Profile_2"), "web:web.whatsapp.com")
  assert.equal(M.canonicalApp("brave-github.com__notifications-Default"), "web:github.com")
  assert.equal(M.canonicalApp("brave-app.slack.com"), "web:app.slack.com")
  // Plain browser classes are not web apps.
  assert.equal(M.canonicalApp("brave-browser"), "brave")
  assert.equal(M.canonicalApp("chromium-browser"), "chromium-browser")
})

test("parseList accepts arrays and strings, lowercases and de-duplicates", () => {
  deepEqual(M.parseList("Steam, rofi\nWofi ,, rofi"), ["steam", "rofi", "wofi"])
  deepEqual(M.parseList(["Steam", " rofi ", "", "STEAM"]), ["steam", "rofi"])
  deepEqual(M.parseList(undefined), [])
  deepEqual(M.parseList(42), [])
})

test("parseNames accepts objects, 'a=B' strings and arrays", () => {
  deepEqual(M.parseNames("zen=Browser, foot = Terminal"), { zen: "Browser", foot: "Terminal" })
  deepEqual(M.parseNames({ Zen: "Browser", bad: "", "": "x" }), { zen: "Browser" })
  deepEqual(M.parseNames(["zen=Browser", "nonsense"]), { zen: "Browser" })
  deepEqual(M.parseNames(null), {})
  assert.equal(M.parseNames("a=" + "x".repeat(100)).a.length, 40)
})

test("parseGoal clamps to 0-24 whole hours", () => {
  assert.equal(M.parseGoal(6), 6)
  assert.equal(M.parseGoal("8"), 8)
  assert.equal(M.parseGoal(2.9), 2)
  assert.equal(M.parseGoal(-3), 0)
  assert.equal(M.parseGoal("abc"), 0)
  assert.equal(M.parseGoal(undefined), 0)
  assert.equal(M.parseGoal(99), 24)
})

test("displayLabel prefers a custom name by key or by readable name", () => {
  assert.equal(M.displayLabel("zen", { zen: "Browser" }), "Browser")
  assert.equal(M.displayLabel("brave", { "brave": "Web" }), "Web")
  assert.equal(M.displayLabel("steam_app_1", { "steam app 1": "Game" }), "Game")
  assert.equal(M.displayLabel("zen", {}), "Zen")
  assert.equal(M.displayLabel("zen"), "Zen")
})

test("isIgnored matches key, class, readable or custom name, case-insensitively", () => {
  assert.equal(M.isIgnored([], {}, "rofi", "rofi"), false)
  assert.equal(M.isIgnored(["rofi"], {}, "rofi", "rofi"), true)
  assert.equal(M.isIgnored(["brave browser"], {}, "brave-browser", "brave-browser"), true)
  assert.equal(M.isIgnored(["launcher"], { rofi: "Launcher" }, "rofi", "rofi"), true)
  assert.equal(M.isIgnored(["web.whatsapp.com"], {}, "web:web.whatsapp.com", ""), true)
  assert.equal(M.isIgnored(["rofi"], {}, "nvim", "foot"), false)
  assert.equal(M.isIgnored(["foot"], {}, "nvim", "foot"), true)
})

test("visibleDay drops ignored apps and recomputes the total", () => {
  const day = { total: 600, apps: { rofi: 100, nvim: 300, brave: 200 } }
  const v = M.visibleDay(day, ["rofi"], {})
  deepEqual(v, { total: 500, apps: { nvim: 300, brave: 200 } })
  assert.equal(M.visibleDay(day, [], {}), day)
  assert.equal(M.visibleDay(null, ["rofi"], {}), null)
  assert.equal(day.total, 600) // input untouched
})

test("goalProgress", () => {
  assert.equal(M.goalProgress(1000, 0).enabled, false)
  const half = M.goalProgress(3 * 3600000, 6)
  assert.equal(half.enabled, true)
  assert.equal(half.ratio, 0.5)
  assert.equal(half.reached, false)
  assert.equal(half.remainingMs, 3 * 3600000)
  const done = M.goalProgress(7 * 3600000, 6)
  assert.equal(done.reached, true)
  assert.equal(done.ratio, 1)
  assert.equal(done.remainingMs, 0)
  assert.equal(M.goalProgress(6 * 3600000, 6).reached, true)
})

test("splitByDay leaves a same-day stretch whole", () => {
  const from = new Date(2026, 8, 20, 10, 0, 0).getTime()
  deepEqual(M.splitByDay(from, from + 1000), [{ key: "2026-09-20", ms: 1000 }])
  deepEqual(M.splitByDay(from, from), [])
  deepEqual(M.splitByDay(from, from - 5), [])
})

test("splitByDay credits a stretch across midnight to both days", () => {
  const from = new Date(2026, 8, 20, 23, 59, 59, 400).getTime()
  const to = new Date(2026, 8, 21, 0, 0, 0, 500).getTime()
  const parts = M.splitByDay(from, to)
  deepEqual(parts, [
    { key: "2026-09-20", ms: 600 },
    { key: "2026-09-21", ms: 500 }
  ])
  assert.equal(parts[0].ms + parts[1].ms, to - from)
})

test("splitByDay across month and year ends, and a multi-day gap", () => {
  const dec31 = new Date(2026, 11, 31, 23, 59, 59, 0).getTime()
  const jan1 = new Date(2027, 0, 1, 0, 0, 1, 0).getTime()
  deepEqual(M.splitByDay(dec31, jan1).map((p) => p.key), ["2026-12-31", "2027-01-01"])
  const a = new Date(2026, 8, 20, 12, 0, 0).getTime()
  const b = new Date(2026, 8, 23, 12, 0, 0).getTime()
  const days = M.splitByDay(a, b)
  assert.equal(days.length, 4)
  assert.equal(days.reduce((n, p) => n + p.ms, 0), b - a)
})

test("topApps merges rows that share a name and applies custom names", () => {
  const day = { total: 100, apps: { zen: 40, firefox: 30, nvim: 30 } }
  const rows = M.topApps(day, 5, { zen: "Browser", firefox: "Browser" })
  assert.equal(rows.length, 2)
  assert.equal(rows[0].name, "Browser")
  assert.equal(rows[0].ms, 70)
  assert.equal(rows[0].share, 0.7)
  assert.equal(rows[1].name, "Nvim")
})

test("normalizeKeys merges history recorded under older names", () => {
  const days = {
    "2026-09-20": { total: 700, apps: { "brave-browser": 300, brave: 200, "chrome-web.whatsapp.com__-Default": 100, nvim: 100 } }
  }
  const out = M.normalizeKeys(days)
  deepEqual(out["2026-09-20"], { total: 700, apps: { brave: 500, "web:web.whatsapp.com": 100, nvim: 100 } })
  // input untouched
  assert.equal(days["2026-09-20"].apps["brave-browser"], 300)
  deepEqual(M.normalizeKeys({}), {})
  // already-normal history is unchanged
  deepEqual(M.normalizeKeys(out), out)
})

// ---- Phase 2: weeks, insights, donut --------------------------------------------

test("parseKey round-trips and rejects junk", () => {
  assert.equal(M.dayKey(M.parseKey("2026-09-20")), "2026-09-20")
  assert.equal(M.parseKey("2026-9-20"), null)
  assert.equal(M.parseKey("nope"), null)
  assert.equal(M.parseKey(null), null)
})

test("mondayOf treats Monday as the first day", () => {
  assert.equal(M.dayKey(M.mondayOf(D(2026, 9, 20))), "2026-09-14") // Sunday
  assert.equal(M.dayKey(M.mondayOf(D(2026, 9, 14))), "2026-09-14") // Monday
  assert.equal(M.dayKey(M.mondayOf(D(2026, 9, 17))), "2026-09-14")
  assert.equal(M.dayKey(M.mondayOf(D(2026, 1, 1))), "2025-12-29") // across the year
})

test("isoWeek matches the ISO 8601 calendar", () => {
  assert.equal(M.isoWeek(D(2026, 8, 31)), 36)
  assert.equal(M.isoWeek(D(2026, 9, 6)), 36)
  assert.equal(M.isoWeek(D(2026, 9, 7)), 37)
  assert.equal(M.isoWeek(D(2026, 1, 1)), 1)
  assert.equal(M.isoWeek(D(2026, 12, 31)), 53) // 2026 has 53 weeks
  assert.equal(M.isoWeek(D(2027, 1, 1)), 53) // still 2026's last week
  assert.equal(M.isoWeek(D(2027, 1, 4)), 1)
  assert.equal(M.isoWeek(D(2024, 12, 30)), 1) // belongs to 2025's week 1
  assert.equal(M.isoWeek(D(2024, 2, 29)), 9) // leap day
})

test("weekLabel", () => {
  assert.equal(M.weekLabel(D(2026, 8, 31)), "Aug 31 \u2013 Sep 6, 2026 \u00b7 W36")
  assert.equal(M.weekLabel(D(2026, 9, 14)), "Sep 14 \u2013 Sep 20, 2026 \u00b7 W38")
  assert.equal(M.weekLabel(D(2026, 12, 28)), "Dec 28, 2026 \u2013 Jan 3, 2027 \u00b7 W53")
})

test("weekPage: seven Monday-to-Sunday days with totals and shares", () => {
  const days = {
    "2026-09-14": { total: 3600000, apps: { a: 3600000 } },
    "2026-09-16": { total: 7200000, apps: { a: 7200000 } },
    "2026-09-20": { total: 1800000, apps: { a: 1800000 } }
  }
  const p = M.weekPage(days, D(2026, 9, 20), 0)
  assert.equal(p.days.length, 7)
  deepEqual(p.days.map((d) => d.key), ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20"])
  deepEqual(p.days.map((d) => d.letter), ["M", "T", "W", "T", "F", "S", "S"])
  assert.equal(p.total, 12600000)
  assert.equal(p.days[2].rel, 1)
  assert.equal(p.days[0].rel, 0.5)
  assert.equal(p.days[6].today, true)
  assert.equal(p.days.filter((d) => d.today).length, 1)
  assert.ok(Math.abs(p.share - 12600000 / (168 * 3600000)) < 1e-12)
  assert.equal(p.label, "Sep 14 \u2013 Sep 20, 2026 \u00b7 W38")
})

test("weekPage: future days count as zero and are flagged", () => {
  const days = { "2026-09-18": { total: 500, apps: { a: 500 } }, "2026-09-22": { total: 999, apps: { a: 999 } } }
  const p = M.weekPage(days, D(2026, 9, 17), 0) // Thursday
  deepEqual(p.days.map((d) => d.future), [false, false, false, false, true, true, true])
  assert.equal(p.total, 0)
})

test("weekPage: paging back and ignoring apps", () => {
  const days = {
    "2026-09-08": { total: 300, apps: { rofi: 100, nvim: 200 } }
  }
  const p = M.weekPage(days, D(2026, 9, 20), 1, ["rofi"], {})
  assert.equal(p.label, "Sep 7 \u2013 Sep 13, 2026 \u00b7 W37")
  assert.equal(p.total, 200)
  assert.equal(p.days[1].ms, 200)
  assert.equal(p.days.filter((d) => d.today).length, 0)
  assert.equal(M.weekPage(days, D(2026, 9, 20), 1).total, 300)
})

test("weekPage: an empty week is all zeros with no divide-by-zero", () => {
  const p = M.weekPage({}, D(2026, 9, 20), 3)
  assert.equal(p.total, 0)
  assert.ok(p.days.every((d) => d.ms === 0 && d.rel === 0))
})

test("weeksBack and maxBack", () => {
  const now = D(2026, 9, 20)
  assert.equal(M.weeksBack(now, D(2026, 9, 14)), 0)
  assert.equal(M.weeksBack(now, D(2026, 9, 13)), 1)
  assert.equal(M.weeksBack(now, D(2025, 9, 21)), 52)
  assert.equal(M.weeksBack(now, D(2027, 1, 1)), 0) // future clamps to 0
  assert.equal(M.maxBack({}, now, 52), 0)
  assert.equal(M.maxBack({ "2026-09-20": {} }, now, 52), 0)
  assert.equal(M.maxBack({ "2026-08-31": {}, "2026-09-20": {} }, now, 52), 2) // W36 -> W38
  assert.equal(M.maxBack({ "2024-01-01": {} }, now, 52), 51) // capped at cap - 1
  assert.equal(M.maxBack({ "bad": {} }, now, 52), 0)
})

test("shiftDay moves by days, never past today or the oldest day", () => {
  assert.equal(M.shiftDay("2026-09-19", 1, "2026-09-20", "2025-09-22"), "2026-09-20")
  assert.equal(M.shiftDay("2026-09-20", 1, "2026-09-20", "2025-09-22"), "2026-09-20")
  assert.equal(M.shiftDay("2026-09-20", -1, "2026-09-20", "2025-09-22"), "2026-09-19")
  assert.equal(M.shiftDay("2026-03-01", -1, "2026-09-20", "2025-09-22"), "2026-02-28")
  assert.equal(M.shiftDay("2025-09-22", -1, "2026-09-20", "2025-09-22"), "2025-09-22")
  assert.equal(M.shiftDay("garbage", 1, "2026-09-20", ""), "garbage")
})

test("dayTitle", () => {
  assert.equal(M.dayTitle("2026-09-20", "2026-09-20"), "Today")
  assert.equal(M.dayTitle("2026-09-19", "2026-09-20"), "Yesterday")
  assert.equal(M.dayTitle("2026-09-17", "2026-09-20"), "Thu, Sep 17")
  assert.equal(M.dayTitle("2026-03-01", "2026-03-02"), "Yesterday")
})

test("dayInsights: top app, comparison with the day before, busiest day", () => {
  const days = {
    "2026-09-19": { total: 3600000, apps: { nvim: 3600000 } },
    "2026-09-20": { total: 5400000, apps: { nvim: 1800000, brave: 3600000 } }
  }
  const now = D(2026, 9, 20)
  const page = M.weekPage(days, now, 0)
  const r = M.dayInsights(days, "2026-09-20", "2026-09-20", page, [], {})
  deepEqual(r.map((x) => x.label), ["Top app", "vs yesterday", "Busiest day"])
  assert.equal(r[0].value, "Brave \u00b7 1h")
  assert.equal(r[1].value, "+30m")
  assert.equal(r[2].value, "Sun \u00b7 1h 30m")
  // A past day is compared with its own previous day, named by weekday.
  const past = M.dayInsights(days, "2026-09-19", "2026-09-20", page, [], {})
  assert.equal(past[1].label, "vs Fri")
  assert.equal(past[1].value, "\u2014") // no data for the 18th
  // Less than the day before.
  const less = { "2026-09-19": { total: 7200000, apps: { a: 7200000 } }, "2026-09-20": { total: 3600000, apps: { a: 3600000 } } }
  assert.equal(M.dayInsights(less, "2026-09-20", "2026-09-20", M.weekPage(less, now, 0), [], {})[1].value, "\u22121h")
  const same = { "2026-09-19": { total: 60000, apps: { a: 60000 } }, "2026-09-20": { total: 60000, apps: { a: 60000 } } }
  assert.equal(M.dayInsights(same, "2026-09-20", "2026-09-20", M.weekPage(same, now, 0), [], {})[1].value, "same")
})

test("dayInsights: empty data shows dashes, never throws", () => {
  const page = M.weekPage({}, D(2026, 9, 20), 0)
  const r = M.dayInsights({}, "2026-09-20", "2026-09-20", page, [], {})
  deepEqual(r.map((x) => x.value), ["\u2014", "\u2014", "\u2014"])
})

test("dayInsights respects ignored apps and custom names", () => {
  const days = { "2026-09-20": { total: 900, apps: { rofi: 800, nvim: 100 } } }
  const page = M.weekPage(days, D(2026, 9, 20), 0, ["rofi"], {})
  const r = M.dayInsights(days, "2026-09-20", "2026-09-20", page, ["rofi"], { nvim: "Editor" })
  assert.equal(r[0].value, "Editor \u00b7 <1m")
})

test("donutSlices: top apps, small ones folded into Other, angles add to a full turn", () => {
  const day = { total: 1000, apps: { a: 400, b: 300, c: 200, d: 50, e: 30, f: 15, g: 5 } }
  const s = M.donutSlices(day, {}, 6, 0.03)
  deepEqual(s.map((x) => x.name), ["A", "B", "C", "D", "E", "Other"])
  assert.equal(s[5].other, true)
  assert.equal(s[5].ms, 20) // f + g are under 3%
  assert.equal(s[0].startFrac, 0)
  const last = s[s.length - 1]
  assert.ok(Math.abs(last.startFrac + last.sweepFrac - 1) < 1e-9)
  s.forEach((x, i) => assert.equal(x.index, i))
})

test("donutSlices: never more than maxApps plus Other", () => {
  const apps = {}
  for (let i = 0; i < 12; i++) apps["app" + String.fromCharCode(97 + i)] = 100
  const s = M.donutSlices({ total: 1200, apps }, {}, 6, 0.03)
  assert.equal(s.length, 7)
  assert.equal(s[6].other, true)
  assert.equal(s[6].ms, 600)
})

test("donutSlices: no Other when everything fits; empty and single-app days", () => {
  assert.equal(M.donutSlices({ total: 30, apps: { a: 10, b: 20 } }, {}, 6, 0.03).some((x) => x.other), false)
  assert.equal(M.donutSlices(M.newDay(), {}, 6, 0.03).length, 0)
  const one = M.donutSlices({ total: 50, apps: { a: 50 } }, {}, 6, 0.03)
  assert.equal(one.length, 1)
  assert.equal(one[0].sweepFrac, 1)
})

test("donutSlices merges apps that share a custom name", () => {
  const day = { total: 100, apps: { zen: 40, firefox: 40, nvim: 20 } }
  const s = M.donutSlices(day, { zen: "Browser", firefox: "Browser" }, 6, 0.03)
  deepEqual(s.map((x) => x.name), ["Browser", "Nvim"])
  assert.equal(s[0].ms, 80)
})

// ---- Phase 3: archive and yearly view ----------------------------------------

const H = 3600000

test("parseHistory reads the archive, drops bad entries, and old files have none", () => {
  const text = JSON.stringify({
    version: 2,
    days: {},
    archive: { "2024-05-01": 1000.4, "2024-05-02": 0, "2024-05-03": -5, "2024-05-04": "x", "junk": 5, "2024-05-05": 2000 }
  })
  const r = M.parseHistory(text)
  assert.equal(r.ok, true)
  deepEqual(r.archive, { "2024-05-01": 1000, "2024-05-05": 2000 })
  // A version-1 file (no archive key) still loads.
  deepEqual(M.parseHistory('{"version":1,"days":{}}').archive, {})
  // An archive of the wrong type is an unreadable file, not silently emptied.
  assert.equal(M.parseHistory('{"archive": []}').ok, false)
  assert.equal(M.parseHistory('{"archive": "x"}').ok, false)
  assert.equal(M.parseHistory('{"archive": null}').ok, false)
})

test("serialize writes version 2 with a sorted archive and round-trips", () => {
  const days = M.addTime({}, "2026-09-20", "foot", 5000)
  const archive = { "2025-03-02": 200, "2024-12-31": 100 }
  const text = M.serialize(days, archive)
  const parsed = JSON.parse(text)
  assert.equal(parsed.version, 2)
  deepEqual(Object.keys(parsed.archive), ["2024-12-31", "2025-03-02"])
  const back = M.parseHistory(text)
  deepEqual(back.days, days)
  deepEqual(back.archive, archive)
  // no archive argument is fine
  deepEqual(JSON.parse(M.serialize(days)).archive, {})
})

test("dayTotals: archive underneath, detail on top, ignored apps left out of detail", () => {
  const days = {
    "2026-09-20": { total: 900, apps: { rofi: 800, nvim: 100 } },
    "2026-09-19": { total: 500, apps: { rofi: 500 } }
  }
  const archive = { "2025-01-01": 4000, "2026-09-20": 1 }
  const t = M.dayTotals(days, archive, ["rofi"], {})
  assert.equal(t["2025-01-01"], 4000)
  assert.equal(t["2026-09-20"], 100) // detail wins over the archive entry
  assert.equal(t["2026-09-19"], undefined) // everything on it was ignored
  assert.equal(M.dayTotals(days, archive, [], {})["2026-09-19"], 500)
  deepEqual(M.dayTotals({}, {}, [], {}), {})
})

test("yearsRange runs from the first recorded year to this one with no gaps", () => {
  deepEqual(M.yearsRange({}, "2026-09-20"), [])
  deepEqual(M.yearsRange({ "2026-01-02": 1 }, "2026-09-20"), [2026])
  deepEqual(M.yearsRange({ "2024-05-01": 1, "2026-09-01": 1 }, "2026-09-20"), [2024, 2025, 2026])
  deepEqual(M.yearsRange({ "2027-01-01": 1 }, "2026-09-20"), []) // future only
})

test("daysInYear, dateTitle and rangeLabel", () => {
  assert.equal(M.daysInYear(2024), 366)
  assert.equal(M.daysInYear(2025), 365)
  assert.equal(M.daysInYear(1900), 365)
  assert.equal(M.daysInYear(2000), 366)
  assert.equal(M.dateTitle("2026-09-19"), "Sat, Sep 19")
  assert.equal(M.dateTitle("nope"), "nope")
  assert.equal(M.rangeLabel("2026-09-03", "2026-09-11"), "Sep 3 – Sep 11")
  assert.equal(M.rangeLabel("2026-09-03", "2026-09-03"), "Sep 3")
  assert.equal(M.rangeLabel("bad", "2026-09-03"), "")
})

test("yearSummary: a partial first year is measured from the first recorded day", () => {
  const t = { "2026-09-14": H, "2026-09-15": 2 * H, "2026-09-16": 3 * H, "2026-09-18": H, "2026-09-20": 2 * H }
  const r = M.yearSummary(t, 2026, "2026-09-20")
  assert.equal(r.total, 9 * H)
  assert.equal(r.activeDays, 5)
  assert.equal(r.spanDays, 7) // Sep 14 - Sep 20, not the whole year
  assert.equal(r.averageDay, 1.8 * H)
  deepEqual(r.longestStreak, { days: 3, from: "2026-09-14", to: "2026-09-16" })
  deepEqual(r.longestBreak, { days: 1, from: "2026-09-17", to: "2026-09-17" }) // ties go to the earlier one
  deepEqual(r.peakDay, { key: "2026-09-16", ms: 3 * H })
  assert.equal(r.busiestWeek, null) // needs two weeks of span
  deepEqual(r.topMonths.map((m) => m.label), ["Sep"])
  assert.equal(r.months.length, 12)
  assert.equal(r.months[8].ms, 9 * H)
  assert.equal(r.months[8].days, 5)
  assert.equal(r.months[8].outside, false)
  assert.equal(r.months[0].outside, true) // before tracking began
  assert.equal(r.months[11].outside, true) // after today
  assert.equal(r.months[8].rel, 1)
})

test("yearSummary: a full past year, hand-checked", () => {
  const t = {
    "2025-01-06": H, "2025-01-07": 2 * H, "2025-01-08": H, // Mon-Wed
    "2025-03-10": 5 * H, // a Monday
    "2025-12-31": H // a Wednesday
  }
  const r = M.yearSummary(t, 2025, "2026-09-20")
  assert.equal(r.total, 10 * H)
  assert.equal(r.activeDays, 5)
  assert.equal(r.spanDays, 360) // Jan 6 - Dec 31 2025
  assert.equal(r.averageDay, 2 * H)
  deepEqual(r.longestStreak, { days: 3, from: "2025-01-06", to: "2025-01-08" })
  // Mar 11 - Dec 30 is day 70 to day 364 of the year: 295 days off.
  deepEqual(r.longestBreak, { days: 295, from: "2025-03-11", to: "2025-12-30" })
  deepEqual(r.peakDay, { key: "2025-03-10", ms: 5 * H })
  assert.equal(r.busiestWeek.ms, 5 * H)
  assert.equal(r.busiestWeek.key, "2025-03-10")
  assert.equal(r.busiestWeek.label, "Mar 10 – Mar 16, 2025 · W11")
  deepEqual(r.topMonths.map((m) => m.label + ":" + m.ms / H), ["Mar:5", "Jan:4", "Dec:1"])
  // Weekday rhythm averages every span day with that weekday, days off included.
  deepEqual(r.weekdays.map((d) => d.weekday), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
  assert.ok(Math.abs(r.weekdays[0].ms - (6 * H) / 52) < 1e-6) // 52 Mondays: 1h + 5h
  assert.equal(r.weekdays[0].rel, 1)
  assert.ok(Math.abs(r.weekdays[1].rel - 2 / 6) < 1e-9) // Tuesday: 2h over 52
  assert.equal(r.weekdays[3].ms, 0)
})

test("yearSummary: today with no time yet is left out, so it can't be a break", () => {
  const t = { "2026-09-18": 2 * H, "2026-09-19": H }
  const r = M.yearSummary(t, 2026, "2026-09-20")
  assert.equal(r.spanDays, 2)
  assert.equal(r.longestBreak, null)
  deepEqual(r.longestStreak, { days: 2, from: "2026-09-18", to: "2026-09-19" })
  // Once today has time it counts.
  const withToday = Object.assign({}, t, { "2026-09-20": H })
  assert.equal(M.yearSummary(withToday, 2026, "2026-09-20").spanDays, 3)
})

test("yearSummary: a break can run right up to the end of a past year", () => {
  const r = M.yearSummary({ "2025-06-01": H, "2025-06-02": H, "2026-02-01": H }, 2025, "2026-09-20")
  deepEqual(r.longestBreak, { days: 212, from: "2025-06-03", to: "2025-12-31" })
})

test("yearSummary: leap years have 29 days in February", () => {
  const r = M.yearSummary({ "2024-02-29": H }, 2024, "2025-06-01")
  assert.equal(r.spanDays, 307) // Feb 29 - Dec 31 2024
  deepEqual(r.longestBreak, { days: 306, from: "2024-03-01", to: "2024-12-31" })
  assert.equal(r.months[1].days, 1)
})

test("yearSummary: days after today never count", () => {
  const r = M.yearSummary({ "2026-09-20": H, "2026-09-25": 9 * H }, 2026, "2026-09-20")
  assert.equal(r.total, H)
  assert.equal(r.activeDays, 1)
  assert.equal(r.peakDay.ms, H)
})

test("yearSummary: nothing to show returns null", () => {
  assert.equal(M.yearSummary({}, 2026, "2026-09-20"), null)
  assert.equal(M.yearSummary({ "2026-09-20": H }, 2025, "2026-09-20"), null) // before tracking began
  assert.equal(M.yearSummary({ "2026-09-20": H }, 2027, "2026-09-20"), null) // in the future
  assert.equal(M.yearSummary({ "2024-05-01": H, "2026-09-01": H }, 2025, "2026-09-20"), null) // a year off
  assert.equal(M.yearSummary({ "2026-09-20": H }, 2026, "garbage"), null)
})

test("yearSummary: a week straddling New Year counts only this year's days", () => {
  const t = {}
  for (let d = 1; d <= 14; d++) t["2025-12-" + String(d).padStart(2, "0")] = H / 4
  t["2025-12-29"] = 2 * H
  t["2025-12-30"] = 2 * H
  t["2025-12-31"] = 2 * H
  t["2026-01-01"] = 9 * H // next year: must not leak into 2025's week
  const r = M.yearSummary(t, 2025, "2026-09-20")
  assert.equal(r.busiestWeek.key, "2025-12-29")
  assert.equal(r.busiestWeek.ms, 6 * H)
  assert.equal(r.total, 3.5 * H + 6 * H)
})

test("yearSummary: streaks reset across a day off and the earlier tie wins", () => {
  const t = {}
  ;["2026-03-02", "2026-03-03", "2026-03-05", "2026-03-06", "2026-03-09"].forEach((k) => (t[k] = H))
  const r = M.yearSummary(t, 2026, "2026-09-20")
  deepEqual(r.longestStreak, { days: 2, from: "2026-03-02", to: "2026-03-03" })
})

// ---- Phase 4: settings values, record week, recharge month --------------------

test("VERSION matches the manifest", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
  assert.equal(M.VERSION, manifest.version)
})

test("parseWeeks accepts only the offered lengths", () => {
  assert.equal(M.parseWeeks(12), 12)
  assert.equal(M.parseWeeks("24"), 24)
  assert.equal(M.parseWeeks(36), 36)
  assert.equal(M.parseWeeks(52), 52)
  assert.equal(M.parseWeeks(40), 52)
  assert.equal(M.parseWeeks(undefined), 52)
  assert.equal(M.parseWeeks("abc"), 52)
  assert.equal(M.parseWeeks(-1), 52)
})

test("parseBool understands hand-written values", () => {
  assert.equal(M.parseBool(true, false), true)
  assert.equal(M.parseBool("true", false), true)
  assert.equal(M.parseBool(1, false), true)
  assert.equal(M.parseBool(false, true), false)
  assert.equal(M.parseBool("false", true), false)
  assert.equal(M.parseBool(0, true), false)
  assert.equal(M.parseBool(undefined, true), true)
  assert.equal(M.parseBool("maybe", false), false)
  assert.equal(M.parseBool(null, true), true)
})

test("weekPage carries its Monday's key", () => {
  assert.equal(M.weekPage({}, D(2026, 9, 20), 0).key, "2026-09-14")
  assert.equal(M.weekPage({}, D(2026, 9, 20), 2).key, "2026-08-31")
})

test("recordWeek finds the busiest week once there are two weeks of data", () => {
  const t = {
    "2026-08-31": H, "2026-09-01": 2 * H, // week of Aug 31: 3h
    "2026-09-08": 4 * H, "2026-09-10": 3 * H, // week of Sep 7: 7h
    "2026-09-15": H // week of Sep 14: 1h
  }
  deepEqual(M.recordWeek(t, "2026-09-20"), { key: "2026-09-07", ms: 7 * H })
  // Under 14 days of history: nothing to compare yet.
  assert.equal(M.recordWeek({ "2026-09-10": H, "2026-09-15": H }, "2026-09-20"), null)
  assert.equal(M.recordWeek({}, "2026-09-20"), null)
  // Future days never count; ties go to the earlier week.
  const ties = { "2026-08-31": H, "2026-09-07": H, "2026-09-14": H, "2026-09-27": 9 * H }
  assert.equal(M.recordWeek(ties, "2026-09-20").key, "2026-08-31")
})

test("recordWeek spans years and archived totals", () => {
  const t = { "2024-03-04": 9 * H, "2026-09-16": H }
  assert.equal(M.recordWeek(t, "2026-09-20").key, "2024-03-04")
})

test("yearSummary: recharge month is the lightest well-measured month", () => {
  const t = {}
  // Jan: 20 days x 3h, Feb: 20 days x 1h, Mar: 20 days x 2h, all tracked.
  for (let d = 1; d <= 31; d++) t["2025-01-" + String(d).padStart(2, "0")] = 3 * H
  for (let d = 1; d <= 28; d++) t["2025-02-" + String(d).padStart(2, "0")] = H
  for (let d = 1; d <= 31; d++) t["2025-03-" + String(d).padStart(2, "0")] = 2 * H
  const r = M.yearSummary(t, 2025, "2025-03-31") // measured Jan 1 - Mar 31
  assert.equal(r.rechargeMonth.label, "Feb")
  assert.equal(r.rechargeMonth.ms, 28 * H)
  assert.equal(r.months[0].covered, 31)
  assert.equal(r.months[1].covered, 28)
})

test("yearSummary: recharge month skips months measured under two weeks", () => {
  // Tracking began Sep 10, so September is measured for 11 days only.
  const t = { "2026-09-10": H, "2026-09-20": H, "2026-08-01": 5 * H }
  const early = M.yearSummary(t, 2026, "2026-09-20")
  assert.equal(early.months[8].covered, 20 - 0) // span starts at the first recorded day, Aug 1
  // Only one month is measured for two weeks or more: nothing to compare.
  const t2 = { "2026-09-01": H, "2026-09-20": H }
  assert.equal(M.yearSummary(t2, 2026, "2026-09-20").rechargeMonth, null)
  // A fresh month with a few days is ignored in favour of full ones.
  const t3 = {}
  for (let d = 1; d <= 31; d++) t3["2026-07-" + String(d).padStart(2, "0")] = 4 * H
  for (let d = 1; d <= 31; d++) t3["2026-08-" + String(d).padStart(2, "0")] = 2 * H
  t3["2026-09-01"] = 1 // September is barely used, and only its first days have been measured
  const r3 = M.yearSummary(t3, 2026, "2026-09-10")
  assert.equal(r3.months[8].covered, 9) // Sep 1-9: the 10th has no time yet, so it is left out
  assert.equal(r3.rechargeMonth.label, "Aug") // Sep is skipped: under two weeks measured
  // Measured for two weeks or more, the same tiny month is the lightest.
  assert.equal(M.yearSummary(t3, 2026, "2026-09-20").rechargeMonth.label, "Sep")
})

test("fmtBytes and storageSummary", () => {
  assert.equal(M.fmtBytes(0), "0 B")
  assert.equal(M.fmtBytes(512), "512 B")
  assert.equal(M.fmtBytes(2048), "2 KB")
  assert.equal(M.fmtBytes(5 * 1024 * 1024), "5.0 MB")
  assert.equal(M.fmtBytes(NaN), "0 B")
  const days = M.addTime({}, "2026-09-20", "foot", 5000)
  const text = M.storageSummary(days, { "2024-01-01": 100, "2024-01-02": 200 })
  assert.match(text, /^\d+ (B|KB) · 1 day in detail · 2 archived \(totals kept forever\)$/)
  assert.match(M.storageSummary({}, {}), /0 days in detail · 0 archived/)
})
