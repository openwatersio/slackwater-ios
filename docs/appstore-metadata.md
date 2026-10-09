# App Store metadata

The rules the App Store listing is written against. The values themselves live in [`appstore-listing.json`](appstore-listing.json), which `scripts/asc.mjs` pushes to App Store Connect ([App Store releases](appstore.md)); the field names below are its keys. `scripts/appstore.mjs` refuses any value over Apple's limit before a request goes out.

## Coverage, as every field below states it

Tides are worldwide. Currents are the United States and Canada. Any copy that describes the app as North American is wrong; any copy that implies currents are worldwide is also wrong, and it is the more expensive mistake.

| What ships               | Count | Where it comes from                                                         |
| ------------------------ | ----- | --------------------------------------------------------------------------- |
| Bundled tide stations    | 4,793 | 3,261 NOAA, 1,499 TICON across 105 countries and territories, 33 Kartverket |
| Bundled current stations | 2,534 | NOAA, not every NOAA station (`tools/gen-noaa-currents.mjs` lists the filters) |
| Canadian tide stations   | 1,057 | CHS, fetched once per station, then offline for good                        |
| Canadian current passes  | 22    | CHS: 13 fetch once, then offline; 9 fetch a month at a time when online     |
| Listed but blank         | 136   | Stations we cannot publish numbers for                                      |

Refresh the counts before submitting, and any time coverage changes:

```
node -e '
const bySource = (arr) => arr.reduce((c, s) => (c[s.id.split("/")[0]] = (c[s.id.split("/")[0]] || 0) + 1, c), {});
const i = require("./Slackwater/Resources/station-index.json");
console.log("bundled tide stations", i.tides.length, bySource(i.tides));
console.log("bundled current stations", i.currents.length, bySource(i.currents));
console.log("Canadian tide stations", require("./Slackwater/Resources/chs-stations.json").length);
const passes = require("./Slackwater/Resources/chs-current-gates.json");
console.log("Canadian current passes", passes.length, "online only", passes.filter((g) => g.online).length);
console.log("listed but blank", require("./Slackwater/Resources/unavailable-stations.json").length);
// country isnt in the committed data, but every TICON id embeds an ISO 3166-1 alpha-3 code
const ticonCountries = new Set(i.tides.filter((s) => s.id.startsWith("ticon/")).map((s) => s.id.match(/-([a-z]{3})-[a-z0-9_]+$/)[1]));
console.log("countries and territories", ticonCountries.size);
'
```

Round down in copy. "More than 4,700" survives a catalog change; "4,793" needs an App Store review to correct.

Every feature the copy names must be in the build attached to the version. Release builds have sold Premium since `nightly-1.14.0-57`, and the watch app, alerts, station calendars, and 14 languages ship alongside it.

## Name & subtitle

`appInfoLocalization.name` and `appInfoLocalization.subtitle`, 30 characters each.

The name already indexes "tides" and "currents", so the subtitle spends its characters on words the name does not have. "Slack water times, offline" carries three:

- **"Slack water"** as a phrase, because "Slackwater" in the name does not index as two words. Other tide apps named Slackwater already sit on the store, and the phrase is what people searching for slack water type.
- **"Times"**, which pairs with "tides" for "tide times", the phrase British, Irish and Australian searchers use.
- **"Offline"**, the differentiator.

Never name a region here. Currents will outgrow one before the listing is next reviewed. Never put "worldwide" here either: beside "Currents" in the name it reads as worldwide currents.

## Keywords

`versionLocalization.keywords`: comma-separated, 100 bytes, name and subtitle words omitted.

The rules this set follows, for whoever edits it next:

- **Never repeat a word from the name or subtitle.** Apple indexes those fields and combines across them, so `chart` and `table` pair with "tides" and "currents" for free. `tide chart` would waste ten characters buying nothing.
- **Activity terms travel.** Kayak, paddle, fishing, sailing, beach and marine are how a non-boater finds a tide app in any country.
- **Add what Apple does not stem.** `tidal` is not "tide", and people search "tidal currents" and "tidal chart".
- **Name what people look for by feature.** `widget`: "tide widget" is a common search, and the home-screen widgets are free.
- **Name the data source people search.** `noaa` is searched directly and reads as credibility. `chs` is rarely searched outside Canada and lost its bytes to `widget`.
- **One spelling of harbour.** Storefronts without their own localization fall back to this listing, and most harbours worldwide are spelled the British way, so `harbour` stays and `harbor` goes.
- **One regional anchor: `salish sea`.** Almost nobody targets it, it is the densest cluster of validated current gates, and it is the home audience. Drop it when currents ship outside North America and the characters are needed for a term that covers the new water — not before, and not to chase `tide chart`, which Garmin owns.

