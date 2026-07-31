# App Store metadata — DRAFT for Bryan's review

*M4, 2026-07-30. Nothing here has been submitted; App Store Connect still has
placeholder values. Names/keywords from the ASO block in [gtm.md](gtm.md).*

## Name & subtitle

| Field | Value | Limit |
|---|---|---|
| **Name** | `Slackwater — Tides & Currents` | 30 (29 used) |
| **Subtitle** | `Offline currents, US & Canada` | 30 (29 used) |

Subtitle alternates (gtm.md): `Salish Sea slack & tide timing`, `Tides, currents & slack alerts`.

## Keywords (≤100 chars, name/subtitle words omitted)

```
salish sea,gulf islands,juan de fuca,ebb,flood,kayak,paddle,sail,fishing,puget sound,knot,boating
```

(97 characters.)

## Category

**Primary: Weather. Secondary: Navigation.** Recommendation with the tradeoff:
Weather is where every tide app the market research tore down actually lives
(Tide Guide, Tides Near Me — so it's where tide-app browsers and chart rankings
are), while Navigation carries an implication the app explicitly disclaims on
every screen ("not for navigation"). Navigation as secondary keeps the
discovery surface without making the primary shelf contradict the disclaimer.

## Promotional text (170 chars max, editable without review)

> Slack and max-current timing for the Salish Sea — computed on your phone, so
> it still answers in an anchorage with no bars. US and Canadian stations, free.

(159 characters.)

## Description

First line (the ASO block's, verbatim):

> Slack and max-current timing you can trust — offline, US and Canadian waters, no subscription.

Full draft:

> Slack and max-current timing you can trust — offline, US and Canadian waters,
> no subscription.
>
> Everyone does tide heights. Currents are the actual planning problem: when
> does the pass go slack, how hard is it running at max, and can you be through
> before it turns. Slackwater computes real harmonic current predictions on
> your phone — no server, no signal needed — for the Salish Sea's passes,
> narrows and channels, on both sides of the border.
>
> WORKS WITH NO SIGNAL
> The harmonics run on the device. Open it once with a connection and it keeps
> answering in an anchorage, a dead zone, or with the boat's electronics down.
>
> CURRENTS, NOT JUST TIDES
> Signed velocity curves with slack, max flood and max ebb — scrub the day with
> your thumb. Current stations show the tide at their reference port on the
> same screen.
>
> US AND CANADIAN STATIONS
> NOAA harmonic stations bundled; Canadian (CHS) stations fit a harmonic model
> on your device from CHS predictions on first launch, then work offline.
>
> A MAP THAT WORKS OFFLINE
> Every station on a pin map with coastline that renders with zero bars. Depth
> contours appear when you're online.
>
> FREE, NO ACCOUNT, NO ADS
> The offline core is free and stays free.
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
- Support URL (suggest slackwater.sailingnaturali.com or the GitHub org page)
  and marketing URL — Bryan to confirm.
