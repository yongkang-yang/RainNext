# RainNext

A lightweight native macOS menu bar app that answers one question:

> What will the rain situation be over the next couple of hours?

Not a weather app. The menu bar shows a glanceable state, the popover shows the
next ~2 hours, and that is the whole product.

Design discussion: [BD-105](https://linear.app/yongkang/issue/BD-105/initial-design-discussion)

## Status

v0.1 skeleton — builds, runs, fetches live Buienradar data.

## Menu bar notation

```
☀           dry for the whole window
☂ 27m       rain starts in 27 minutes
☂ 0.8       raining now at ~0.8 mm/h
```

Rain further than 90 minutes out gets no countdown. Heavy rain swaps the
umbrella for a `cloud.heavyrain` symbol. No temperature in v1 — the Buienradar
nowcast endpoint does not carry one, and adding a second data source for it
would work against the "one question" principle.

## Architecture

```
Sources/
├── RainNextKit/        no SwiftUI — testable domain layer
│   ├── Models/
│   │   ├── RainReading       one 5-minute sample, raw value → mm/h
│   │   ├── RainEpisode       a continuous stretch of rain
│   │   ├── RainForecast      readings + episodes + RainStatus
│   │   ├── RainIntensity     thresholds in one place
│   │   ├── MenuBarState      the menu bar notation, testable
│   │   └── WeatherLocation
│   └── Services/
│       ├── BuienradarForecastParser   JSON feed → [RainReading]
│       ├── BuienradarCoverage         where the radar composite has data
│       ├── RainService       RainDataSource protocol + Buienradar impl
│       ├── PayloadLogger     keeps wet payloads for threshold calibration
│       ├── PlaceSearchService  CLGeocoder, filtered to coverage
│       ├── LocationService   CoreLocation, reduced accuracy
│       └── LocationStore     remembers the selection
└── RainNext/           SwiftUI app
    ├── RainNextApp           MenuBarExtra, .accessory activation policy
    ├── AppState              refresh cadence + selection
    └── Views/
        ├── MenuBarStatusView
        ├── PopoverView
        ├── StatusSummaryView
        ├── RainTimelineView   2-hour graph, NOW marker, hover details
        └── LocationPickerView
```

Rain is modelled as **episodes**, not as a list of samples — "rain in 18 min",
"rain for ~35 min", "stops around 19:40" are all questions about an episode.

## Thresholds

Two floors, on purpose:

| | | |
| --- | --- | --- |
| `episodeFloor` | 0.1 mm/h | below this a sample is dry |
| `announceFloor` | 0.4 mm/h | an episode peaking under this never reaches the menu bar |
| `moderate` / `heavy` | 0.5 / 2.5 mm/h | intensity labels |
| `minimumEpisodeDuration` | 10 min | one isolated wet sample is usually radar clutter |
| `episodeMergeGap` | 15 min | bridges the dry slots inside a train of showers |

`episodeFloor` decides what exists; `announceFloor` decides what interrupts you.
A countdown that expires with nothing falling outside is how people stop
trusting the number, so drizzle stays on the graph and out of the menu bar. The
floor gates *predictions* only — a rate that is falling right now is still shown.

These are estimates. `PayloadLogger` writes every wet response to
`~/Library/Application Support/RainNext/payloads` (local only, capped at 500
files) so they can eventually be measured instead — BD-108.

## Locations

Current location (CoreLocation, reduced accuracy), plus a saved list that is
searched with `CLGeocoder` — no extra dependency, no API key. The list is
seeded once with five Dutch cities so the first launch is useful even if
location permission is denied, and is fully editable after that: drag to
reorder, context menu to remove, capped at 12.

Buienradar's radar composite covers **lat 49.51–54.80, lon 0.00–10.00** and
answers 404 outside it, so "no coverage" can never masquerade as "dry". Those
bounds were measured against the live endpoint rather than documented, and are
used only to keep obviously-elsewhere search results out of the list; the feed
itself remains the authority. If CoreLocation puts you outside the box, the app
keeps the location you had instead of replacing a working forecast with a
permanent error.

## Rain alerts

Off until switched on with the bell in the popover. One notification per
shower, fired once rain is within 20 minutes, only for episodes that clear the
same `announceFloor` the menu bar countdown uses — the app never interrupts you
about rain it would not even display. Never while it is already raining.

A ledger records the end of the announced episode, not its start, so a forecast
that drifts by a few minutes between refreshes does not produce a second
notification about the same shower. It survives relaunch, and resets when you
switch to a different place.

Quiet hours are the system's job: the notification is `.active`, not
`.timeSensitive`, so Focus and Do Not Disturb hold it back.

Rain cannot be summoned on demand, so the delivery path has its own hook:

```sh
open --env RAINNEXT_TEST_ALERT=1 build/RainNext.app   # sends one sample alert
```

## Refresh

Fetch on launch, every 5 minutes after that, and again when the popover opens
(if the data is more than 60s old). A failed refresh keeps the last valid
forecast on screen.

## Icon

`Resources/AppIcon.png` is the master art; `Scripts/make-icon.py` turns it into
`Resources/AppIcon.icns`, which `bundle.sh` regenerates only when the master is
newer.

The script rebuilds the art **full-bleed** rather than passing it through. From
macOS 26 on, the system draws every app icon inside a container shape of its
own, so art that bakes in its own rounded square renders as a squircle nested
in a squircle, on a grey plate where the transparent margins were. The script
lifts the glyph off its background, reproduces the background gradient across
the whole canvas at 1024, and leaves the corners to the system — which is how
the icon ends up looking like the ones next to it.

The glyph is a seal-script 雨. At 16pt it is a smudge; that size only appears
in Finder list views, and the menu bar draws an SF Symbol rather than this.

## Build

Xcode 27 is required for the SDK, but the project is a SwiftPM package — open
`Package.swift` in Xcode, or use the command line:

```sh
swift build          # needs DEVELOPER_DIR pointing at Xcode.app if
swift test           # xcode-select still points at CommandLineTools
./Scripts/bundle.sh  # → build/RainNext.app

RAINNEXT_LIVE=1 swift test --filter LiveEndpointTests   # hits the real feed
```

The normal suite is offline and deterministic; the live test is opt-in.

`bundle.sh` wraps the SwiftPM binary in an `.app` with an `Info.plist`
(`LSUIElement`, location and notification usage strings), then signs it with the
first real identity it finds, falling back to ad-hoc with a warning.

**Notifications need a real signature.** macOS refuses to treat an ad-hoc
bundle with no Team Identifier as a notification client: the very first
`notificationSettings()` query returns `.denied` and no permission prompt ever
appears. A free Apple Development certificate (Xcode → Settings → Accounts) is
enough — the paid programme is only needed to hand the `.app` to other people.

Two traps found the hard way:

- A certificate can be installed and still be invisible to `security
  find-identity -v -p codesigning`, which filters out anything whose trust
  chain does not build. If the only WWDR intermediate in the keychain is the
  G1 that expired in February 2023, every modern certificate looks absent.
  Install the matching intermediate from
  <https://www.apple.com/certificateauthority/>.
- A bundle identifier that was ever denied stays denied, and an app that never
  registered does not appear in System Settings → Notifications to be switched
  back on. The identifier changed from `com.yongkang.RainNext` to
  `nl.yongkang.rainnext` for exactly this reason; preferences live under the
  identifier, so that reset the saved locations once.

An app run from `/tmp` is not accepted as a notification client either,
whatever its signature. `build/` and `~/Applications` are both fine.

Migrating to an `.xcodeproj` is the step before any distribution to others.

## Data

Precipitation nowcast from **Buienradar.nl**, via the public
`graphdata.buienradar.nl/2.0/forecast/geo/RainHistoryForecast` feed — no token,
no API key. Each entry carries a UTC timestamp and a rate in mm/h, plus
Buienradar's raw radar value, which is kept only for threshold calibration.

The feed reaches about 15 minutes back and close to three hours forward;
`ForecastWindow` trims that to 30 minutes of history and a 2-hour horizon.
Sample spacing is read from the data rather than assumed — real payloads do drop
slots. Coverage is the Benelux.

Not a fork of RainBar — own codebase, own implementation.

## License

[GPL-3.0-or-later](LICENSE). Not distributed commercially.

## Still open (BD-105)

- notification before rain starts — not built (BD-106)
- threshold calibration against real readings (BD-108)
- Buienradar attribution wording (BD-109)
- radar imagery is intentionally excluded from v1