Deliberately out: `gulf islands`, `juan de fuca`, `puget sound`, `knot`, `boating` (low value; `boating` is implied by the category).

## Category

**Primary: Weather. Secondary: Navigation.** (`appInfo.primaryCategory` and `appInfo.secondaryCategory`, as App Store Connect category IDs.)

Weather is where tide apps live: 81 of the 103 tide and current apps on the US store in October 2026, and 12 of the 15 with more than 1,000 ratings, Tide Guide and Tides Near Me among them. It is where tide-app browsers and chart rankings are. Navigation carries an implication the app disclaims wherever it shows a prediction ("not for navigation"), so it stays secondary: the discovery surface without a primary shelf that contradicts the disclaimer.

## Promotional text

`versionLocalization.promotionalText`, 170 characters, editable without review.

This field sits directly above the description and is the one piece of copy that can change without a review — use it for anything time-sensitive. It leads with the one-liner slackwater.xyz uses, "The tide and currents app that works without signal", then states coverage with its limit. Lead with a station count and the field and the description read as a spec sheet twice over.

## Description

`versionLocalization.description`, 4,000 characters. In the JSON it is an array of lines: each paragraph is one line, an empty string separates paragraphs, and a section heading sits on the line directly above its paragraph.

**Angle: outcome first.** The App Store truncates after roughly three lines before "…more", so those lines are all most people ever read. They carry the one-liner and the coverage. Everything establishing _why the numbers are trustworthy_ — sources, validation, counts — sits near the end, where it reassures the people who scroll rather than gatekeeping the people who don't.

Rules that are easy to break by accident:

- **Placement beats phrasing inside the first 200 characters.** "Works without signal" and "currents across the US and Canada" both sit in the first two sentences, inside the collapsed view. A better sentence past the fold is worse than a plain one above it.
- **Currents are named as the US and Canada every time coverage is claimed.** The opening and the provenance block both say so, and neither can be trimmed for length.
- **Provenance names every source.** Tides come from NOAA, CHS, Kartverket and TICON-4, a research catalogue rather than a national authority. Only stations that publish datums are checked against them, so the copy says "wherever it has them".
- **Premium is disclosed while it is on sale.** The paragraph under FREE, NO ACCOUNT, NO ADS names what Premium adds and that it is a yearly subscription or a lifetime purchase (App Review 2.3.2). Every prediction stays free, so the free claims hold either way.
- **The Terms of Use line stays last while a subscription is on sale.** App Review 3.1.2 requires a link to the Terms of Use in the metadata. slackwater.xyz has no terms page, so it is Apple's standard licence agreement, the same link the purchase sheet carries.

## What's New

This field is the version's release notes without the beta testing instructions, so the two can never disagree. `asc.mjs localization` extracts it the same way as this line:

```sh
sed -e '1,2d' -e '/^Worth testing:/,$d' docs/release-notes/1.14.0.md
```

[`release-notes/README.md`](release-notes/README.md) documents the format. An app's first version has no What's New field, so 1.14.0's introduction reaches TestFlight and the GitHub release only. Every version after it leads with what changed.

## Privacy (App Store Connect "App Privacy" answers)

- **Data collection: none.** No analytics, no tracking, no accounts, no third-party SDKs that phone home. Answer "Data Not Collected" throughout.
- **Location** is requested (When In Use, optional) to rank nearby stations. The coordinates stay on the device. The map packs below are chosen around the fix, so the tile host sees which map cells are requested, as with any map. Nothing reaches us, and there is no privacy-label entry. Declining leaves the app fully functional.
- **Tracking (ATT): No.**
- **Network requests the app makes**, none carrying identity beyond IP:
  - `api-iwls.dfo-mpo.gc.ca` — Canadian station predictions, from the phone and the watch, fetched once per station for on-device fitting (a month at a time for the online-only passes), under DFO's own terms.
  - `tiles.openfreemap.org` — basemap style and tiles, downloaded at launch whether or not the map is opened: the world at low zoom, the area around the location fix, and the area around each favourite or downloaded station (`ChartPacks.swift`). Cached on the device afterwards.
