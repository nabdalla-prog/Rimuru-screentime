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
