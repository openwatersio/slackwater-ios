# Slackwater station list — living product specification

Status: normative, living document

This document defines the station list, Slackwater's home surface, as a product and interaction contract. It is the source of truth for reimplementing the list on iOS, Android, and the web. Platform code may use different list, navigation, and storage APIs, but a person should see the same stations in the same order and reach the same detail from each of them.

The current iOS implementation is the reference implementation. Exact iOS values are recorded as reference tokens. Requirements use **must**, recommendations use **should**, and iOS implementation details are labelled as such. One logical unit is one iOS point, one Android dp, or one CSS pixel.

[`detail.md`](detail.md) owns everything after a station opens. [`scrubber.md`](scrubber.md) owns the detail timeline. [`alerts.md`](alerts.md) owns alerts.

## 1. Scope

The list contract covers:

1. the screen's sections, their order, and when each appears;
2. the location slot and its four permission states;
3. Favorites, Near Me, and Recents, including de-duplication and persistence;
4. the station card shared by the list, search, and map preview;
5. search;
6. the download strip and footer; and
7. navigation from a card, a deep link, or first run into a detail.

The map is a separate surface reached from the list. This document covers only the handoff between the two (§10). The first-run gate and the coach-mark tour are separate surfaces; §11 covers what they hand to the list.

## 2. Product idea

The list answers "what is the water doing near me, and at the places I care about?" without a tap. Every card carries a live reading, so the list is useful before anything opens.

Three ideas shape it:

- **Nearest first.** Location decides the order of everything that is not a favorite. Without a fix the list still ranks by distance from a stand-in anchor, so a first launch is never empty.
- **One station, one place on screen.** A station appears in at most one group, by a fixed priority. The stored lists stay intact; the de-duplication happens only when the list is drawn.
- **One place per name.** Neighbouring stations that share a name and a series collapse to one entry, so Near Me shows places rather than a cluster of gauges.

## 3. Screen structure

Sections appear top to bottom in this order:

| # | Section | Appears when |
|---|---|---|
| 1 | Station unavailable | A deep link named a station that is no longer published (§9.2) |
| 2 | Download strip | Canadian predictions are downloading or a download offer is open (§8) |
| 3 | My Location slot | Always; one of four states (§4) |
| 4 | Favorites | At least one favorite remains after de-duplication |
| 5 | Near Me | Always: a header row with the series filter, then 4 or 5 cards |
| 6 | Recents | At least one recent remains after de-duplication |
| 7 | Footer | Always: Downloads, Settings, and supporter-status rows, then the wordmark |

Favorites and Recents have no empty-state copy; their heading simply does not render. The list has no pull-to-refresh and no reordering.

Section headings are small uppercase monospaced labels in the go colour (`#88B868`). The uppercase is visual only; assistive technology must hear the heading in its written case.

A clearance spacer at the end keeps the last row above the floating action buttons (§10). Its iOS height is the action-button stack (56 + 24 + 16 units) scaled with text size, never less than 96.

### 3.1 Layout by width

At compact width (a phone, or an iPad in Slide Over) the list and the map share one navigation stack and swap in place beneath a floating button bar. The system navigation bar is hidden.

At regular width the list sits in a 320-unit sidebar beside a detail pane. The pane's root is the map or a placeholder reading "Pick a station" / "Tides and currents open here." On the first appearance only, an empty pane with the map off opens the first list item: the nearest hero card if there is a fix, else the first favorite, else the first Near Me card. That automatic opening must not be recorded in Recents.

## 4. Location slot

The slot shows exactly one of four states. It cross-fades (0.25 s ease on iOS) when the state or the fix changes.

| State | Slot content | Near Me heading and count |
|---|---|---|
| Authorized, with a fix | My Location tile and one or two hero cards | "Near Me", 4 cards |
| Authorized, no fix yet | My Location tile with a spinner and "Finding your location…", at least 96 units tall | 5 cards |
| Denied or restricted | My Location heading and attention-amber card: title "Location unavailable", action "Go to Settings" opening the app's system settings | 5 cards |
| Not determined | My Location heading and go-green card: title "Location unavailable", action "Find tides near me" raising the system prompt | 5 cards |

