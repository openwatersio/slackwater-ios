# App Store metadata

The rules the App Store listing is written against. The values themselves live in [`appstore-listing.json`](appstore-listing.json), which `scripts/asc.mjs` pushes to App Store Connect ([App Store releases](appstore.md)); the field names below are its keys. `scripts/appstore.mjs` refuses any value over Apple's limit before a request goes out.

## Coverage, as every field below states it

Tides are worldwide. Currents are the United States and Canada. Any copy that describes the app as North American is wrong; any copy that implies currents are worldwide is also wrong, and it is the more expensive mistake.

| What ships               | Count | Where it comes from                                          |
| ------------------------ | ----- | ------------------------------------------------------------ |
| Bundled tide stations    | 4,782 | 3,262 NOAA, 1,520 TICON across 105 countries and territories |
| Bundled current stations | 2,534 | NOAA                                                         |
| Canadian tide stations   | 1,060 | CHS, fetched once per station, then offline for good         |
| Canadian current passes  | 22    | CHS, same fetch-once model                                   |
| Listed but blank         | 139   | Stations we cannot publish numbers for                       |

Refresh the counts before submitting, and any time coverage changes:

```
node -e '
const bySource = (arr) => arr.reduce((c, s) => (c[s.id.split("/")[0]] = (c[s.id.split("/")[0]] || 0) + 1, c), {});
const i = require("./Slackwater/Resources/station-index.json");
console.log("bundled tide stations", i.tides.length, bySource(i.tides));
console.log("bundled current stations", i.currents.length, bySource(i.currents));
console.log("Canadian tide stations", require("./Slackwater/Resources/chs-stations.json").length);
console.log("Canadian current passes", require("./Slackwater/Resources/chs-current-gates.json").length);
console.log("listed but blank", require("./Slackwater/Resources/unavailable-stations.json").length);
// country isnt in the committed data, but every TICON id embeds an ISO 3166-1 alpha-3 code
const ticonCountries = new Set(i.tides.filter((s) => s.id.startsWith("ticon/")).map((s) => s.id.match(/-([a-z]{3})-[a-z0-9_]+$/)[1]));
console.log("countries and territories", ticonCountries.size);
'
```

Round down in copy. "More than 4,700" survives a catalog change; "4,782" needs an App Store review to correct.

## Name & subtitle

`appInfoLocalization.name` and `appInfoLocalization.subtitle`, 30 characters each.

The name already indexes "tides" and "currents", so the subtitle spends all 30 characters on words the name does not have: the differentiator, the coverage, and a third indexable noun. Never name a region here — currents will outgrow one before the listing is next reviewed.

## Keywords

`versionLocalization.keywords`: comma-separated, 100 bytes, name and subtitle words omitted.

The rules this set follows, for whoever edits it next:

- **Never repeat a word from the name or subtitle.** Apple indexes those fields and combines across them, so `chart` and `table` pair with "tides" and "currents" for free. `tide chart` would waste ten characters buying nothing.
- **Activity terms travel.** Kayak, paddle, fishing, sailing and marine are how a non-boater finds a tide app in any country.
- **Name the data sources.** People search `noaa` and `chs` directly, and both read as credibility in the listing.
- **Spell for both sides of the Atlantic where Apple does not stem.** `harbor` and `harbour` are separate terms, and worldwide coverage means most harbours are spelled the second way.
- **One regional anchor: `salish sea`.** Almost nobody targets it, it is the densest cluster of validated current gates, and it is the home audience. Drop it when currents ship outside North America and the characters are needed for a term that covers the new water — not before, and not to chase `tide chart`, which Garmin owns.

Deliberately out: `gulf islands`, `juan de fuca`, `puget sound`, `knot`, `boating` (low value; `boating` is implied by the category).

## Category

**Primary: Weather. Secondary: Navigation.** (`appInfo.primaryCategory` and `appInfo.secondaryCategory`, as App Store Connect category IDs.)

Weather is where tide apps live — Tide Guide and Tides Near Me both sit there, so it is where tide-app browsers and chart rankings are. Navigation carries an implication the app disclaims on every screen ("not for navigation"), so it stays secondary: the discovery surface without a primary shelf that contradicts the disclaimer.

## Promotional text

`versionLocalization.promotionalText`, 170 characters, editable without review.

This field sits directly above the description and is the one piece of copy that can change without a review — use it for anything time-sensitive. Keep it problem-first like the description rather than leading with a station count, or the two read as a spec sheet twice over.

## Description

`versionLocalization.description`, 4,000 characters. In the JSON it is an array of lines: each paragraph is one line, an empty string separates paragraphs, and a section heading sits on the line directly above its paragraph.

**Angle: problem first.** The App Store truncates after roughly three lines before "…more", so those lines are all most people ever read. They carry the problem and the solution. Everything establishing _why the numbers are trustworthy_ — sources, validation, counts — sits near the end, where it reassures the people who scroll rather than gatekeeping the people who don't.

Two rules that are easy to break by accident:

- **Placement beats phrasing inside the first 200 characters.** "Offline" earns its spot in the second sentence because that is character 52, inside the collapsed view. A better sentence past the fold is worse than a plain one above it.
- **Currents are named as North American every time coverage is claimed.** The provenance block is the only place the limit appears, so it cannot be trimmed for length.

## What's New

This field is the version's release notes without the beta testing instructions, so the two can never disagree. `asc.mjs localization` extracts it the same way as this line:

