# Widgets + Premium debut — design

*2026-08-21. Supersedes every earlier statement of the free/paid line — the July 12 tide-app
design (§5, §6), the Brandon collaboration draft, the July 13 current-detail backlog, the
July 29 milestones backlog, and this repo's README have all been reconciled to point here.*

## 1. Goal

Ship Slackwater's first widgets **and** its first paid feature in the same release, so the
free/paid line is visible from day one and nothing free is ever later taken away. The
monetization posture is deliberately quiet: premium funds development; buy it because you
want it, or because you want to say thanks. No nags, no trials, no countdown discounts.

## 2. The line (canonical)

**Home screen is free. Lock screen is Premium.**

- **Free forever:** the entire offline core — heights and extremes for any date, currents,
  slack times, curves, favorites, offline downloads, **and home screen widgets**. The free
  core never shrinks. Hard rule, unchanged.
- **Premium (one tier):** everything on the **lock screen** — accessory widgets now, the
  slack Live Activity / Dynamic Island tile when it ships — plus, as they ship later:
  **local threshold alerts**, boat-relative **go-windows**, and anything needing live
  observed data (weather/swell/wind overlays).

Alerts move to Premium **now, before ever shipping free**, resolving the standing doc
contradiction without shrinking anything a user ever had. (Earlier docs said free —
2026-07-12 §5, brandon-collaboration; the CHS-online spec §5b already said paid. Paid wins.)

The one-sentence customer explanation stays the CHS-online spec's: *the curve answers "what
is the water doing" — free; "can I go" and "tell me without opening the app from my pocket"
— Premium.*

## 3. The tier

- **Name:** Slackwater Premium.
- **SKUs (StoreKit 2, exactly two):** yearly auto-renewable **~$4.99–7.99/yr** and lifetime
  non-consumable **~$19.99–29.99** — the cheap no-brainer band: be the obvious yes for
  every boater rather than optimizing revenue per user (this resolves the pricing fork
  left open in brandon-collaboration §Money). Exact numbers picked when StoreKit work
  starts; the band is decided.
- **No tip jar** (already rejected in the July 12 spec): the lifetime SKU *is* the
  say-thanks gesture — supporters get something real.
- **Tier sheet copy (tone-of-voice reference, final words Bryan's):**
  > Everything you use today stays free, forever. Premium adds the lock screen — and it's
  > how Slackwater's development gets funded. Buy it because you want it, or because you
  > want to say thanks.
  Followed by a short list of what's in the tier today and what's coming to it (Live
  Activity, alerts, go-windows) — buyers today get everything the tier grows into.

## 4. Widget set (this release)

One WidgetKit extension target. All widgets compute on-device from the engine — fully
offline; deterministic predictions mean whole-day timelines precompute with zero network.

**Free — home screen:**
- **Small:** next event for a chosen station — slack (▸) or high/low (▲▼), time, station
  name. Adapts to station type: current stations show next slack / max, tide stations next
  high/low.
- **Medium:** today's curve sparkline with a now-marker, plus the next event. The curve is
  the signature visual and passes the collaboration plan's 3-second test ("a station curve
  and the next slack, answered before the app opens").
- Station configurable per-widget via AppIntent configuration, choices from Favorites
  (fallback: nearest / most recent).

**Premium — lock screen (accessory families):**
- **accessoryInline:** `Slack 14:32 ▸ Race Passage`.
- **accessoryCircular:** arrow + time to next event.
- **accessoryRectangular:** next slack + window span (the sub-threshold slack window the
  app already computes) + station.

**Locked state:** Apple shows every app's lock widgets in the gallery, purchase or not. A
free user who adds one sees a quiet rendering — wave glyph + "Premium", no data, no
exclamation marks. Tapping opens the in-app Widgets gallery page. That is the entire
pressure applied on the lock screen.

## 5. Upsell surfaces — the complete list

1. **Settings row** (permanent, quiet): "Slackwater Premium — support the app" → tier sheet.
2. **In-app Widgets gallery page:** previews every widget, free and Premium side by side,
   with add-to-home/lock instructions. Doubles as discoverability for the free widgets;
   linked from Settings and from the locked lock-widget tap-through.
3. **Later, when alerts ship:** a 🔔 button on the list view, visible only when a station
   is selected (no clutter), opening the same tier sheet for non-subscribers.

Nothing else. No launch interstitials, no badges, no periodic prompts, no locked rows
scattered through Settings.

## 6. Technical shape

- **App Group** `group.io.openwaters.slackwater` — the prerequisite migration:
  - `FavoritesStore` / `RecentsStore` move from standard `UserDefaults` to the shared
    suite (one-time migration on first launch; keys unchanged).
  - Offline station data the widget needs (bundled catalogs ship in the extension via the
    engine package; CHS fitted constituents + offline downloads move to the shared
    container so widgets can read them).
- **Widget extension** links `slackwater-engine` directly and reuses the app's existing
  computation (next event, slack windows). Timeline: precompute today + tomorrow of
  entries per station, reload `.atEnd`; no background refresh budget concerns because
  entries are known in advance.
- **StoreKit 2:** two products; entitlement resolved via `Transaction.currentEntitlements`
  in the app, cached as a flag in shared defaults for the widget process's free/premium
  check (re-verified opportunistically in-app; the widget only ever reads the cache).
- **Slack-window computation** (`slackWindow` in `TimelineStrip.swift`) is currently
  UI-layer code; hoist what the widget needs into a shared, testable unit rather than
  importing view code into the extension.
- **TDD** per house rules: the hoisted slack-window unit, the entitlement gate, the
  favorites migration, and timeline entry generation each get failing-test-first coverage.

## 7. Release scoping

- **This release:** free home widgets (small + medium), Premium accessory widgets, App
  Group migration, StoreKit 2 tier, Settings row, Widgets gallery page, locked state.
- **Next (tier grows, no new purchase):** slack Live Activity / Dynamic Island.
- **Later (tier grows):** threshold alerts (+ the 🔔 entry point), boat-relative
  go-windows, live overlays.

## 8. Launch blockers (outside this repo)

1. **Seller entity / revenue split** — the collaboration plan requires the Open Waters
   seller/revenue agreement before any paid tier ships. Spec and code can proceed; the
   App Store submission of the paid tier cannot.
2. **ASO copy** — resolved 2026-08-21: the drafted first description line now reads
   "no subscription required" (Bryan's wording), true alongside a yearly SKU since the
   lifetime purchase covers Premium without one.

## 9. Out of scope

Watch app/complications, StandBy-specific layouts, Live Activity (next release), alerts
implementation, go-windows, any Android/web widget story (web keeps the "Drops" boundary
from the web-client design).
