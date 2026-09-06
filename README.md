# Beat Time

Do you hate time zones? Do you have trouble coordinating with people across
the planet? Do you long for a system that could handle all of this?
Especially one that came out about 10 years before it was necessary AT ALL?
If so, my oddly specific friend, this is for you!

**I'LL CONFESS.** In 1998, Swatch looked at the entire planet's clocks and
said "no." They chopped the day into 1,000 pieces, called each one a
".beat," pinned it to midnight in a small Swiss town, and announced that
time zones were over. Suddenly, time is the same everywhere! @500 in Tokyo
is @500 in Toledo. There is nothing to convert! Ever! And no one cared.

Except me. And if you've read THIS far, probably YOU.

**BUT PONG, YOU ASK.** If @330 is the same everywhere, how do I know
whether my friend in Manila is eating lunch or asleep with her phone face
down? That question killed Internet Time in 1999, and this plugin answers
it. Right-click the beat. A grid unfolds: one thousand beats across the
top, and one strip for every person you care about. Strips glow during
business hours and go dark for the dead of night. Hover any beat and every
row converts. Know in one glance that @330 is a perfectly civilized 2:55pm
in Manila and a crime in Los Angeles.

**AND THERE'S MORE.** Add a zone from a searchable list of all 598 zones
from tzdata. Rename it. Drag it to reorder. Remove it. Mouse? Keyboard?
Yes. Pile on zones and the bar scrolls them past like a ticker at a stock
exchange that trades in beats. It follows your Omarchy theme so it never
ruins the vibe. It uses no network, asks for no privileges, runs no daemon,
and will always pay its bills ON TIME. .beat time, that is!