Without a fix the My Location slot says "Showing places near [last-opened place]", or "Showing places near Chesapeake Bay" on a first launch. This names the origin of the displayed distances. The Near Me heading reads "Near Me", except on a launch where nothing has ever been opened, when it names the fallback anchor's region, "Chesapeake Bay". Keep that proper name unchanged in every language.

The My Location tile has the eyebrow "My Location", a location arrow, and the fix as degrees to three decimals with hemisphere letters ("48.423°N, 123.371°W"), monospaced. The coordinate wraps rather than truncating. When iOS supplies reduced accuracy, "Approximate location" replaces the precise-looking coordinate. If an authorized location request fails, the slot says "Location unavailable" and names the fallback origin instead of continuing to spin.

A fix counts only while location is authorized. A cached fix is usable when it is no more than 600 seconds old and has a valid accuracy. The reference requests 100 m accuracy and refreshes the fix whenever the list appears and whenever the app returns to the foreground.

### 4.1 Hero cards

With a fix, the slot holds the nearest station of either series. If the nearest station of the other series lies within 20 km of the fix, it appears beside the first as a second hero. Heroes ignore the series filter, show their distance from the fix, and are each replaced by the person's chosen namesake (§5.3) when one exists. Hero cards have no swipe actions.

## 5. Groups

### 5.1 Ranking anchor and distance

Near Me, search, and the map's opening camera rank by distance from one anchor, chosen in this order:

1. the authorized fix;
2. the station opened most recently (the first Recent that still resolves); then
3. the first-run anchor, Annapolis on Chesapeake Bay (38.9750, −76.4550), where bundled NOAA tides and currents work on first launch.

Distance is the haversine great-circle distance with a mean Earth radius of 6371.0088 km. Equal distances keep catalog order: name alphabetically, then id. Implementations may cache the ranking per anchor; the reference rounds the anchor to 0.001° for that cache.

Without a saved height preference, tide heights use feet for the device’s US region and metres elsewhere, independently of app language. Current speed defaults to knots. Explicit choices, including iCloud-synced choices, override regional defaults across the app, watch, widgets, Siri, and alerts. Regional defaults are not saved or uploaded to iCloud.

Distances always display in nautical miles, whatever the height and speed units: one decimal below 10 nm, whole numbers from 10 nm, formatted with the locale's decimal separator ("1.2 nm", "14 nm").

### 5.2 Series filter

A row of three chips, "All", "Tides", and "Currents", sits at the right of the Near Me heading. The same filter, with the same persisted value, governs Near Me, search results, and every detail page's Nearby section. Tapping the active chip returns to All. The choice persists across launches.

The filter narrows Near Me and search. It does not hide heroes, favorites, or recents. The chips announce "Show all", "Show tides", and "Show currents" as selectable buttons with a selected state, have at least a 44-unit touch row, and wrap onto as many as three rows at large text sizes.

### 5.3 One place per name

In Near Me and search, stations with the same series and the same name collapse to a single entry: the person's chosen namesake when one exists, otherwise the nearest. A tide and a current with the same name stay separate. Namesake choices come from the detail page's "Other locations" chooser, never from the list; they persist on the device and sync through iCloud.

Favorites and Recents are not collapsed. A station the person saved or opened stays as itself.

### 5.4 Near Me

Near Me lists the collapsed, filtered ranking with heroes and favorites removed: the first 4 with a fix, or the first 5 without one. There is no distance cap. Each card shows its distance from the anchor.

### 5.5 Favorites