- **In-app purchases** settle through StoreKit. Apple handles the transaction and no personal data reaches us; the answers above hold with Premium on sale.

Re-answer this section whenever a new host appears in the app. `grep -rhoE "https://[a-z0-9.-]+" --include="*.swift" Slackwater/` lists every one.

- **Privacy manifests.** `Slackwater/`, `SlackwaterWidgets/` and `SlackwaterWatch/PrivacyInfo.xcprivacy` declare no tracking, no collected data, and the required-reason APIs each target uses: `UserDefaults` (`CA92.1`, and `1C8F.1` for the App Group) and file modification dates (`C617.1`). Every target compiles `ChsCurrentGate.swift`, which reads a file's modification date, so the files are identical. `SlackwaterWatchWidgets` compiles the same files and has no manifest yet (#668). Re-check them when a target starts using another [required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api); App Store Connect reports a gap by email (ITMS-91053), not in the upload log.

## Accessibility Nutrition Labels

App Store Connect answers these per device. Mac shows the iPhone and iPad answers and needs none of its own; Apple Watch is answered separately. `accessibility` in the listing file holds the iPhone and iPad column, one flag per label, true only where it says Yes, and `asc.mjs accessibility --yes` publishes it for both. The Apple Watch column is entered in the App Store Connect UI. A label can be published only for a device with a live version, so nothing publishes before the first version is approved; after that, changes take effect without review.

Apple's [criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels) allow a label only if every common task can be completed with the feature: for Slackwater, the first-run gate, finding a station, reading and scrubbing a detail, favouriting, Downloads, Settings, and the purchase sheet. Claim only what the app does today. A wrong label is a support burden and a trust cost, and App Review can ask for it to be corrected (guideline 2.3). An omitted label costs nothing but the label itself.

