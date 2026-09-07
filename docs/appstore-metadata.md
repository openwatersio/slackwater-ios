# App Store metadata — DRAFT for Bryan's review

*M4, 2026-07-30. **Rewritten 2026-08-01 for national coverage** (M5.3: 3,352 bundled
stations across the US and Canada — the previous draft described a Salish-Sea app).
Nothing here has been submitted; App Store Connect still has placeholder values.*

**What changed in the rewrite:** keywords (regional → national + one regional anchor),
promotional text, and the description's coverage claims. Name, subtitle, category,
privacy answers and review notes were already national and stand unchanged.

## Name & subtitle

| Field | Value | Limit |
|---|---|---|
| **Name** | `Slackwater — Tides & Currents` | 30 (29 used) |
| **Subtitle** | `Offline currents, US & Canada` | 30 (29 used) |

The subtitle covers both countries; a Salish Sea-only subtitle would understate the app’s coverage.

## Keywords (≤100 chars, name/subtitle words omitted)

```
chart,table,slack,ebb,flood,marine,kayak,paddle,fishing,sailing,noaa,chs,harbor,harbour,salish sea
```

(98 characters.)

**Why this set, since it's a real strategy change.** The old list spent 40 of its 100
characters on three Salish place names — correct when the app covered one region, wrong
now that most of the coverage would be undiscoverable.

- **`chart` / `table`, not "tide chart" / "tide table".** Apple indexes the app name, so
  "tides" and "currents" are already covered; the algorithm combines fields, so the bare
  nouns pair with them for free. Repeating them would waste 10 characters.
- **Activity terms carry nationally** — kayak, paddle, fishing, sailing, marine are how
  non-boaters find a tide app in any state.
- **`noaa` / `chs`** — people search the data source by name, and it's a credibility
  signal in the listing.
- **`harbor` *and* `harbour`** — Apple doesn't stem across spellings, and half the
  coverage is Canadian.
- **One regional anchor kept: `salish sea`.** It's cheap to rank for (almost nobody
  targets it), it's where the app is genuinely strongest (the densest cluster of
  validated Canadian current gates — the national ones are single gates a coast
  apart), and it's the home audience. Dropping it to chase "tide chart" nationally
  would trade a term we can win for one Garmin owns.

Deliberately dropped: `gulf islands`, `juan de fuca`, `puget sound`, `knot`, `boating`
(low-value; `boating` is also implied by the category).

## Category

**Primary: Weather. Secondary: Navigation.** Recommendation with the tradeoff:
Weather is where every tide app the market research tore down actually lives
(Tide Guide, Tides Near Me — so it's where tide-app browsers and chart rankings
are), while Navigation carries an implication the app explicitly disclaims on
every screen ("not for navigation"). Navigation as secondary keeps the
discovery surface without making the primary shelf contradict the disclaimer.

## Promotional text (170 chars max, editable without review)

> All tide and current predictions, offline on your phone. Works on the water, on the
> beach, in the anchorage — no bars and nothing to load. Free, no account.

(156 characters.)

Rewritten to the same problem-first angle as the description below — it sits directly
above it on the product page, so leading with "slack and max-current timing for 3,000+
stations" made the two read as a spec sheet twice over. The station count moved into the
description's provenance block, where it reassures rather than gatekeeps.

## Description

**Angle: problem first.** The App Store truncates the description after roughly
three lines before "…more", so those lines are all most people ever read. They now
carry the problem and the solution, not the spec. Everything that establishes
*why the numbers are trustworthy* — NOAA, CHS, validation, counts — moved to a
short block near the end, where it reassures the people who scroll rather than
gatekeeping the people who don't.

**"offline" is placed, not swapped** (2026-08-21). The obvious edit was changing the
closing "already on your phone" to "offline on your phone", matching slackwater.xyz. But
that phrase sits at character 187, past the ~3-line truncation this section is written
around — most readers would never have seen the word. Moving it into the second sentence
puts it at character 52, inside the collapsed view, without touching the problem-first hook.

Full draft:

> Every tide app works fine at home. Slackwater works offline, where you need
> it — on the water, on the beach, in the anchorage — no bars and nothing to
> load. Thousands of US and Canadian stations, already on your phone.
>
> No spinner. No "no internet connection". No waiting on a server that isn't
> coming. You open it, and the answer is there.
>
> And it does the part most tide apps skip. Heights are the easy half. The
> harder question is the current: when does the pass go slack? How hard is it
> running at max? Can you get through before it turns?
>
> WORKS WHERE THERE IS NO SIGNAL
> The predictions are computed on your phone, not fetched. Down a dead-end
> road, out at the point, in an anchorage, or with the boat's electronics
> down — you get the same answer you would have got at the dock.
>
> CURRENTS, NOT JUST TIDES
> A curve for the whole day, with slack, max flood and max ebb marked. Drag
> your thumb across it to read any moment. Every current station shows the
> tide at its reference port on the same screen.
>
> A MAP THAT WORKS OFFLINE TOO
> Every station on a map. The coastline draws with zero bars; depth contours
> appear when you're online.
>
> FREE, NO ACCOUNT, NO ADS
> The offline core is free and stays free.
>
> WHERE THE NUMBERS COME FROM
> More than 2,200 NOAA tide and current stations are built in, with nothing to
> download. Canadian stations build their own model from the Canadian
> Hydrographic Service's published predictions, then work offline for good.
> Canadian current passes run from the Salish Sea to Haida Gwaii and Cape
> Breton, each one checked against published predictions before it ships. A few
> sit in water the on-device model cannot predict accurately — those fetch when
> you have a signal, and tell you so.
>
> Predictions are not observations — conditions vary with weather and river
> flow. Not for navigation.

## Privacy (App Store Connect "App Privacy" answers)

- **Data collection: none.** No analytics, no tracking, no accounts, no
  third-party SDKs that phone home. Answer "Data Not Collected" throughout.
- **Location** is requested (When In Use, optional) to rank nearby stations;
  it is used on-device only and never transmitted. Declining leaves the app
  fully functional. Under Apple's definitions this is *not* "collection"
  (nothing leaves the device), so it does not create a privacy-label entry.
- **Network requests the app does make** (none carry identity beyond IP):
  - DFO/CHS IWLS API — Canadian station predictions fetched once per station
    for on-device fitting, under DFO's own terms.
  - `tiles.openwaters.io` — Seascape map style/tiles when the map is open and
    online.
- **Tracking (ATT): No.**

## Review notes (for the App Review box)

> All predictions are computed on-device from public harmonic data. The app is
> explicitly marked "not for navigation" in-app (every detail footer, the map,
> and Settings). Location permission is optional and used only to sort the
> station list; deny it and search/browse works identically. No account needed.

## Assets still needed before submission

- Screenshots (6.9" and 6.5" sets) — can be produced from the UI-test
  screenshot walk once copy is settled.
- Support URL: `https://github.com/openwatersio` — decided in #5 (brand-neutral;
  App Store Connect allows changing it later if a dedicated page appears under
  the publishing brand). Marketing URL: leave blank.