- **Order:** the order in which stations were starred, oldest first. With iCloud, order is by star timestamp, then id.
- **Add:** the detail header's star, or a leading swipe "Favorite" (star, sun tint `#F0C860`) on a Near Me or Recents card.
- **Remove:** a trailing swipe "Unfavorite" on a favorite card, or the detail header's star. A full swipe must not trigger it. An unstarred station moves to the front of Recents rather than disappearing.
- **Limit:** none.
- **Storage:** an ordered list on the device, shared with widgets, and one iCloud key-value entry per station whose value is the star time. After the first merge, the iCloud key set is the list, which is how an unstar on one device reaches the others: an iCloud store emptied elsewhere empties this device too. When the iCloud account changes, the device re-seeds iCloud from its own list instead of adopting the new account's.
- **Widgets** reload on every change.

Cards show no distance in Favorites.

### 5.6 Recents

- **Order:** most recently opened first. Re-opening a station moves it to the front; an id appears at most once.
- **Limit:** 6.
- **Recorded:** when any station detail appears, including a Canadian station still waiting for its download. The regular-width automatic opening (§3.1) is not recorded.
- **Remove:** a trailing swipe "Remove" (destructive; a full swipe is allowed). A leading swipe "Favorite" stars it.
- **Storage:** on the device only, deliberately not synced.

Cards show no distance in Recents.

### 5.7 De-duplication

Each station renders in one group only, by priority: My Location, then Favorites, then Near Me, then Recents. Removal happens at render time; the stored favorites and recents never change because of it.

## 6. The station card

The list, search results, and the map's preview panel draw the same card. It is one tap target that opens the station's detail.

### 6.1 Anatomy

```text
┌──────────────────────────────────────────────────┐
│ Station name                         4.2 ft      │
│ Region • 1.2 nm                      Rising ↗    │
│ [status strip, when there is one]                │
│ ~~~~~~~~~~~~ 25-hour curve with a now dot ~~~~~~ │
└──────────────────────────────────────────────────┘
```

- **Left:** the station name on one line, shrinking slightly before it truncates; below it the region, which wraps, then " • " and the distance when the group shows one.
- **Right:** the reading (§6.2), or the download status while one is active (§6.3).
- **Back:** the mini curve (§6.4), drawn behind the text from 54 units below the top and bleeding 3 units past each side.

When the width cannot hold the identity row, the distance is the first thing dropped. The card shows no station-kind glyph and announces no kind. Colour encodes the water's state, never the station type.

Reference geometry: 20 units of horizontal padding and 16 vertical; a minimum height of 96, or 168 with a curve or its loading placeholder; white fill at 5%; a 24-unit corner radius; a soft shadow (`#001432` at 24%, radius 12, 10 units down).

### 6.2 Readings

Readings describe the moment the card was built (§6.5).

| Station | Value | Below the value |
|---|---|---|
| Tide | Height: feet to one decimal or metres to two, then " ft" or " m" | "Rising" with a teal (`#2DD4BF`) up-right arrow, or "Falling" with an amber (`#FBBF24`) down-right arrow |
| Measured current | Absolute speed to one decimal, then "kn", "km/h", or "m/s" | A state word, a 16-point compass direction, and an arrow rotated to the set |
| Derived gate | None | The phase word with a forward, back, or slack glyph |
| Canadian tide preview | Downloaded height, with the ordinary tide state | Additional download status below the identity |
| Canadian station without readings | None | The download status (§6.3) |

Tide state is Rising when the next extreme is a high. With no next extreme it is Rising, except that a finite Canadian preview uses the local downloaded slope.

Current state is "Slack" in go green when the instant lies inside a measured slack window or the speed is below 0.15 kn; otherwise "Flooding" or "Ebbing" in neutral foam. The set arrow is flood blue (`#4A9FD8`) or ebb amber (`#E8A33D`). Below 0.05 kn the bearing is replaced by a neutral dot, because the direction means nothing there. Slack windows use the person's slack threshold, 0.5 kn by default.

Changing the slack threshold refreshes already-mounted measured-current cards, including map previews and online current gates. Derived gates have no measured speed window. Settings includes an illustrative current curve labeled "Example": its green window and duration expand or contract with the comfort-current value. The example is not a place prediction. A chosen comfort current syncs through iCloud like the units, to the watch as well as other phones; the 0.5 kn default is never uploaded.

