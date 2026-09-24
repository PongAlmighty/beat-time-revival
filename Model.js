// Pure time/formatting logic for the beat-time widget. Swatch Internet Time
// has no zones — one beat is the same everywhere — so the grid axis is the
// 1000-beat Biel day and each configured zone is projected onto it. Zone
// math works on UTC-offset minutes fetched from tzdata via `date`; no
// Date-local calls, so the same instant renders consistently everywhere.
//
// Canonical definition (github.com/swatchtime/sample-code):
//   reference zone: Biel Mean Time = UTC+1, fixed, no DST
//   1 beat = 86.4 s (86400 / 1000); @000 at Biel midnight, @999 just before.

var DAY_MS = 86400000
var BEAT_MS = 86400            // 86.4 s
var BIEL_OFFSET_MS = 3600000   // UTC+1

function mod(n, m) {
  return ((n % m) + m) % m
}

// Fractional beats in [0, 1000) for a UTC instant.
function beatsAt(utcMs) {
  return mod(utcMs + BIEL_OFFSET_MS, DAY_MS) / BEAT_MS
}

// Whole beat, 0..999.
function beatAt(utcMs) {
  return Math.floor(beatsAt(utcMs)) % 1000
}

function pad3(n) {
  return (n < 10 ? "00" : n < 100 ? "0" : "") + n
}

// "@767" — or "@767.42" with centibeats. Rounds to 2 decimals *before*
// wrapping so 999.995 shows "@000.00", never "@1000.00".
function beatLabel(utcMs, centibeats) {
  if (!centibeats) return "@" + pad3(beatAt(utcMs))
  var rounded = Math.round(beatsAt(utcMs) * 100) / 100
  if (rounded >= 1000) rounded -= 1000
  var whole = Math.floor(rounded)
  var frac = Math.round((rounded - whole) * 100)
  return "@" + pad3(whole) + "." + (frac < 10 ? "0" : "") + frac
}

// UTC ms of the most recent Biel midnight (23:00 UTC) — beat @000, column 0.
function bielDayStartUtc(nowUtcMs) {
  var biel = nowUtcMs + BIEL_OFFSET_MS
  return biel - mod(biel, DAY_MS) - BIEL_OFFSET_MS
}

// UTC ms of a (possibly fractional) beat on the given Biel day.
function beatToUtc(dayStartUtcMs, beats) {
  return dayStartUtcMs + beats * BEAT_MS
}

// UTC ms of a zone's most recent local midnight — the left edge of the grid
// when it is aligned to that zone's day instead of the Biel day.
function localDayStartUtc(nowUtcMs, offsetMin) {
  var local = nowUtcMs + offsetMin * 60000
  return local - mod(local, DAY_MS) - offsetMin * 60000
}

// Fractional beats from the grid's left edge to a UTC instant. With the
// grid on the Biel day this is beatsAt(); on a zone's day it is shifted by
// that zone's midnight, e.g. UTC-7 midnight is @333.33 so the "now" line
// and hover positions move left by that much.
function gridPos(utcMs, gridStartUtcMs) {
  return (utcMs - gridStartUtcMs) / BEAT_MS
}

// "+0200" / "-0930" → signed minutes east of UTC.
function parseUtcOffset(text) {
  var m = /^([+-])(\d{2}):?(\d{2})$/.exec(String(text || "").trim())
  if (!m) return null
  var minutes = parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
  return m[1] === "-" ? -minutes : minutes
}

// Output of the offsets probe: one "<key> <±HHMM> <ABBR>" line per zone.
function parseOffsetLines(text) {
  var result = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 2) continue
    var offset = parseUtcOffset(parts[1])
    if (offset === null) continue
    result[parts[0]] = { offsetMin: offset, abbr: parts.length > 2 ? parts[2] : "" }
  }
  return result
}

