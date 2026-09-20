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

test("pruneDays keeps the window and drops older days", () => {
  const days = {
    "2025-09-19": M.newDay(),
    "2025-09-20": M.newDay(),
    "2026-09-20": M.newDay()
  }
  const kept = M.pruneDays(days, 365, D(2026, 9, 20))
  deepEqual(Object.keys(kept).sort(), ["2025-09-20", "2026-09-20"])
})

test("parseHistory: blank and missing days are empty but valid", () => {
  deepEqual(M.parseHistory(""), { ok: true, days: {} })
  deepEqual(M.parseHistory("  \n"), { ok: true, days: {} })
  deepEqual(M.parseHistory(undefined), { ok: true, days: {} })
  deepEqual(M.parseHistory("{}"), { ok: true, days: {} })
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

test("recentDays spans n days ending today, oldest first", () => {
  const days = {
    "2026-09-20": { total: 4000, apps: { a: 4000 } },
    "2026-09-18": { total: 2000, apps: { a: 2000 } }
  }
  const out = M.recentDays(days, D(2026, 9, 20), 7)
  assert.equal(out.length, 7)
  assert.equal(out[0].key, "2026-09-14")
  assert.equal(out[6].key, "2026-09-20")
  assert.equal(out[6].today, true)
  assert.equal(out[6].rel, 1)
  assert.equal(out[4].ms, 2000)
  assert.equal(out[4].rel, 0.5)
  assert.equal(out[5].ms, 0)
  assert.equal(out.filter((d) => d.today).length, 1)
  // 2026-09-20 is a Sunday
  assert.equal(out[6].label, "S")
})

test("recentDays handles month boundaries", () => {
  const out = M.recentDays({}, D(2026, 3, 2), 4)
  deepEqual(out.map((d) => d.key), ["2026-02-27", "2026-02-28", "2026-03-01", "2026-03-02"])
  assert.ok(out.every((d) => d.rel === 0))
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

test("recentDays leaves ignored apps out of each day's total", () => {
  const days = {
    "2026-09-20": { total: 300, apps: { rofi: 100, nvim: 200 } },
    "2026-09-19": { total: 100, apps: { rofi: 100 } }
  }
  const out = M.recentDays(days, D(2026, 9, 20), 2, ["rofi"], {})
  assert.equal(out[1].ms, 200)
  assert.equal(out[0].ms, 0)
  assert.equal(M.recentDays(days, D(2026, 9, 20), 2)[0].ms, 100)
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