| Label                        | iPhone and iPad | Apple Watch    | Evidence |
| ---------------------------- | --------------- | -------------- | -------- |
| Dark Interface               | Yes             | Yes            | The phone is dark-only (`UIUserInterfaceStyle: Dark` in `project.yml`, `.preferredColorScheme(.dark)` on the root and sheets). Every watch surface draws on the dark canvas. |
| Captions, Audio Descriptions | Not applicable  | Not applicable | No audio or video. |
| Larger Text                  | Not yet         | Not yet        | The lead, its pad and the pills scale, and chart labels stay fixed by contract (`docs/scrubber.md` § 5). Station names, Downloads rows and the eyebrows clip, the pills stop at the first accessibility size, and the iPad sidebar is a fixed 320 points; #500. On the watch, list rows are a fixed height, the reading card shrinks its text, and the detail never scrolls. |
| VoiceOver                    | Yes             | Not yet        | The scrubber is one adjustable control with a dated spoken value and Next event, Previous event and Set an alert actions; icon buttons are named and section labels are headings, and the list and search reach every station the map shows. The audit covers three screens (#674), so the rest is a hand check on a device before publishing (#610). Known gaps: #498, #671, #673. The watch's complications and reading card are unlabelled; #672. |
| Reduced Motion               | Yes             | Yes            | Honoured for the sky's stars, every scrubber landing, the scale glide and the pill settle fade (`TimelineTests` and `ReduceMotionTests` tripwires); the watch's two animations and its stars check it too. A map pin recentres with a plain pan; #673. |
| Sufficient Contrast          | Not yet         | Not yet        | `AccessibilityAuditTests` measures rendered contrast on the list and both details; secondary text clears 4.5:1 on the dark grounds. Caption text over the sky (the header's region line, the lead's time) cannot reach 4.5:1 on the twilight-to-day band with any single ink (`ColourAndFormTests.testLeadInkClearsLargeTextContrastOnEverySky`); a design change, tracked in #499. Nothing measures the watch. |
| Differentiate Without Color  | Yes             | Yes            | Every state has a carrier besides its colour — distinct high/low glyphs, a set arrow with a compass word, slack named in words, speeds printed at maxima — and `ColourAndFormTests.testEveryStateHasANonColourCarrier` pins each one (`docs/scrubber.md` § 25). Stars, bells and checkboxes change shape and carry `.isSelected`. Watch complications read by shape on single-tint faces. Minor colour-only states (filter chips, the Downloads warning, map slack pins) are in #673. |
| Voice Control                | Yes             | Not applicable | Every control has a name: the platform audit's element-description check passes on the list and both details (`AccessibilityAuditTests`), and the hand check covers the rest (#610). Three names differ from their visible text; #673. watchOS has no Voice Control. |

Each "not yet" names the issue that closes it; [`scrubber.md`](scrubber.md) § 18 lists the scrubber's own remaining deviations. `AccessibilityAuditTests` runs on iPhone for every pull request and on iPad for pushes to `main`. Re-check this table whenever one of those issues lands, and every release: Apple asks for a re-evaluation with each update.

## Review notes

`reviewDetail` in the listing file: the contact and the notes App Review reads. The notes say that predictions are computed on-device, where the app is marked not for navigation, that location is optional, that no account is needed, and that Canadian stations download their data once for offline use. While Premium is on sale they also say what it unlocks and how to reach the purchase sheet, so the reviewer can test the purchase. The contact phone number stays out of the repo (`ASC_REVIEW_PHONE`, see [App Store releases](appstore.md)).

## In-app purchases

Two products, entered by hand in App Store Connect; `asc.mjs` does not push them. `Slackwater.storekit` mirrors them for Debug runs.

| Product          | Product ID                                     | Type                                                           | Family Sharing |
| ---------------- | ---------------------------------------------- | -------------------------------------------------------------- | -------------- |
| Premium Yearly   | `io.openwaters.slackwater.premium.yearly`      | Auto-renewable, 1 year, in the subscription group "Slackwater Premium" | Yes            |
| Premium Lifetime | `io.openwaters.slackwater.premium.lifetime.v2` | Non-consumable                                                 | No             |

### Localizations

Each display name is at most 30 characters and each description at most 45, and a change to either goes through review. The purchase sheet shows the display name beside the price in the device's language, so every app language has a row; a language without one shows the English name. The descriptions name what Premium adds in the app's own terms for each feature ("Alerts", "Favourites calendars", "Lock screen"), so the store and the sheet agree. Spanish and Dutch leave out the Watch to fit.

| App Store Connect locale | Premium Yearly        | Premium Lifetime       | Description (both products)                   |
| ------------------------ | --------------------- | ---------------------- | --------------------------------------------- |
| `en-US`                  | Premium Yearly        | Premium Lifetime       | Alerts, calendars, lock screen and Watch      |
| `da`                     | Premium årligt        | Premium livstid        | Varsler, kalendere, låseskærm og Apple Watch  |
| `de-DE`                  | Premium jährlich      | Premium auf Lebenszeit | Meldungen, Kalender, Sperrbildschirm, Watch   |
| `es-ES`                  | Premium anual         | Premium de por vida    | Alertas, calendarios y pantalla de bloqueo    |
| `fi`                     | Premium-vuositilaus   | Elinikäinen Premium    | Hälytykset, kalenterit, lukitusnäyttö, Watch  |
| `fr-CA`                  | Premium annuel        | Premium à vie          | Alertes, calendriers, écran verrouillé, Watch |
| `it`                     | Premium annuale       | Premium a vita         | Avvisi, calendari, schermata di blocco, Watch |
| `ja`                     | Premium 年間プラン    | Premium 買い切り       | アラート、カレンダー、ロック画面、Apple Watch |
| `ko`                     | Premium 연간 구독     | Premium 평생 이용권    | 알림, 캘린더, 잠금 화면, Apple Watch          |
| `no`                     | Premium årlig         | Premium livstid        | Varsler, kalendere, låst skjerm og Watch      |
| `nl-NL`                  | Premium jaarlijks     | Premium levenslang     | Waarschuwingen, kalenders en toegangsscherm   |
| `pt-BR`                  | Premium anual         | Premium vitalício      | Alertas, calendários, Tela Bloqueada e Watch  |
| `pt-PT`                  | Premium anual         | Premium vitalício      | Alertas, calendários, ecrã bloqueado e Watch  |
| `sv`                     | Premium årsabonnemang | Premium livstid        | Aviseringar, kalendrar, låsskärm och Watch    |

The subscription group needs one localization, `en-US`, with the display name "Slackwater Premium"; without any, App Store Connect holds its subscriptions at Missing Metadata. Other languages fall back to it, and a brand name needs no translation, so the group has no other localizations. Apple refuses special characters in the name. The group shows the app's own name above it on the Manage Subscriptions page.

### Review information

The same screenshot serves both products: the purchase sheet with both products, their prices and the yearly term, Restore purchase, and the Privacy Policy and Terms of Use links. Shoot it on a 6.9" iPhone, the size of the listing's own screenshots. `SLACKWATER_SIMS` must name a simulator no other device shares:

```sh
xcrun simctl create "Slackwater IAP review shot" "iPhone 18 Pro Max"
SLACKWATER_SIMS="Slackwater IAP review shot" \
  SLACKWATER_ONLY=SlackwaterUITests/SettingsLayoutTests/testSupportSheetOpensAndClosesFromTheFooter \
  ./scripts/test.sh
```

It saves `support-sheet.png` in `/tmp/slackwater-shots`. Shoot it again whenever the purchase sheet changes, and delete the simulator afterwards.

Review notes for Premium Yearly:

> Premium Yearly is a one-year auto-renewable subscription in the Slackwater Premium group. It unlocks lock screen widgets, Apple Watch complications, alerts and station calendars. Every tide and current prediction, the Watch app and the home screen widgets stay free.
>
> To buy: scroll to the bottom of the station list and tap Support Slackwater. Alerts and Calendar in Settings open the same sheet. It shows both Premium products with their prices and the yearly term, Restore purchase, and links to the Privacy Policy and Terms of Use.
>
> To see it unlocked: in Settings → Calendar, turn on a saved station, or press and hold a station's curve to set an alert. No account is needed.

Review notes for Premium Lifetime:

> Premium Lifetime is a one-time, non-consumable purchase. It unlocks the same features as Premium Yearly permanently, with no renewal: lock screen widgets, Apple Watch complications, alerts and station calendars. It is not shared through Family Sharing. Every tide and current prediction, the Watch app and the home screen widgets stay free.
>
> To buy: scroll to the bottom of the station list and tap Support Slackwater. Alerts and Calendar in Settings open the same sheet. It shows both Premium products with their prices, Restore purchase, and links to the Privacy Policy and Terms of Use.
>
> To see it unlocked: in Settings → Calendar, turn on a saved station, or press and hold a station's curve to set an alert. No account is needed.

## Before submission

- [ ] Screenshots shot on the current UI. Apple takes 1–10 per device size and scales the 6.9" set down for smaller iPhones, so two sets cover a universal app: 6.9" iPhone (1320×2868) and 13" iPad (2064×2752). `SlackwaterUITests/AppStoreScreenshots.swift` shoots both from a pinned clock, location fix and favorites, so a re-run reproduces them, and `asc.mjs screenshots` uploads them:

  ```
  WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/iphone-6.9 ./scripts/screenshots.sh
  WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/ipad-13 \
    SLACKWATER_SIM='iPad Pro 13-inch (M5)' ./scripts/screenshots.sh
  ```

  Five frames, numbered in upload order: currents on slack, a mixed tide mid-rise, the scrubber parked at night, the nearby list with its three groups, and the map. None may show Premium or imply navigation use.
- [ ] Station counts re-derived and rounded down.
- [ ] Both Premium products attached to the version while the build sells them. A first in-app purchase goes to App Review with a version, and a purchase sheet whose products App Review cannot load is rejected under 2.1. `asc.mjs submit` stops on a submission holding an in-app purchase, so that submission goes through the App Store Connect UI.
- [ ] Each product's localizations, review notes and review screenshot entered from [In-app purchases](#in-app-purchases), and the subscription group's `en-US` display name.
- [ ] After approval: the hand check in #610 done, then the Accessibility Nutrition Labels published, iPhone and iPad with `asc.mjs accessibility --yes` and Apple Watch in the UI, claiming only the cells that say Yes.