A Canadian current gate with a usable early model prefixes numbers with “~” and keeps the ordinary downloading, queued, retrying, offline, or failed status alongside its reading and progress wave. Timing uncertainty is explained in detail, separate from download status. There is no separate refining state or fast-answer badge. A usable tide preview follows the same download states. Both remain unfinished in the overall queue until their full models land.

An online Canadian gate shows an ordinary current card while its downloaded window covers today; otherwise it shows the pending shell with "Not downloaded" (never fetched) or "Expired" (fetched before).

### 6.3 Download status

| State | Label | Placement |
|---|---|---|
| Downloading | "Downloading" | Replaces the reading |
| Queued | Its place: "Next", or "3rd in line" | Replaces the reading |
| Retrying | "Retrying in N min", or "Retrying" | Replaces the reading |
| Not queued | none | No strip |
| Offline | "Not downloaded" | Strip below the identity |
| Expired | "Expired" | Strip below the identity |
| Not downloaded | "Not downloaded" | Strip below the identity |
| Failed | "Failed", in attention amber | Strip below the identity |

A Canadian tide port first downloads a finite prediction preview. While its coverage includes now, its card shows a reading and the available portion of the mini curve alongside the remaining download status. A failed or interrupted full-model download must retain that usable preview. Other tide ports without readings get their previews before the queue completes existing previews, except that opening a place promotes its download. Derived gates still require the reference port’s fitted model.

While a station has no usable predictions and is downloading, queued, retrying, not queued, or not downloaded, the curve area shows a data-free skeleton (a wave and three capsules) at full card height, so the list does not jump when data arrives. An unfitted Canadian card shows its identity at 82% opacity with no reading. A derived gate takes its status from its reference port.

Each status has a spoken sentence explaining what will happen, for example "Queued — Canadian predictions download once, then work offline." and "Not downloaded — get back online to download predictions."

### 6.4 Mini curve

The curve spans 1.5 tidal swings back and 2.5 ahead of the card's moment, where one swing is 6.21 hours, about 25 hours in all. It samples every 10 minutes.

- The vertical range fits the data with 25% padding; a current's range always includes zero.
- Tide highs and lows get a dot; current peaks do not.
- Axis times hide within 20 units of either edge and value labels within 34, so nothing is clipped.
- The past fades to 45% opacity, and a now dot rides the curve.
- A derived gate draws a schematic shape with green dots at its slack times.
- Times use the station's time zone and the locale's hour format.

The curve announces as "25-hour curve" with a value listing its extremes as "value unit at time", separated by commas.

### 6.5 Liveness

A card computes its reading and curve once, when it appears. There is no ticking clock in the list. Canadian cards follow their download state live, and a refined fit or a freshly downloaded online window rebuilds its card.

## 7. Search

The Search action opens a full-screen overlay above the list, the map, and the regular-width detail pane. Each opening starts with an empty query and focuses the field. While search is open, the surface beneath it is hidden from assistive technology.

Results fill the screen. The series filter and the input float at the bottom over a fade at the end of the results. The input's placeholder is "Harbor, bay, or channel". Autocorrection is off. A clear button, "Clear search text", appears once there is text, and a 48-unit "Close search" button sits beside the field. A tap anywhere in the control area focuses the field.

### 7.1 Matching and ranking

1. Trim spaces and tabs from the query and lowercase it.
2. Match it as a plain substring against each station's lowercased name, region, and aliases. There is no word, prefix, or diacritic folding.
3. Apply the series filter during the scan, so the result cap fills with the chosen series.
4. Rank name matches first, then region, then alias; break ties by distance from the anchor (§5.1), then by id.
5. Collapse namesakes as in §5.3.
6. Return at most 60 results.

