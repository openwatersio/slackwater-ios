# App Store metadata

The listing Slackwater submits, and the rules any edit to it is written against. Nothing here has been submitted — App Store Connect still holds placeholder values.

## Coverage, as every field below states it

Tides are worldwide. Currents are the United States and Canada. Any copy that describes the app as North American is wrong; any copy that implies currents are worldwide is also wrong, and it is the more expensive mistake.

| What ships | Count | Where it comes from |
|---|---|---|
| Bundled tide stations | 4,782 | 3,262 NOAA, 1,520 TICON across 105 countries and territories |
| Bundled current stations | 2,534 | NOAA |
| Canadian tide stations | 1,060 | CHS, fetched once per station, then offline for good |
| Canadian current passes | 22 | CHS, same fetch-once model |
| Listed but blank | 139 | Stations we cannot publish numbers for |

Refresh the counts before submitting, and any time coverage changes:

```
node -e 'const i=require("./Slackwater/Resources/station-index.json");console.log(i.tides.length,i.currents.length)'
```

Round down in copy. "More than 4,700" survives a catalog change; "4,782" needs an App Store review to correct.

## Name & subtitle

| Field | Value | Limit |
|---|---|---|
| **Name** | `Slackwater — Tides & Currents` | 30 (29 used) |
| **Subtitle** | `Offline worldwide predictions` | 30 (29 used) |

The name already indexes "tides" and "currents", so the subtitle spends all 30 characters on words the name does not have: the differentiator, the coverage, and a third indexable noun. Never name a region here — currents will outgrow one before the listing is next reviewed.

## Keywords (≤100 chars, name/subtitle words omitted)

```
chart,table,slack,ebb,flood,marine,kayak,paddle,fishing,sailing,noaa,chs,harbor,harbour,salish sea
```

(98 characters.)

The rules this set follows, for whoever edits it next:

- **Never repeat a word from the name or subtitle.** Apple indexes those fields and combines across them, so `chart` and `table` pair with "tides" and "currents" for free. `tide chart` would waste ten characters buying nothing.
- **Activity terms travel.** Kayak, paddle, fishing, sailing and marine are how a non-boater finds a tide app in any country.
- **Name the data sources.** People search `noaa` and `chs` directly, and both read as credibility in the listing.
- **Spell for both sides of the Atlantic where Apple does not stem.** `harbor` and `harbour` are separate terms, and worldwide coverage means most harbours are spelled the second way.
- **One regional anchor: `salish sea`.** Almost nobody targets it, it is the densest cluster of validated current gates, and it is the home audience. Drop it when currents ship outside North America and the characters are needed for a term that covers the new water — not before, and not to chase `tide chart`, which Garmin owns.

Deliberately out: `gulf islands`, `juan de fuca`, `puget sound`, `knot`, `boating` (low value; `boating` is implied by the category).

## Category

**Primary: Weather. Secondary: Navigation.**

Weather is where tide apps live — Tide Guide and Tides Near Me both sit there, so it is where tide-app browsers and chart rankings are. Navigation carries an implication the app disclaims on every screen ("not for navigation"), so it stays secondary: the discovery surface without a primary shelf that contradicts the disclaimer.

## Promotional text (170 chars max, editable without review)

> Tide and current predictions worldwide, offline on your phone. Works on the water, on the beach, in the anchorage — no bars and nothing to load. Free, no account.

(162 characters.)

This field sits directly above the description and is the one piece of copy that can change without a review — use it for anything time-sensitive. Keep it problem-first like the description rather than leading with a station count, or the two read as a spec sheet twice over.

## Description

**Angle: problem first.** The App Store truncates after roughly three lines before "…more", so those lines are all most people ever read. They carry the problem and the solution. Everything establishing *why the numbers are trustworthy* — sources, validation, counts — sits near the end, where it reassures the people who scroll rather than gatekeeping the people who don't.

Two rules that are easy to break by accident:

- **Placement beats phrasing inside the first 200 characters.** "Offline" earns its spot in the second sentence because that is character 52, inside the collapsed view. A better sentence past the fold is worse than a plain one above it.
- **Currents are named as North American every time coverage is claimed.** The provenance block is the only place the limit appears, so it cannot be trimmed for length.

Full text:

> Every tide app works fine at home. Slackwater works offline, where you need
> it — on the water, on the beach, in the anchorage — no bars and nothing to
> load. Thousands of stations worldwide, already on your phone.
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
> Every station on a map. The coastline you have already looked at stays on
> your phone and draws again with zero bars.
>
> FREE, NO ACCOUNT, NO ADS
> The offline core is free and stays free.
>
> WHERE THE NUMBERS COME FROM
> Tides for more than 4,700 stations across a hundred countries are built in
> with nothing to download, each one from the national authority that
> publishes it and checked against that authority's own tide datums before it
> ships. Currents cover the United States and Canada: every NOAA current
> station, plus Canadian passes from the Salish Sea to Haida Gwaii and Cape
> Breton. Canadian stations build their own model from the Canadian
> Hydrographic Service's published predictions, then work offline for good. A
> few stations are listed but blank — where we cannot publish numbers we
> trust, we say so instead of guessing.
>
> Predictions are not observations — conditions vary with weather and river
> flow. Not for navigation.

## Privacy (App Store Connect "App Privacy" answers)

- **Data collection: none.** No analytics, no tracking, no accounts, no third-party SDKs that phone home. Answer "Data Not Collected" throughout.
- **Location** is requested (When In Use, optional) to rank nearby stations. It is used on-device only and never transmitted, so under Apple's definitions it is not "collection" and creates no privacy-label entry. Declining leaves the app fully functional.
- **Tracking (ATT): No.**
- **Network requests the app makes**, none carrying identity beyond IP:
  - `api-iwls.dfo-mpo.gc.ca` — Canadian station predictions, fetched once per station for on-device fitting, under DFO's own terms.
  - `tiles.openfreemap.org` — basemap style and tiles when the map is open and online, cached on the device afterwards.
- **In-app purchases** settle through StoreKit. Apple handles the transaction; no personal data reaches us, and the answers above do not change when Premium goes on sale.

Re-answer this section whenever a new host appears in the app. `grep -rhoE "https://[a-z0-9.-]+" --include="*.swift" Slackwater/` lists every one.

## Accessibility Nutrition Labels

Claim only what the app does today. These labels appear on the product page and a wrong one is a support burden and a trust cost, not a marketing win — an omitted label costs nothing but the label itself.

Verify each answer against Apple's current published criteria before submitting; the summary below is what the code supports, not a reading of the criteria.

| Label | Answer today | Evidence |
|---|---|---|
| Dark Interface | Yes | The app is dark-only (`preferredColorScheme(.dark)` app-wide). |
| Captions, Audio Descriptions | Not applicable | No audio or video. |
| Larger Text | Not yet | Chrome scales and `SlackwaterTests/TypeScaleTests.swift` guards it, but chart labels are drawn in `Canvas` at fixed sizes, and the lead sits in fixed 160-point geometry. |
| VoiceOver | Not yet | Labels, traits and values cover cards, lists, headers and downloads. The graph canvas is not an adjustable control and the scroll view announces a bare clock time. |
| Reduced Motion | Not yet | Honoured for the sky's stars; pill settle fading still runs under the setting. |
| Sufficient Contrast | Unverified | `ColourAndFormTests` asserts contrast on the speed ramp and pin fills only, not on body text. |
| Differentiate Without Color | Unverified | Direction is a signed diverging axis with arrow glyphs, and tests forbid speaking direction in colour alone — but no test covers every state. |
| Voice Control | Unverified | Rides on the same labels as VoiceOver; never tested. |

[`scrubber.md`](scrubber.md) § 18 is the authoritative list of the gaps behind the "not yet" rows, including the pill capsules that do not yet offer a 44-by-44 target. Close those before flipping a row to yes, and re-run this table whenever they land — the labels are editable without a full review, so shipping honest labels now and upgrading them later costs nothing.

## Review notes (for the App Review box)

> All predictions are computed on-device from public harmonic data. The app is
> explicitly marked "not for navigation" in-app (every detail footer, the map,
> and Settings). Location permission is optional and used only to sort the
> station list; deny it and search/browse works identically. No account needed.

## Before submission

- [ ] Screenshots (6.9" and 6.5" sets), produced from the UI-test screenshot walk once copy is settled.
- [ ] Station counts re-derived and rounded down.
- [ ] Support URL `https://slackwater.xyz/support/`. Marketing URL `https://slackwater.xyz`.
- [ ] Premium listed as an in-app purchase if it is on sale by submission; the description's "the offline core is free and stays free" is written to stay true either way.
- [ ] Accessibility Nutrition Labels answered against Apple's current criteria, claiming only the rows that are yes.