// Local wall-clock fields of a UTC instant in a fixed-offset zone.
function localFields(utcMs, offsetMin) {
  var d = new Date(utcMs + offsetMin * 60000)
  return {
    hour: d.getUTCHours(),
    day: d.getUTCDate(),
    weekday: d.getUTCDay(),
    month: d.getUTCMonth(),
    minute: d.getUTCMinutes()
  }
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Grid granularity: beats per column. Anything that does not divide 1000
// evenly falls back to 50 (20 columns of 72 minutes each).
var CELL_SIZES = [25, 40, 50, 100, 125, 200]
function cellSize(value) {
  var n = parseInt(value, 10)
  return CELL_SIZES.indexOf(n) === -1 ? 50 : n
}

// Visual band for a cell: business hours pop, waking hours mid, night dark.
function tintFor(hour) {
  if (hour >= 8 && hour < 18) return "work"
  if (hour >= 6 && hour < 23) return "day"
  return "night"
}

// One zone cell for the beat span [col*size, (col+1)*size): the local hour
// at the middle of the span, which is the hour most of the span falls in.
// Spans are 72 minutes at 50 beats/cell, so the hour at the left edge
// would mislabel a 22:48-24:00 cell as 22. If the zone's local midnight
// falls inside the span, the cell is a day boundary and carries the new
// day's label instead.
function cell(col, size, dayStartUtcMs, offsetMin) {
  var startUtc = beatToUtc(dayStartUtcMs, col * size)
  var endUtc = beatToUtc(dayStartUtcMs, (col + 1) * size)
  var localStart = startUtc + offsetMin * 60000
  var localEnd = endUtc + offsetMin * 60000
  // A midnight k*DAY lies in [localStart, localEnd) iff the day index of
  // (localEnd - 1) exceeds that of (localStart - 1).
  var crossesMidnight = Math.floor((localEnd - 1) / DAY_MS) > Math.floor((localStart - 1) / DAY_MS)
  var f = localFields((startUtc + endUtc) / 2, offsetMin)
  var dayFields = localFields(endUtc - 1, offsetMin)
  return {
    hour: f.hour,
    isMidnight: crossesMidnight,
    dayLabel: WEEKDAYS[dayFields.weekday] + " " + dayFields.day,
    tint: tintFor(f.hour)
  }
}

// Ruler cell: the beat at which the column starts, e.g. "@000", "050".
// `gridStartUtcMs` moves the grid's left edge off Biel midnight (a zone's
// own midnight), so the labels start mid-day and wrap past @999.
function rulerLabel(col, size, gridStartUtcMs) {
  var origin = gridStartUtcMs === undefined ? 0 : beatsAt(gridStartUtcMs)
  var b = Math.floor(mod(origin + col * size, 1000))
  return col === 0 ? "@" + pad3(b) : pad3(b)
}

// Configurable strings (icon, labels, abbreviations) are rendered by Text
// elements whose default AutoText format detects rich text — strip the
// characters that could smuggle markup (e.g. <img src=...>) into the
// long-lived shell process.
function plainText(value) {
  return String(value === null || value === undefined ? "" : value).replace(/[<>&]/g, "")
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// "07:12" for a zone at a UTC instant; "7:12pm" on a 12-hour clock. The
// meridiem is glued on lowercase so the label stays narrow in the bar and
// the row headers.
function timeLabel(utcMs, offsetMin, twelveHour) {
  var f = localFields(utcMs, offsetMin)
  if (!twelveHour) return pad2(f.hour) + ":" + pad2(f.minute)
  return (f.hour % 12 || 12) + ":" + pad2(f.minute) + (f.hour < 12 ? "am" : "pm")
}

// Grid cell hour: "14", or "2p" on a 12-hour clock ("12a" is midnight).
function hourLabel(hour, twelveHour) {
  if (!twelveHour) return String(hour)
  return (hour % 12 || 12) + (hour < 12 ? "a" : "p")
}

// "Thu 21 Aug" style date.
function dateLabel(utcMs, offsetMin) {
  var f = localFields(utcMs, offsetMin)
  return WEEKDAYS[f.weekday] + " " + f.day + " " + MONTHS[f.month]
}

// Offset relative to home: "+6h", "−9h", "+5:30", "" for home itself.
function diffLabel(offsetMin, homeOffsetMin) {
  var diff = offsetMin - homeOffsetMin
  if (diff === 0) return ""
  var sign = diff < 0 ? "−" : "+"
  var abs = Math.abs(diff)
  var h = Math.floor(abs / 60)
  var m = abs % 60
  return sign + (m === 0 ? h + "h" : h + ":" + pad2(m))
}

// Day/night glyph for a zone at a UTC instant (Nerd Font md-weather_sunny /
// md-weather_night). Night is the "asleep" band; work and day both read as
// awake, which is the question the bar label answers.
function dayNightGlyph(utcMs, offsetMin) {
  return tintFor(localFields(utcMs, offsetMin).hour) === "night" ? "󰖔" : "󰖙"
}

// One bar-label entry per non-home zone: "󰖙 NY 07:12".
function compactParts(zones, nowUtcMs, glyphs, twelveHour) {
  var parts = []
  for (var i = 0; i < zones.length; i++) {
    var z = zones[i]
    if (z.home || z.offsetMin === undefined || z.offsetMin === null) continue
    var s = plainText(z.shortLabel) + " " + timeLabel(nowUtcMs, z.offsetMin, twelveHour)
    if (glyphs) s = dayNightGlyph(nowUtcMs, z.offsetMin) + " " + s
    parts.push(s)
  }
  return parts
}

var SEPARATOR = " · "

// Compact bar label shown on hover: "󰖙 NY 07:12 · 󰖔 CDO 19:12".
function compactLabel(zones, nowUtcMs, glyphs, twelveHour) {
  return compactParts(zones, nowUtcMs, glyphs, twelveHour).join(SEPARATOR)
}

// ---- Zone list editing.

// `timedatectl list-timezones` output → ["Africa/Abidjan", ...].
function parseTimezoneList(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var z = lines[i].trim()
    if (z !== "" && /^[A-Za-z0-9_\/+-]+$/.test(z)) out.push(z)
  }
  return out
}

// "America/Argentina/Buenos_Aires" → "Buenos Aires"; "Etc/GMT+5" → "GMT+5".
function cityLabel(zone) {
  var parts = String(zone || "").split("/")
  return parts[parts.length - 1].replace(/_/g, " ")
}

// Bar short label for a new zone: the tzdata abbreviation when it is a
// real one ("JST", "CET"), else the city's first three letters — tzdata
// hands back numeric offsets ("+04") for zones with no conventional name.
function shortLabelFor(zone, abbr) {
  var a = String(abbr || "").trim()
  if (/^[A-Z]{2,5}$/.test(a)) return a
  var city = cityLabel(zone).replace(/[^A-Za-z]/g, "")
  return city.substring(0, 3).toUpperCase()
}

// Index of `zone` in a zone config list, or -1.
function zoneIndex(zoneConfig, zone) {
  for (var i = 0; i < zoneConfig.length; i++) {
    if (!zoneConfig[i].home && String(zoneConfig[i].zone || "") === zone) return i
  }
  return -1
}

// Copy of `list` with the item at `from` moved so it lands at index `to`.
function moveItem(list, from, to) {
  var out = list.slice()
  if (from < 0 || from >= out.length) return out
  var clamped = Math.max(0, Math.min(out.length - 1, to))
  var item = out.splice(from, 1)[0]
  out.splice(clamped, 0, item)
  return out
}

// Fallback when the widget entry in shell.json carries no "zones" array —
// the real configuration belongs there. The home row (zone: "") tracks the
// system timezone, so travel updates it.
function defaultZones() {
  return [
    { label: "Home", shortLabel: "HOME", zone: "", home: true },
    { label: "East Coast", shortLabel: "NY", zone: "America/New_York" },
    { label: "West Coast", shortLabel: "SF", zone: "America/Los_Angeles" }
  ]
}

if (typeof module !== "undefined") {
  module.exports = {
    DAY_MS: DAY_MS,
    BEAT_MS: BEAT_MS,
    beatsAt: beatsAt,
    beatAt: beatAt,
    beatLabel: beatLabel,
    bielDayStartUtc: bielDayStartUtc,
    beatToUtc: beatToUtc,
    localDayStartUtc: localDayStartUtc,
    gridPos: gridPos,
    parseUtcOffset: parseUtcOffset,
    parseOffsetLines: parseOffsetLines,
    localFields: localFields,
    cellSize: cellSize,
    cell: cell,
    rulerLabel: rulerLabel,
    tintFor: tintFor,
    timeLabel: timeLabel,
    hourLabel: hourLabel,
    dateLabel: dateLabel,
    diffLabel: diffLabel,
    dayNightGlyph: dayNightGlyph,
    compactParts: compactParts,
    compactLabel: compactLabel,
    SEPARATOR: SEPARATOR,
    parseTimezoneList: parseTimezoneList,
    cityLabel: cityLabel,
    shortLabelFor: shortLabelFor,
    zoneIndex: zoneIndex,
    moveItem: moveItem,
    plainText: plainText,
    defaultZones: defaultZones
  }
}
