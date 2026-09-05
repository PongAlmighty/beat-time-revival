// Run: node --test test/
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

const utc = (s) => new Date(s).getTime()

test("canonical swatchtime test vectors", () => {
  assert.equal(M.beatLabel(utc("2025-01-01T00:00:00Z")), "@041")
  assert.equal(M.beatLabel(utc("2025-01-01T23:00:00Z")), "@000")
  assert.equal(M.beatLabel(utc("2025-06-01T12:34:56Z")), "@565")
})

test("beat boundaries are exactly 86.4 s apart from Biel midnight", () => {
  const midnight = utc("2025-01-01T23:00:00Z")
  assert.equal(M.beatAt(midnight), 0)
  assert.equal(M.beatAt(midnight + 86399), 0)
  assert.equal(M.beatAt(midnight + 86400), 1)
  assert.equal(M.beatAt(midnight - 1), 999)
})

test("centibeats round first, then wrap — never @1000.00", () => {
  const midnight = utc("2025-01-01T23:00:00Z")
  assert.equal(M.beatLabel(midnight - 1, true), "@000.00")
  assert.equal(M.beatLabel(midnight - 500, true), "@999.99")
  assert.equal(M.beatLabel(utc("2025-01-01T00:00:00Z"), true), "@041.67")
})

test("bielDayStartUtc is the most recent 23:00 UTC", () => {
  assert.equal(M.bielDayStartUtc(utc("2025-01-01T00:00:00Z")), utc("2024-12-31T23:00:00Z"))
  assert.equal(M.bielDayStartUtc(utc("2025-01-01T22:59:59Z")), utc("2024-12-31T23:00:00Z"))
  assert.equal(M.bielDayStartUtc(utc("2025-01-01T23:00:00Z")), utc("2025-01-01T23:00:00Z"))
})

test("beatToUtc round-trips beatsAt", () => {
  const now = utc("2025-06-01T12:34:56Z")
  const start = M.bielDayStartUtc(now)
  assert.equal(M.beatToUtc(start, M.beatsAt(now)), now)
})

test("cellSize accepts only even divisors of 1000", () => {
  assert.equal(M.cellSize(50), 50)
  assert.equal(M.cellSize("25"), 25)
  assert.equal(M.cellSize(30), 50)
  assert.equal(M.cellSize(undefined), 50)
})

test("cell marks the column containing a zone's local midnight", () => {
  const start = utc("2024-12-31T23:00:00Z") // @000
  // UTC zone: local midnight is 01:00 Biel = @041.67 → column 0 at 50/cell.
  const c0 = M.cell(0, 50, start, 0)
  assert.equal(c0.isMidnight, true)
  assert.equal(c0.dayLabel, "Wed 1")
  assert.equal(c0.hour, 23)
  assert.equal(c0.tint, "night")
  assert.equal(M.cell(1, 50, start, 0).isMidnight, false)
  // Biel itself: midnight is exactly column 0's start.
  const biel0 = M.cell(0, 50, start, 60)
  assert.equal(biel0.isMidnight, true)
  assert.equal(biel0.hour, 0)
  assert.equal(M.cell(19, 50, start, 60).isMidnight, false)
  // New York (UTC-5): midnight = 05:00 UTC = 06:00 Biel = @250 → column 5.
  assert.equal(M.cell(4, 50, start, -300).isMidnight, false)
  assert.equal(M.cell(5, 50, start, -300).isMidnight, true)
  assert.equal(M.cell(5, 50, start, -300).hour, 0)
})

test("ruler labels", () => {
  assert.equal(M.rulerLabel(0, 50), "@000")
  assert.equal(M.rulerLabel(1, 50), "050")
  assert.equal(M.rulerLabel(19, 50), "950")
})

test("day/night glyph and compact label", () => {
  const noonUtc = utc("2025-06-01T12:00:00Z")
  assert.equal(M.dayNightGlyph(noonUtc, 0), "󰖙")
  assert.equal(M.dayNightGlyph(noonUtc, 12 * 60), "󰖔")
  const zones = [
    { home: true, shortLabel: "HOME", offsetMin: 120 },
    { shortLabel: "NY", offsetMin: -240 },
    { shortLabel: "TK", offsetMin: 540 }
  ]
  assert.equal(M.compactLabel(zones, noonUtc, false), "NY 08:00 · TK 21:00")
  assert.equal(M.compactLabel(zones, noonUtc, true), "󰖙 NY 08:00 · 󰖙 TK 21:00")
})

test("offset parsing", () => {
  assert.equal(M.parseUtcOffset("+0530"), 330)
  assert.equal(M.parseUtcOffset("-0930"), -570)
  assert.equal(M.parseUtcOffset("bogus"), null)
  const parsed = M.parseOffsetLines("HOME +0200 CEST\nAmerica/New_York -0400 EDT\n")
  assert.deepEqual(parsed["America/New_York"], { offsetMin: -240, abbr: "EDT" })
})

test("plainText strips markup characters", () => {
  assert.equal(M.plainText("<img src=x>&"), "img src=x")
})