**THE BOTTOM LINE.** Swatch was right. They were just early. Free, MIT
licensed, built on Simon Späti's excellent
[omarchy-timezones-plugin](https://github.com/sspaeti/omarchy-timezones-plugin).
Beat math follows the canonical definition from the
[SwatchTime](https://github.com/swatchtime) organization. By TheMightyPong
([PongAlmighty](https://github.com/PongAlmighty) on GitHub). To kick the
tires:

```sh
omarchy plugin add https://github.com/PongAlmighty/beat-time-revival.git --enable
```

And look at the clock. It's @something. It always was.

![preview](preview.png)

## Install

```sh
omarchy plugin add https://github.com/PongAlmighty/beat-time-revival.git --enable
```

## Usage

- **Hover** the beat: compact view of your zones' local times. With up to
  three rows in the popup the view sits still; more than that scroll
  through slowly, ticker style.
- **Right click**: open/close the beat grid (Escape also closes)
- **Hover a beat** in the popup: converts that beat across all zones
- **Middle click**: refresh timezone offsets
- **Left click**: unused, left to the bar and compositor

In the popup:

| Mouse | Keyboard | Does |
|---|---|---|
| hover a row | `j` / `k` | move the cursor |
| drag a row's header | `Shift+J` / `Shift+K`, `Shift+Down` / `Shift+Up` | move the row down / up |
| click a row's header | `Enter` | rename its label and short label |
| ✕ at the row's right edge | `x` | remove the zone (home never is) |
| "+ Add zone" | `a` | add a zone: pick it, adjust the label, `Enter` |
| | `Esc` | cancel an edit, or close the popup |

Changes are written straight back to the widget's entry in `shell.json`.
Scripts and keybindings can do the same over IPC:

```sh
omarchy-shell io.github.pongalmighty.beattime add              # open the popup on the picker
omarchy-shell io.github.pongalmighty.beattime addZone Asia/Tokyo
omarchy-shell io.github.pongalmighty.beattime removeZone Asia/Tokyo
omarchy bar set io.github.pongalmighty.beattime zones '[...]' --json   # replace the whole list
```

A zone added without a short label gets tzdata's abbreviation ("JST") when
it has a conventional one, else the first three letters of the city.

## Configure

Works out of the box: the home row is Omarchy's system timezone, plus US
East Coast and West Coast as example zones.

Configure the widget entry in `~/.config/omarchy/shell.json` (hot-reloads on
save). Example:

```json
{
  "id": "io.github.pongalmighty.beattime",
  "centibeats": false,
  "glyphs": true,
  "beatsPerCell": 50,
  "homeZones": ["America/Chicago"],
  "zones": [
    { "label": "Home", "shortLabel": "HOME", "zone": "", "home": true },
    { "label": "Biel", "shortLabel": "BMT", "zone": "Europe/Zurich" },
    { "label": "East Coast", "shortLabel": "NY", "zone": "America/New_York" },
    { "label": "Cagayan de Oro", "shortLabel": "CDO", "zone": "Asia/Manila", "abbr": "PHT" }
  ]
}
```

- `zones` — the rows of the popup, top to bottom.
  - `zone` — IANA timezone name; `""` with `"home": true` tracks the system timezone.
  - `label` — the location name shown in the popup.
  - `shortLabel` — used in the bar's hover view.
  - `abbr` — optional override for the timezone abbreviation shown in
    parentheses.
- `homeZones` — system timezones that keep the home row's configured label.
  Outside this list (traveling), the home row is relabeled by where the
  system clock actually is. Empty (default): always label by the system
  timezone.
- `centibeats` — show `@767.42` instead of `@767` in the bar. Default `false`.
- `glyphs` — show the day/night glyph (`󰖙` / `󰖔`) next to each zone in the
  bar hover view and popup. Default `true`.
- `beatsPerCell` — grid granularity: one of `25`, `40`, `50`, `100`, `125`,
  `200`. Default `50` (20 columns of 72 minutes). `40` gives 25 columns of
  roughly one hour each.
- `tickerZones` — how many popup rows, home included, the bar's hover view
  shows at rest. With more rows than this, the view stays as wide as the
  entries that fit under that count and the full list scrolls through it.
  Default `3`.
- `tickerSpeed` — ticker scroll speed in pixels per second. Default `22`.
- `icon` — optional glyph drawn before the beat in the bar. Default none.
- `hoverExpand` — set `false` to keep the bar pill static instead of
  expanding on hover. Default `true`.

Move it in the bar:

```sh
omarchy bar move io.github.pongalmighty.beattime --section center
```

## How the beat is computed

Following [swatchtime/sample-code](https://github.com/swatchtime/sample-code):

```
bielMs = (utcMs + 3600000) mod 86400000     // Biel = UTC+1, fixed
beats  = bielMs / 86400                     // 1 beat = 86.4 s
label  = "@" + zeroPad3(floor(beats))
```

The grid's column 0 is the most recent Biel midnight (23:00 UTC). A zone's
cell at column `c` is its local time at beat `c × beatsPerCell`. Centibeats
are rounded to two decimals *before* wrapping, so the display never flashes
`@1000.00`.

The only difference from the reference snippet is millisecond rather than
whole-second precision, so a beat turns over at exactly 86.4 s rather than
on the next whole second. The reference test vectors pass either way; see
`test/model.test.js` (`node --test test/`).

## What it runs and touches

No network, no daemon, no elevated privileges, no external packages.

- Reads the clock and tzdata through `date` and `timedatectl` (`TZ=<zone>
  date +'%z %Z'` per configured zone, `timedatectl list-timezones` for the
  picker). Zone names are validated against `[A-Za-z0-9_/+-]` before they
  reach a shell.
- Writes only the widget's own entry in `~/.config/omarchy/shell.json`, and
  only through the shell's `updateEntryInline` API, when you edit zones in
  the popup or over IPC. Nothing else in your configuration is touched.
- Runs inside the Omarchy shell process like every plugin, with your user's
  permissions.

## Remove

```sh
omarchy plugin remove io.github.pongalmighty.beattime
```

## License

MIT. See [LICENSE](LICENSE), which retains the original copyright notices.
