# Slackwater for iOS

Tide **and current** predictions that keep working with **no signal**. Open it once, install it,
and it answers in an anchorage with no bars — the harmonics run on the device, not fetched from
a server.

The wedge is currents, not tides. Everyone does tide heights. Currents are the actual planning
problem, and nobody ships *offline + real current predictions + US-and-Canada + modern UX* in
one app. Offline-first isn't a feature, it's the reason the app exists — if the boat's systems
die, a phone in your pocket independently runs the same numbers.

**Salish Sea today, global by design.** Coverage starts with waters we know well enough to tell
when the numbers are wrong. The path to accurate-worldwide is open source: people who sail their
own waters fixing the data.

## The family

| Piece | What | Where |
|---|---|---|
| Engine | Pure-Swift harmonic tide/current engine, a port of [Neaps](https://github.com/openwatersio/neaps), validated against Neaps + NOAA | [`slackwater-engine`](https://github.com/sailingnaturali/slackwater-engine) |
| Web app | The free GPL reference implementation — and the honest answer to "is there an Android version" | [`slackwater-web`](https://github.com/sailingnaturali/slackwater-web) |
| **This repo** | The iOS app — same free core, nicer everything, plus the paid planning tier | here |

Station data and shared libraries live in the Open Waters / Neaps ecosystem
(`current-stations`, `chs-constituents`, `station-corrections`, `@neaps/tide-database`).

## The free / paid line

- **Free forever:** the entire offline core — heights and extremes for any date, currents, slack
  times, saved locations, local threshold alerts (deterministic, scheduled on-device, no
  server). **The free core never shrinks.** Hard rule.
- **Paid:** the slack Live Activity / Dynamic Island view (the live tile), boat-relative
  **go-windows** (tell it your boat and your slack window; it tells you the green spans to
  transit a gate), and anything needing live observed data (weather, swell, wind overlays and
  alerts on them).

## The bar

Native-first, and the ambition is a design award — or at least best in category (low bar for
marine apps). User experience first, capability of the platform second, technology last.

## Status & license

M1 (tides at web parity: station list + search, scrubbable tide detail, units) — see the
[docs index](docs/README.md) and the milestone plan in `slackwater/docs/superpowers/specs/`.
Build: `xcodegen generate`, then build the `Slackwater` scheme (`.xcodeproj` and `Info.plist`
are generated, not committed). This repo is **deliberately private and
deliberately unlicensed for now**: the engine and libraries are open and permissive, the web app
is GPL, and the app's own license waits until we've worked out a structure that actually holds
(copyleft + paid distribution + contributor terms don't sit cleanly together). Getting it right
beats getting it fast.
