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
│       ├── BuienradarParser  raintext → [RainReading]
│       ├── RainService       RainDataSource protocol + Buienradar impl
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
Timestamps are resolved into real `Date`s at parse time, including across
midnight, so no downstream code has to handle `HH:mm` strings.

## Refresh

Fetch on launch, every 5 minutes after that, and again when the popover opens
(if the data is more than 60s old). A failed refresh keeps the last valid
forecast on screen.

## Build

Xcode 27 is required for the SDK, but the project is a SwiftPM package — open
`Package.swift` in Xcode, or use the command line:

```sh
swift build          # needs DEVELOPER_DIR pointing at Xcode.app if
swift test           # xcode-select still points at CommandLineTools
./Scripts/bundle.sh  # → build/RainNext.app
```

`bundle.sh` wraps the SwiftPM binary in an `.app` with an `Info.plist`
(`LSUIElement`, location usage strings) and ad-hoc signs it, which is what
CoreLocation and `MenuBarExtra` need. Migrating to an `.xcodeproj` is the step
before any signed/App Store distribution.

## Data

Precipitation nowcast from **Buienradar.nl** (`gpsgadget.buienradar.nl/data/raintext`),
converted with the documented `mm/h = 10 ^ ((value - 109) / 32)`. Coverage is
the Benelux. Attribution and licensing for public distribution are still open
(BD-105).

Not a fork of RainBar — own codebase, own implementation.

## Still open (BD-105)

- notification before rain starts — not built
- custom / favourite locations beyond the presets
- rain episode thresholds, currently 0.1 / 0.5 / 2.0 mm/h
- radar imagery is intentionally excluded from v1
