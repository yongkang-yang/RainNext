# RainNext design

How the menu bar item and the popover should look, and why. The numbers here
live in code as `Metrics` in `Sources/RainNext/Views/Glass.swift`; when the two
disagree, fix whichever one is wrong, and do not leave them apart.

## Principles

- **One question, answered first.** The popover opens on the answer ("Dry for
  the next 2 hours"), then the evidence (the chart), then the controls. Nothing
  sits above the headline except the place it is about.
- **Rain before sky.** The nowcast wins whenever it has something to say; the
  station observation only fills the gap it leaves. See `MenuBarState`.
- **Look like macOS 26.** Use system materials, system controls and SF Symbols.
  No custom colour theme, no custom fonts, and no chrome the system already
  draws.
- **Degrade quietly.** The package deploys to macOS 14. Every Liquid Glass call
  goes through the helpers in `Glass.swift`, which fall back to a plain fill,
  and no view checks availability itself.

## Liquid Glass

Glass is for things you press. Content never gets glass.

| Element | Treatment |
|---|---|
| Popover window | System material, corners rounded to `popoverRadius` |
| Location pill, Done, footer buttons | `glassSurface(in:interactive: true)` |
| Search field | `glassSurface(in: Capsule())`, not interactive |
| Span picker (2h / 12h / 48h) | Stock segmented `Picker`, which adopts glass on its own |
| Timeline card | `card()`: a plain `primary` fill at 4.5 %, no glass |
| Chart | A plain `primary` fill at 4 % inside the card |

The popover is already glass. Glass on glass inside it muddies both layers, so
the forecast sits on a flat fill. Neighbouring glass controls go inside one
`GlassGroup`, so they read as a single cluster instead of separate panes.

## Shape and spacing

| Token | Value | Use |
|---|---|---|
| `popoverWidth` | 360 | Popover and location picker |
| `popoverRadius` | 28 | Popover window corner |
| `popoverPadding` | 16 | Popover content inset |
| `cardRadius` | 12 | `popoverRadius − popoverPadding` |
| `cardPadding` | 12 | Timeline card inset |
| `chartRadius` | 6 | Chart background and clip |
| `iconButton` | 28 | Round footer buttons |

- Corners are **continuous** (`style: .continuous`) everywhere, never circular
  arcs.
- The card is **concentric** with the window: its radius is the window's minus
  the gap between them, so the two curves run parallel. If you change the
  padding, change the radius with it.
- Vertical rhythm: 14 between popover sections, 8 inside the timeline card.
- Pills pad 10 horizontally and 4–6 vertically. Everything round is a
  `Capsule` or a `Circle`, not a rectangle with a large radius.

The window corner is set by `PopoverWindowShape`, which rounds and masks the
layer of the `MenuBarExtra` window's frame view. SwiftUI has no API for this.
If a future macOS changes that view hierarchy, the popover falls back to the
stock corner. Check it after every major OS update.

## Type

System font only. Use sizes, not text styles: a menu bar popover has a fixed
width and should not reflow with Dynamic Type.

| Role | Size / weight |
|---|---|
| Headline | 19 semibold |
| Headline detail | 13 regular, secondary |
| Section title (picker) | 13 semibold |
| Body, list rows, location pill | 12 (pill: medium) |
| Chart summary, sky line, notices | 11, secondary (summary: medium) |
| Axis, source label, footer | 10, tertiary |

Any number that changes while you watch it (countdowns, rates, clock times,
the axis) uses `.monospacedDigit()`, so the text beside it does not jitter.

Emphasis goes in steps: `primary` → `secondary` → `tertiary`. A link sits one
step brighter than the text around it. The Buienradar attribution is `secondary`
beside a `tertiary` timestamp, because a link that cannot be seen as a link
does not meet the attribution requirement.

## Colour

Colour comes only from the system and the accent colour, so light mode, dark
mode and the user's accent all work without extra code.

| Rain intensity | Bar colour |
|---|---|
| Dry | `secondary` at 35 % |
| Light (< 0.5 mm/h) | accent at 55 % |
| Moderate (< 2.5 mm/h) | accent |
| Heavy | `purple` |

Past bars drop to 35 % opacity and future bars show at 85 %. A hovered bar goes
to 100 %.

## Timeline chart

- 96 pt tall. Height scales with the square root of the rate, and full height
  is 4 mm/h on every span, so a bar of the same height always means the same
  rate.
- Bars grow up from a 1 pt floor line. The floor is always drawn, so an
  all-dry window reads as "measured, and dry" rather than "failed to load".
- Bars have rounded tops (2 pt) and square bottoms, with 2 pt gaps between
  them.
- The NOW marker is a 1 pt line in `primary` at 55 %, and appears on the
  nowcast only. On the 48 h span, midnights get a 1 pt line at 18 %.
- The header names the feed (`radar` or `model`): "rain at 18:00" and "rain in
  20 minutes" are not equally certain.

## Menu bar item

- One SF Symbol, sometimes followed by short text: `27m` (countdown) or `0.8`
  (mm/h). Wording is defined in `MenuBarState`, not in the view.
- The symbol is a **16 pt medium** template `NSImage`. The menu bar ignores
  SwiftUI font modifiers on a label's image, so the size has to be set on the
  image itself. It stays a template image, so it follows the menu bar's colour.
- Text is 13 pt medium, monospaced digits.
- Every state has an `accessibilityLabel` in plain words ("rain in 27 minutes").

## Icons

SF Symbols only, with `.fill` variants for the selected or active state
(`bell.fill` when alerts are on, `location.fill` for the current location).
Every icon-only button has a `.help` tooltip that says what it does or what
state it is in.