An empty query returns the nearest 60, so opening search shows nearby stations at once. A non-empty query waits 120 ms after the last keystroke; ranking runs off the main thread, and a result for a superseded query is discarded.

When exactly 60 results return, "Nearest 60 — keep typing to narrow" appears above them.

When a completed search has no results, "No matches" appears above the empty grid. The input and series filters remain available. The message is hidden while a different query is still being ranked.

### 7.2 Results

Results use the station card (§6) without a distance and without swipe actions, in an adaptive grid with a 360-unit minimum column and 12-unit spacing: one column on a phone, two on a portrait iPad, three in landscape. Tapping a result closes search and opens the station.

## 8. Download strip and footer

Canadian predictions download to the device in tiers: the stations in view, then those within 25 km, then those within 150 km. The download strip reports that work at the top of the list.

- **Working:** "Downloading" with "N of M" and a progress bar. Tapping opens the Downloads sheet.
- **Offering the next tier:** "Download N more?" with a decline button ("Not now") and an accept button ("Download N more"). Declining lasts for the session.
- **Neither:** the strip takes no space.

The footer is a rounded card with three rows: "Downloads", which opens the Downloads sheet and announces its state ("Online, all stations downloaded", "Offline, 3 still to download", and so on), "Settings", and "Support Slackwater" ("Slackwater supporter ❇" when Premium is active), each at least 48 units tall. The support row opens a dedicated sheet with Premium benefits, purchase options, and restore. Settings retains widget setup instructions but no purchase controls. Below the card are "Slackwater" and "by Open Waters".

## 9. Opening a station

### 9.1 From a card

A tap anywhere on a card opens that station's detail, replacing whatever was shown and dismissing the keyboard. A row holding two hero cards must open only the card that was tapped.

| Station | Detail |
|---|---|
| NOAA tide | Tide detail |
| NOAA current | Current detail |
| Canadian tide port | Tide detail with a downloaded preview or fitted model; the waiting page before either |
| Canadian derived gate | Derived-gate detail once its reference port is fitted; the waiting page before that |
| Canadian current gate | The online detail for online gates; the current detail once fitted; the waiting page before that |

Opening a Canadian station moves its download to the front of the queue. At regular width a tap replaces the detail pane. Links from one detail to another push onto the stack, so Back retraces them.

### 9.2 Deep links

| Link | Result |
|---|---|
| `slackwater://station/<id>` | Opens the station. The id is percent-encoded and read whole, so ids containing `/` survive. |
| `https://slackwater.xyz/tides/<slug>[/<instant>]`, `…/currents/…` | Opens the station, centred on the instant when one is given. An instant that does not parse rejects the whole link. |
| `slackwater://premium` | Opens the dedicated Support Slackwater sheet, in builds that sell it. |

An alert notification opens through the same path.

A link to a station that is no longer published resets navigation, closes search, and shows the Station unavailable section at the top of the list. A link to an id the app has never known does nothing. A link that arrives before the first-run gate is answered marks the gate seen and opens once the list first appears.

Neither the unavailable section nor the removed-station card says *why* the station is gone, and that is deliberate. The app cannot tell a decommissioned gauge from a renumbered one from a publisher's outage, and a guess printed as a reason is worse than no reason. Do not add an explanation back.

### 9.3 Stations that leave the catalog

A favorite or deep-linked station that is no longer published stays in place as a removed-station card:

- title: the station's last known name, or "Station removed";
- text: "<region> — no longer published.", or "This station is no longer published."; then "It has been withdrawn from the hydrographic service, so it has no readings to show.", with " Swipe to remove it." added for a favorite; and
- action: "Choose another station", which lists the five stations nearest the removed one under "Choose a replacement near the removed station." Choosing one replaces the favorite in its existing slot, keeping its iCloud star time.

The trailing swipe on a removed favorite is "Remove", which deletes it outright without adding it to Recents.

## 10. Map handoff

There are no tabs. Two floating 56-unit glass buttons sit at the bottom of the list, 16 units from the sides and 24 from the bottom:

| Position | Over the list | Over the map |
|---|---|---|
| Left | "Search" | "My Location" |
| Right | "Map" | "List" |

The right button swaps the list and the map in place. At regular width, opening the map clears the detail pane, and returning to the list shows the placeholder. Tapping a detail header's title returns to the map focused on that station.

The map's preview panel uses the station card (§6) without a distance; tapping it opens the detail. The map's pins, camera, and gestures are outside this document.

## 11. First run

The first-run gate offers "Find tides near me", which asks for location, and "Search for a place", which opens the list straight into search. Either answer, including a denial, closes the gate for good.

After the gate, if the coach-mark tour has not been seen and no search handoff or deep link is pending, the list's first appearance opens the nearest bundled NOAA tide station within 150 km of the anchor, or Friday Harbor (`noaa/9449880`) when none is that close. The tour draws on that detail, not on the list.

## 12. Accessibility

- Each card is one element that activates its station. Its reading must be one spoken phrase, such as "4.2 feet, rising", rather than separate number, unit, word, and arrow stops (see §15).
- Section headings are headings, heard in their written case.
- The series chips are selectable buttons with a selected state.
- Search hides the surface beneath it from assistive technology.
- Reading order follows visual order.
- At large text sizes names shrink before truncating, regions, status strips, and coordinates wrap, the distance drops first, chips wrap, the search field grows, and the action buttons stay 56 units with a clearance that scales with them.

Touch targets meet the platform minimum: 44 by 44 units on iOS and the web, 48 by 48 dp on Android.

## 13. Reference tokens

| Token | Value |
|---|---:|
| Near Me count | 4 with a fix, 5 without |
| Hero cross-series radius | 20 km |
| First-run anchor | 38.9750, −76.4550 |
| Earth radius | 6371.0088 km |
| Search result cap | 60 |
| Search debounce | 120 ms |
| Recents cap | 6 |
| Cached-fix maximum age | 600 s |
| Requested accuracy | 100 m |
| Card curve | 6.21 h swing; 1.5 back, 2.5 ahead; 10-minute samples |
| Card slack word | below 0.15 kn |
| Card neutral bearing | below 0.05 kn |
| Default slack threshold | 0.5 kn |
| Card minimum height | 96, or 168 with a curve |
| Download tiers | in view, 25 km, 150 km |
| First-run tour radius | 150 km |
| Action button | 56; 16 from the side, 24 from the bottom |
| Regular-width sidebar | 320 |
| Search grid minimum column | 360 |

## 14. Conformance scenarios

### Order and grouping

1. **Group order:** With a fix, a favorite, and a recent, the list shows My Location, Favorites, Near Me, Recents, then the footer.
2. **One home:** A station that is both a hero and a favorite appears only as a hero; a favorite that is also recent appears only in Favorites. Removing the hero station's favorite later restores nothing that was not stored.
3. **Namesakes:** Two nearby tide stations named the same appear once in Near Me; after choosing the farther one on its detail, Near Me shows that one.
4. **Filter:** Choosing Currents narrows Near Me and search to currents and leaves heroes, favorites, and recents untouched. Tapping Currents again returns to All.

### Location

5. **Denied:** My Location shows the amber card and names the last-opened place used for distances; "Go to Settings" opens the app's settings, and Near Me shows 5 cards ranked from that place.
6. **Not determined:** The slot shows the green card; "Find tides near me" raises the system prompt.
7. **Authorized, no fix:** The slot shows "Finding your location…" and Near Me shows 5 cards.
8. **First launch, no fix:** My Location says "Showing places near Chesapeake Bay"; Near Me keeps that proper-name heading in every language and ranks from Annapolis.
9. **Second hero:** A fix within 20 km of both a tide and a current station shows both as heroes; tapping one opens only that one.

### Favorites and recents

