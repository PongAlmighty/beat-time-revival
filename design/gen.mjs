// Generates the three mockup artboards (Idle, RowHover, AddZone) for the
// add/remove-zone UI, matching the shell's real tokens and using Model.js
// for the grid data. Run: node design/gen.mjs
import { createRequire } from "node:module"
import { writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const M = createRequire(import.meta.url)(join(here, "..", "Model.js"))

// ---- Shell tokens (Style.qml defaults, scale 1, theme tr909newcolors).
const FG = "#8f8c87", BG = "#090907", ACCENT = "#b4666f"
const FONT = "'JetBrains Mono', 'JetBrainsMono Nerd Font', ui-monospace, monospace"
const darker = (hex, f) => {
  const n = parseInt(hex.slice(1), 16)
  const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(v => Math.round(v / f))
  return "#" + c.map(v => v.toString(16).padStart(2, "0")).join("")
}
const alpha = (hex, a) => {
  const n = parseInt(hex.slice(1), 16)
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`
}
const FG15 = darker(FG, 1.5), FG14 = darker(FG, 1.4), FG16 = darker(FG, 1.6)

const cellW = (660 - 19) / 20, cellH = 38, rulerH = 22, headerW = 168, headerGap = 14, rowGap = 6
const actionGap = 8, actionW = 22
const stripX = headerW + headerGap
const stripW = 660

// ---- Scene: the screenshot's moment, Sat 5 Sep 2026 10:34 PDT.
const nowUtc = Date.parse("2026-09-05T17:34:20Z")
const dayStart = M.bielDayStartUtc(nowUtc)
const nowBeats = M.beatsAt(nowUtc)
const zones = [
  { label: "Los Angeles", abbr: "PDT", off: -420, home: true },
  { label: "East Coast", abbr: "EDT", off: -240 },
  { label: "Cagayan de Oro", abbr: "PHT", off: 480 }
]
const homeOff = zones[0].off

// ---- Icons: stroke SVG on a 14px grid, currentColor.
const svg = (body, size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:block">${body}</svg>`
const ICON = {
  sun: svg('<circle cx="12" cy="12" r="4"></circle><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"></path>', 12),
  moon: svg('<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"></path>', 12),
  closeCircle: svg('<circle cx="12" cy="12" r="9"></circle><path d="M15 9l-6 6M9 9l6 6"></path>'),
  check: svg('<path d="M20 6L9 17l-5-5"></path>'),
  chevron: svg('<path d="M6 9l6 6 6-6"></path>', 12),
  plus: svg('<path d="M12 5v14M5 12h14"></path>', 11)
}

const css = `
  body { margin: 0; background: #14140f; font-family: ${FONT}; font-size: 12px; color: ${FG}; -webkit-font-smoothing: antialiased; }
  a { color: ${ACCENT}; } a:hover { color: ${FG}; }
  .card { position: relative; background: ${BG}; border: 2px solid ${ACCENT}; padding: 14px; display: inline-block; }
  .rows { display: flex; flex-direction: column; gap: ${rowGap}px; position: relative; }
  .row { display: flex; align-items: center; height: ${cellH}px; }
  .ruler { height: ${rulerH}px; }
  .hdr { width: ${headerW}px; flex: none; display: flex; flex-direction: column; gap: 2px; }
  .hdr .l1 { display: flex; align-items: center; gap: 6px; }
  .hdr .l2 { display: flex; align-items: center; gap: 6px; }
  .name { font-size: 12px; color: ${FG}; }
  .abbr { font-size: 10px; color: ${FG15}; }
  .time { font-size: 12px; font-weight: 700; color: ${FG}; }
  .sub { font-size: 10px; color: ${FG15}; }
  .strip { margin-left: ${headerGap}px; width: ${stripW}px; flex: none; display: flex; gap: 1px; }
  .cell { width: ${cellW}px; height: ${cellH}px; border-radius: 3px; display: flex; align-items: center; justify-content: center; font-size: 10px; line-height: 0.85; text-align: center; }
  .rcell { width: ${cellW}px; height: ${rulerH}px; display: flex; align-items: center; font-size: 9px; color: ${FG14}; }
  .act { margin-left: ${actionGap}px; width: ${actionW}px; height: ${actionW}px; flex: none; display: flex; align-items: center; justify-content: center; color: ${FG}; }
  .now { position: absolute; top: 0; width: 2px; background: ${ACCENT}; opacity: 0.9; border-radius: 1px; }
  .add { height: ${rulerH}px; display: flex; align-items: center; }
  .addlink { display: flex; align-items: center; gap: 6px; font-size: 11px; color: ${FG15}; }
  .ctl { height: 28px; box-sizing: border-box; border: 1px solid ${alpha(FG, 0.4)}; background: ${alpha(FG, 0.04)}; display: flex; align-items: center; padding: 0 10px; font-size: 12px; color: ${FG}; }
  .ctl.hot { border-color: ${alpha(FG, 0.25)}; background: ${alpha(FG, 0.08)}; }
  .ph { color: ${FG16}; }
  .cursor { position: absolute; pointer-events: none; }
  .tip { position: absolute; background: ${BG}; border: 1px solid ${FG}; color: ${FG}; font-size: 10px; padding: 3px 6px; white-space: nowrap; }
`

const rulerRow = (hover) => {
  const cells = Array.from({ length: 20 }, (_, i) => `<div class="rcell">${M.rulerLabel(i, 50)}</div>`).join("")
  return `<div class="row ruler">
    <div class="hdr" style="flex-direction: row; align-items: center; gap: 6px;">
      <span class="time" style="color: ${hover ? ACCENT : FG}">${hover ? "@" + String(hover).padStart(3, "0") : M.beatLabel(nowUtc)}</span>
      <span class="sub">Internet Time</span>
    </div>
    <div class="strip">${cells}</div>
    <div class="act"></div>
  </div>`
}

const tintColor = (t, hot) => t === "work" ? alpha(ACCENT, hot ? 0.5 : 0.28) : t === "day" ? alpha(FG, hot ? 0.24 : 0.10) : alpha(FG, hot ? 0.16 : 0.035)

const zoneRow = (z, opts = {}) => {
  const focus = opts.hoverBeat != null ? M.beatToUtc(dayStart, opts.hoverBeat) : nowUtc
  const hotCol = opts.hoverBeat != null ? Math.floor(opts.hoverBeat / 50) : -1
  const cells = Array.from({ length: 20 }, (_, i) => {
    const c = M.cell(i, 50, dayStart, z.off)
    const text = c.isMidnight ? c.dayLabel.replace(" ", "<br>") : String(c.hour)
    const color = c.isMidnight ? FG : c.tint === "night" ? FG16 : FG
    const weight = c.isMidnight ? "700" : "400"
    const size = c.isMidnight ? "8px" : "10px"
    return `<div class="cell" style="background: ${tintColor(c.tint, i === hotCol)}; color: ${color}; font-weight: ${weight}; font-size: ${size};">${text}</div>`
  }).join("")
  const isNight = M.tintFor(M.localFields(focus, z.off).hour) === "night"
  const timeColor = opts.hoverBeat != null ? ACCENT : FG
  const homeDate = M.dateLabel(focus, homeOff), zoneDate = M.dateLabel(focus, z.off)
  const sub = z.home ? zoneDate : M.diffLabel(z.off, homeOff) + (zoneDate !== homeDate ? "&nbsp;&nbsp;" + zoneDate : "")
  const action = z.home ? `<div class="act"></div>` : opts.showRemove
    ? `<div class="act" style="position: relative; background: ${opts.removeHot ? alpha(FG, 0.08) : "transparent"}; color: ${FG};">${ICON.closeCircle}${opts.removeHot ? `<div class="tip" style="left: 50%; transform: translateX(-50%); top: 26px;">Remove</div>` : ""}</div>`
    : `<div class="act"></div>`
  return `<div class="row">
    <div class="hdr">
      <div class="l1"><span class="name" style="font-weight: ${z.home ? 700 : 400}">${z.label}</span><span class="abbr">(${z.abbr})</span></div>
      <div class="l2"><span style="display:flex; color: ${timeColor}">${isNight ? ICON.moon : ICON.sun}</span><span class="time" style="color: ${timeColor}">${M.timeLabel(focus, z.off)}</span><span class="sub">${sub}</span></div>
    </div>
    <div class="strip">${cells}</div>
    ${action}
  </div>`
}

const addRowIdle = (hot) => `<div class="add">
  <div class="addlink" style="color: ${hot ? FG : FG15}">${ICON.plus}<span>Add zone</span></div>
</div>`

// Expanded add row: searchable zone picker (trigger + open list), label
// fields, confirm/cancel. Mirrors SearchableDropdown + TextField + the
// network panel's confirm action button.
const addRowOpen = () => {
  const options = ["Asia/Tokyo", "Asia/Tomsk", "America/Toronto", "Europe/Tallinn"]
  const list = options.map((o, i) => `<div style="height: 28px; display: flex; align-items: center; padding: 0 10px; background: ${i === 0 ? alpha(FG, 0.08) : "transparent"}; color: ${i === 0 ? ACCENT : FG};">${o}</div>`).join("")
  return `<div class="add" style="position: relative; overflow: visible; height: 28px; gap: 8px;">
    <div style="position: relative; width: 240px;">
      <div class="ctl hot" style="width: 240px; justify-content: space-between;"><span>Asia/Tokyo</span><span style="display:flex; color: ${FG14}">${ICON.chevron}</span></div>
      <div style="position: absolute; left: 0; top: 30px; width: 240px; background: ${BG}; border: 1px solid ${ACCENT}; padding: 1px; z-index: 5;">
        <div style="height: 38px; display: flex; align-items: center; padding: 0 5px;">
          <div class="ctl hot" style="width: 100%; height: 28px;"><span>to</span><span style="display:inline-block; width: 1px; height: 14px; background: ${FG}; margin-left: 1px;"></span></div>
        </div>
        <div style="height: 1px; background: ${alpha(FG, 0.10)}"></div>
        ${list}
      </div>
    </div>
    <div class="ctl" style="width: 128px;"><span>Tokyo</span></div>
    <div class="ctl" style="width: 64px;"><span>TYO</span></div>
    <div class="act" style="margin-left: 0;">${ICON.check}</div>
    <div class="act" style="margin-left: 0; color: ${FG15}">${ICON.closeCircle}</div>
  </div>`
}

const pointer = (x, y) => `<div class="cursor" style="left: ${x}px; top: ${y}px;"><svg width="16" height="20" viewBox="0 0 16 20" style="display:block"><path d="M1 1l14 10-6 1 3 6-2 1-3-6-4 5z" fill="${FG}" stroke="${BG}" stroke-width="1.2"></path></svg></div>`

const page = (title, body, note) => `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap">
  <style>${css}</style>
</helmet>
<div style="padding: 28px 28px 24px 28px; display: flex; flex-direction: column; gap: 10px; align-items: flex-start;">
  <div style="font-size: 11px; color: ${FG15}; letter-spacing: 1px; text-transform: uppercase;">${title}</div>
  <div class="card" style="position: relative;">
    ${body}
  </div>
  <div style="font-size: 11px; color: ${FG15}; max-width: 900px; line-height: 1.5; text-wrap: pretty;">${note}</div>
</div>
</x-dc>
</body>
</html>
`

const nowLine = (rowsHeight) => `<div class="now" style="left: ${stripX + nowBeats / 1000 * stripW - 1}px; height: ${rowsHeight}px;"></div>`
const rowsH = rulerH + rowGap + zones.length * cellH + (zones.length - 1) * rowGap

// 1. Idle — nothing new is visible except the muted add affordance.
const idle = `<div class="rows">
  ${rulerRow()}
  ${zones.map(z => zoneRow(z)).join("")}
  ${nowLine(rowsH)}
</div>
<div style="height: ${rowGap}px"></div>
${addRowIdle(false)}`

// 2. Row hover — pointer over the East Coast strip: conversion header
//    at @330, and the remove button revealed at the row's right edge.
const hoverBeat = 330
const hover = `<div class="rows">
  ${rulerRow(hoverBeat)}
  ${zoneRow(zones[0], { hoverBeat })}
  ${zoneRow(zones[1], { hoverBeat, showRemove: true, removeHot: true })}
  ${zoneRow(zones[2], { hoverBeat })}
  ${nowLine(rowsH)}
</div>
<div style="height: ${rowGap}px"></div>
${addRowIdle(false)}
${pointer(stripX + hoverBeat / 1000 * stripW + 4, rulerH + rowGap + cellH + rowGap + 22)}`

// 3. Add zone — the add row expanded with the picker open on "to".
const add = `<div class="rows">
  ${rulerRow()}
  ${zones.map(z => zoneRow(z)).join("")}
  ${nowLine(rowsH)}
</div>
<div style="height: ${rowGap}px"></div>
${addRowOpen()}`

writeFileSync(join(here, "Main.dc.html"), page("1 · Idle",
  idle,
  "Unchanged layout. The only addition is the muted “+ Add zone” line under the last strip, in the same caption color as the offsets. Home row (bold) never gets a remove control: it tracks the system timezone."))
writeFileSync(join(here, "RowHover.dc.html"), page("2 · Row hover, remove",
  hover,
  "Pointer over the East Coast strip at @330: every header converts (accent), and a 22px close-circle action appears at the row's right edge, the same control Bluetooth uses for “Forget”. Hover fill is foreground at 8% with a plain tooltip. No confirmation: removal writes the zones array back to shell.json immediately."))
writeFileSync(join(here, "AddZone.dc.html"), page("3 · Add zone",
  add,
  "Clicking “+ Add zone” swaps the line for a searchable zone picker (598 tzdata names, filtered as you type), a label field and a short-label field prefilled from the chosen city, then check to commit and close-circle to cancel. Enter commits, Escape cancels. Controls are the shell's 28px TextField and SearchableDropdown with 1px foreground-40% borders."))
console.log("wrote Main.dc.html RowHover.dc.html AddZone.dc.html")