```sh
sed -e '1,2d' -e '/^Worth testing:/,$d' docs/release-notes/1.14.0.md
```

[`release-notes/README.md`](release-notes/README.md) documents the format. An app's first version has no What's New field, so 1.14.0's introduction reaches TestFlight and the GitHub release only. Every version after it leads with what changed.

## Privacy (App Store Connect "App Privacy" answers)

- **Data collection: none.** No analytics, no tracking, no accounts, no third-party SDKs that phone home. Answer "Data Not Collected" throughout.
- **Location** is requested (When In Use, optional) to rank nearby stations. It is used on-device only and never transmitted, so under Apple's definitions it is not "collection" and creates no privacy-label entry. Declining leaves the app fully functional.
- **Tracking (ATT): No.**
- **Network requests the app makes**, none carrying identity beyond IP:
  - `api-iwls.dfo-mpo.gc.ca` — Canadian station predictions, fetched once per station for on-device fitting, under DFO's own terms.
  - `tiles.openfreemap.org` — basemap style and tiles when the map is open and online, cached on the device afterwards.
- **In-app purchases** settle through StoreKit. Apple handles the transaction; no personal data reaches us, and the answers above do not change when Premium goes on sale.

Re-answer this section whenever a new host appears in the app. `grep -rhoE "https://[a-z0-9.-]+" --include="*.swift" Slackwater/` lists every one.

- **Privacy manifests.** `Slackwater/PrivacyInfo.xcprivacy` and `SlackwaterWidgets/PrivacyInfo.xcprivacy` declare no tracking, no collected data, and the required-reason APIs each target uses: `UserDefaults` (`CA92.1`, and `1C8F.1` for the App Group) and file modification dates (`C617.1`). Both targets compile `ChsCurrentGate.swift`, which reads a file's modification date, so the two files are identical. Re-check them when a target starts using another [required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api); App Store Connect reports a gap by email (ITMS-91053), not in the upload log.

## Accessibility Nutrition Labels

`accessibility` in the listing file holds one flag per label, true only for the rows answered yes below; `asc.mjs accessibility --yes` publishes them for iPhone and iPad. Claim only what the app does today. These labels appear on the product page and a wrong one is a support burden and a trust cost, not a marketing win — an omitted label costs nothing but the label itself.

Verify each answer against Apple's current published criteria before submitting; the summary below is what the code supports, not a reading of the criteria.

| Label                        | Answer today   | Evidence                                                                                                                                                                  |
| ---------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dark Interface               | Yes            | The app is dark-only (`UIUserInterfaceStyle: Dark` in `project.yml`).                                                                                                     |
| Captions, Audio Descriptions | Not applicable | No audio or video.                                                                                                                                                        |
| Larger Text                  | Not yet        | Chrome scales and `SlackwaterTests/TypeScaleTests.swift` guards it, but chart labels are drawn in `Canvas` at fixed sizes, and the lead sits in fixed 160-point geometry. |
| VoiceOver                    | Not yet        | Labels, traits and values cover cards, lists, headers and downloads. The graph canvas is not an adjustable control and the scroll view announces a bare clock time.       |
| Reduced Motion               | Not yet        | Honoured for the sky's stars; pill settle fading still runs under the setting.                                                                                            |
| Sufficient Contrast          | Unverified     | `ColourAndFormTests` asserts contrast on the speed ramp and pin fills only, not on body text.                                                                             |
| Differentiate Without Color  | Unverified     | Direction is a signed diverging axis with arrow glyphs, and tests forbid speaking direction in colour alone — but no test covers every state.                             |
| Voice Control                | Unverified     | Rides on the same labels as VoiceOver; never tested.                                                                                                                      |

[`scrubber.md`](scrubber.md) § 18 is the authoritative list of the gaps behind the "not yet" rows, including the pill capsules that do not yet offer a 44-by-44 target. Close those before flipping a row to yes, and re-run this table whenever they land — the labels are editable without a full review, so shipping honest labels now and upgrading them later costs nothing.

## Review notes

`reviewDetail` in the listing file: the contact and the notes App Review reads. The notes say that predictions are computed on-device, that the app is marked not for navigation, that location is optional, that no account is needed, and that Canadian stations download their data once for offline use. The contact phone number stays out of the repo (`ASC_REVIEW_PHONE`, see [App Store releases](appstore.md)).

## Before submission

- [ ] Screenshots shot on the current UI. Apple takes 1–10 per device size and scales the 6.9" set down for smaller iPhones, so two sets cover a universal app: 6.9" iPhone (1320×2868) and 13" iPad (2064×2752). `SlackwaterUITests/AppStoreScreenshots.swift` shoots both from a pinned clock, location fix and favorites, so a re-run reproduces them, and `asc.mjs screenshots` uploads them:

  ```
  WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/iphone-6.9 ./scripts/screenshots.sh
  WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/ipad-13 \
    SLACKWATER_SIM='iPad Pro 13-inch (M5)' ./scripts/screenshots.sh
  ```

  Five frames, numbered in upload order: currents on slack, a mixed tide mid-rise, the scrubber parked at night, the nearby list with its three groups, and the map. None may show Premium or imply navigation use.
- [ ] Station counts re-derived and rounded down.
- [ ] Premium listed as an in-app purchase if it is on sale by submission; the description's "the offline core is free and stays free" is written to stay true either way.
- [ ] Accessibility Nutrition Labels answered against Apple's current criteria, claiming only the rows that are yes.
