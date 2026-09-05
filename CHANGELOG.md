# Changelog

## 0.2.0

- Zones are edited in the popup: "+ Add zone" opens a searchable tzdata
  picker with label fields, rows drag to reorder, click a header to rename,
  and a right-edge action removes. Keyboard: `j`/`k`, `Shift+J`/`Shift+K`,
  `Enter`, `x`, `a`, `Esc`.
- New zones default their short label to tzdata's abbreviation.
- Bar hover view shows up to `tickerZones` zones at rest and scrolls the
  rest through, ticker style (`tickerSpeed`).
- IPC: `add`, `addZone <zone>`, `removeZone <zone>`.

## 0.1.0

- Initial release, derived from
  [omarchy-timezones-plugin](https://github.com/sspaeti/omarchy-timezones-plugin)
  (MIT).
- Bar pill shows the current Swatch Internet Time (`@767`), with optional
  centibeats; hover expands to each zone's local time and a day/night glyph.
- Popup is a 1000-beat grid: a beat ruler across the top and one strip per
  zone showing the local hour at each beat span, tinted work/day/night, with
  local-midnight day boundaries marked and a "now" line at the exact beat.
- Hover any beat to convert it to local time in every zone.
- Right click toggles the popup; left click is left to the bar.