10. **Unfavorite:** Swiping Unfavorite removes the station from Favorites and puts it at the front of Recents.
11. **Recents cap:** Opening a seventh distinct station drops the oldest recent; re-opening a recent moves it to the front without duplicating it.
12. **Removed favorite:** A favorite that leaves the catalog shows the removed card; "Choose another station" offers five nearby stations and puts the choice in the same slot; Remove deletes it without adding it to Recents.

### Search

13. **Empty query:** Opening search shows the 60 nearest stations immediately with the truncation notice.
14. **Name before region:** A query matching one station's name and another's region ranks the name match first.
15. **Superseded query:** Typing quickly shows only the results for the final query.
16. **Result tap:** Tapping a result closes search and opens the station.

### Cards and links

17. **Pending Canadian card:** A queued Canadian station shows its place in line in place of the reading, a skeleton curve, and its full card height before data arrives.
18. **Current download:** A Canadian gate with an early model keeps its reading and “~” before the speed alongside the ordinary download status and progress.
19. **Removed deep link:** A link to a withdrawn station closes search and shows the Station unavailable section.
20. **Unknown deep link:** A link to an id the app has never known leaves the list as it was.

21. **No search match:** A completed search with no match shows "No matches" and keeps the series filter visible.
22. **Approximate fix:** My Location says "Approximate location" instead of precise coordinates when iOS supplies reduced accuracy.
23. **Slack threshold:** Changing comfort current changes the example window in Settings and refreshes measured-current cards already mounted in the list or map preview.

## 15. Known iOS deviations from the intended contract

These are implementation gaps, not behavior to copy to another platform:

- A list card's reading is not combined into one spoken phrase; VoiceOver reads the number, unit, word, and unlabelled arrow separately. Widgets already speak the combined phrase.
- List cards are not announced as buttons; the map preview card is.
- Section labels are not marked as headings, so heading navigation skips them.
- The first-run tour reads the device location without checking authorization, unlike the ranking anchor.
Fixing one of these should update this section and add or amend a conformance scenario.

## 16. Reference implementation map

| Concern | iOS source |
|---|---|
| Screen structure, sections, location slot, search overlay, action buttons, regular-width split | `Slackwater/StationListView.swift` |
| Favorites, Recents, group de-duplication | `Slackwater/StationLists.swift`, `Slackwater/FavoritesCloud.swift` |
| Ranking, anchor, search index, station kinds | `Slackwater/CurrentStation.swift`, `Slackwater/LocationService.swift` |
| Namesake collapse, chooser picks, series filter | `Slackwater/Theme.swift`, `Slackwater/StationChooser.swift` |
| Card shell and readings | `Slackwater/StationCardFace.swift`, `Slackwater/StationCard.swift` |
| Mini curve | `Slackwater/StationCardGraph.swift` |
| Download status and strip | `Slackwater/CardStatus.swift`, `Slackwater/DownloadStrip.swift`, `Slackwater/DownloadTier.swift` |
| Deep links | `Slackwater/DeepLink.swift` |
| Distance formatting | `Slackwater/Units.swift` |
| Pure behavior checks | `SlackwaterTests/UnitsAndGroupsTests.swift`, `SlackwaterTests/NationalScaleTests.swift`, `SlackwaterTests/WorldDefaultsTests.swift`, `SlackwaterTests/StationCardLoadingTests.swift`, `SlackwaterTests/StaleStationTests.swift`, `SlackwaterTests/FavoritesCloudTests.swift` |
| End-to-end checks | `SlackwaterUITests/ListAndFavoritesTests.swift`, `SlackwaterUITests/MapSearchAndNavigationTests.swift`, `SlackwaterUITests/DeepLinkUITests.swift` |

The watch's browse list (`SlackwaterWatch/`) uses the same group de-duplication but leaves out unfitted Canadian stations and namesake picks, and shows four Nearby rows.

## 17. Maintaining this specification

Any user-visible list change updates this file in the same change as the reference implementation. When an implementation differs intentionally, record the deviation and its reason here, decide whether the platform or the shared contract is wrong, and add a conformance scenario for the decision.
