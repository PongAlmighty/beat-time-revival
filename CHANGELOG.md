# Changelog

## 0.3.0

- Alignment toggle at the popup's bottom right: start every row at `@000`
  (the Biel day, as before) or at the home row's local midnight, so home
  reads 0 to 23 left to right. Saved as `alignment` in the widget entry;
  IPC `toggleAlignment` flips it too.
- 12-hour clock toggle beside it: row headers, grid cells and the bar's
  hover view switch between `19:48` / `19` and `7:48pm` / `7p`. Saved as
  `hourFormat`; IPC `toggleHourFormat`.
- Grid cells are labeled by the hour at the middle of their span rather
  than at their left edge, so a 22:48 to midnight cell reads 23, not 22.
- Fix: the popup set the bar's hover-reveal flag through a read-only
  property, throwing a TypeError on every open and close. Over days the
  warning spam could fill the shell's log and take its IPC socket down.
  The bar's setter is used instead.

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
