# Slackwater station detail — living product specification

Status: normative, living document

This document defines the station detail page as a product and interaction contract: everything a person sees after opening a station, apart from the scrubber itself. It is the source of truth for reimplementing the detail on iOS, Android, and the web.

The current iOS implementation is the reference implementation. Exact iOS values are recorded as reference tokens. Requirements use **must**, recommendations use **should**, and iOS implementation details are labelled as such. One logical unit is one iOS point, one Android dp, or one CSS pixel.

[`scrubber.md`](scrubber.md) owns the scrubber: the lead reading, commentary and Now pills, the moving strip, and the sky. [`list.md`](list.md) owns how a person reaches a detail. [`alerts.md`](alerts.md) owns alert rules. [`current-charts.md`](current-charts.md) owns current semantics. Where this document mentions those, it covers only the handoff.

## 1. Scope

This document covers:

1. which page each station kind opens, and the order of its sections;
2. the header: back, share, favorite, title, and the map handoff;
3. the summary tiles and their sheets;
4. related-station links;
5. the multi-day schedule, its day disclosure, and its row highlight;
6. the week-range bar and date picker;
7. the footer: provenance, station details, and problem reports;
8. the Nearby section;
9. waiting and unavailable pages, additional-download notices, and online honesty cards; and
10. sharing a moment.

## 2. Product idea

A detail page answers one question for one station: what is the water doing now, and when does it next change? The scrubber answers it for any instant. Everything else on the page either supports that answer (the schedule, the tiles) or says how far to trust it (the provenance and the honesty cards).

Three rules hold across every kind:

- **The scrubber is the page's clock.** The schedule highlight, the Next max and Range tiles, the share link, and the alert offer all describe the scrubber's selected instant. Tapping a schedule row or a Moon fact moves the scrubber; it never opens a second time readout.
- **Honest about origin.** Every page says where its numbers come from and that they are not for navigation. A page with no usable prediction says so instead of drawing a curve.
- **Station-local time.** All dates and clocks use the station's time zone (scrubber §4.1).

## 3. Kinds and pages

| Station | Page | Before data is ready |
|---|---|---|
| NOAA or TICON tide | Tide detail | — |
| NOAA current | Current detail | — |
| Canadian tide port | Tide detail, including a finite downloaded preview | Waiting page (§12.1) |
| Canadian fitted current gate | Current detail, with an additional-download notice (§12.2) | Waiting page |
| Canadian online current gate | Online detail | Online honesty card (§12.3) |
| Canadian derived gate | Derived-gate detail | Waiting page naming its reference port |
| Station with no predictions | Unavailable page (§13) | — |

Opening a Canadian station that needs a download moves its download to the front of the queue and clears an earlier failure. The page must replace itself with the real detail as soon as the data arrives, without the person navigating again. A refined model or a changed slack threshold rebuilds the open page while keeping the selected instant (scrubber §17, scenario 35).

Opening any page in this table except the unavailable page records the station in Recents (list §5.6).

## 4. Page composition

Detail pages scroll vertically, with the system navigation bar hidden; the header (§5) supplies its own Back. An edge swipe also goes back.

Sections, top to bottom:

| # | Section | Tide | Current | Derived gate | Online gate |
|---|---|---|---|---|---|
| 1 | Header | ✓ | ✓ | ✓ | ✓ |
| 2 | Scrubber card | ✓ | ✓ | ✓ | when a window is downloaded |
| 3 | Download notice | while a preview is showing | while an early model is showing | | |
| 4 | Summary tiles | Range, Moon | Next max, Moon | Shape only, Moon | Next max, Moon |
| 5 | Station links (§7) | Nearby current | Tide at port, or nearby tide | Tide at port | Tide at port, or nearby tide |
| 6 | Schedule card | ✓ | ✓ | ✓ | when a window is downloaded |
| 7 | Footer | ✓ | ✓ | ✓ | when downloaded; otherwise the honesty card |
| 8 | Station details | ✓ | ✓ | ✓ | ✓ |
| 9 | Nearby | ✓ | ✓ | ✓ | ✓ |

The derived gate adds its large-tide note, when it has one, beneath its tiles. The online gate adds "Large-tide context: <note>. This is not a prediction for this pass." above its footer when it has one.

An online gate with no scrubber shows the week-range bar alone, but only when some downloaded window exists; a gate that has never downloaded shows no bar.

Reference spacing: links 12 units below the scrubber card, the schedule 14 below the links, the footer 14 below the schedule, Nearby 28 below the footer, and 42 at the end. Cards are inset 16 units, filled white at 5% with a 0.5-unit stroke in go green at 16%, and rounded to 24 units.

## 5. Header

```text
 (‹)                                   (⇪) (☆)
                  Station name
             Region • 1.2 nm
```

**Chrome row.** Three 44-unit circular glass buttons: Back on the left; Share and the favorite star on the right, Share inboard of the star. They stay 44 units at every text size.

- **Back** ("Back") returns to the previous page.
- **Share** ("Share") shares the station's public link (§15). It is absent when the station has no published link.
- **Favorite** ("Add favorite" / "Remove favorite") toggles the station in Favorites. The filled star is sun gold (`#F0C860`). It appears on every page except the unavailable page, including the waiting page and online gates.

**Title.** The station name, centred. Beneath it the region, then " • " and the distance in nautical miles when location is authorized with a fix (list §5.1 formatting). There is no station-kind label.

Tapping the title returns to the map, focused on this station at street-level zoom (12.5 on iOS). The title is a button only when the station is on the map.

## 6. Summary tiles

Two tiles sit side by side beneath the scrubber. Each has a small uppercase label, a large value, and a caption. A tile with a sheet shows a chevron beside its label and is a button; a tile without one is inert.

All tiles describe the scrubber's selected instant and update as it moves.

### 6.1 Range (tide)

- **Value:** the height difference between the extreme behind the selection and the one ahead of it, with its unit.
- **Caption:** "low to high" or "high to low".
- **Absent** when either neighbouring extreme is missing.

The tile ranks the quantity it prints. Its mark is about this **swing**, never about the height of either turn beside it: a station can have a big range on a day whose low is unremarkable, so the two are different judgements and only the first belongs here. The level question has its own section of the sheet (§6.4).

The swing is ranked against every swing in the fifteen calendar days either side of the selection, in the station's own time zone. That window needs no annual constituent — the semidiurnal and diurnal terms and the fortnightly and perigean beats between them all resolve inside a 60-day CHS fit — so the mark works at every station.

A swing in the top tenth of that window marks. The threshold is the feature: a fortnight holds about 29 highs, so the top tenth is roughly one spring series, and a mark that fires more often than that says nothing.

The caption has one line and three claimants, in this order:

1. **Seasonal.** At a seasonally dominated station (§6.4) it reads "mostly seasonal" when the seasonal ratio is 3 or more and "partly seasonal" otherwise. This outranks the rest: a reader who does not know the number is barely a tide will misread a claim that it is large.
2. **The standing.** "the fortnight's biggest" when no swing in the window goes further, otherwise "beyond normal here".
3. **The direction**, which the curve and the schedule both already show.

The glyph follows the same order: a calendar at a seasonal station, otherwise a vertical span glyph on a marked tile and none on an unmarked one. The mark is also spoken, never carried by glyph or colour alone.

The tile opens the Range sheet wherever there is something behind the number — a fortnight to rank the swing against, or water that follows a year. A station with neither keeps an inert tile.

### 6.2 Next max (current and online gate)

- **Value:** the speed of the next maximum after the selection, with "~" in front and attention amber ink while the model is provisional.
- **Caption:** "Flood at <time>" or "Ebb at <time>".
- **Absent** when no maximum follows.

At a harmonic current station the tile ranks that maximum against the fifteen calendar days either side, **within its own direction**: floods against floods and ebbs against ebbs. Most gates are not symmetric, so one combined ranking would mean the weaker direction never marked at all, however remarkable a maximum is for that direction — and a reader waiting on the flood is not helped by being told the ebbs are bigger.

A maximum in the top tenth of its direction's window marks, on the same threshold the Range tile uses. The caption keeps its time in every state, because the time is the half a reader acts on: the direction word carries the standing instead, reading "Hardest flood · <time>" where nothing in the window runs harder, "Strong flood · <time>" where it merely marks, and "Flood at <time>" otherwise. A marked tile gains the vertical span glyph and opens the Next max sheet (§6.5).

**Inert on an online gate and on a derived gate**, and that is the data rather than a choice: an online gate's detail is bounded by `Timeline.window(anchor:)` — 228 elapsed hours, about nine and a half days — where a fortnight either side needs thirty, and a derived gate has no speed at all.

### 6.3 Shape only (derived gate)

Inert. Label "Shape only", value "No speed", caption "<port> tides". It states plainly that this gate has timing and no speed.

### 6.4 Range sheet

Title "Range", with Done. It opens with the value and "The difference between this swing's high and low, <direction>."

Beneath that it answers three questions, each in its own titled section with its own figure. They are different quantities on different axes — a swing, a level, and a calendar — and one figure for all three reads as a conflation. A section is absent, never empty, when its question cannot be answered at this station.

**"Is this beyond normal?"** One bar per whole station-local day across the fortnight, each carrying that day's biggest swing, on one scale so the biggest day fills the box. The selected day is marked and the next bigger day is flagged ahead of it. Days are the unit rather than swings because rises and falls alternate large and small four times a day, which swamps the fortnightly beat that answers the question; the series is labelled "Each bar is one day's biggest swing" because the caption beneath counts swings, and at a mixed station the marked day's biggest is often not the selected one. The window runs local midnight to local midnight, so anything after its last midnight is a fragment and is dropped. The caption reads "The biggest swing of the fortnight." or "Bigger than all but N of this fortnight's M swings.", the latter tapping through to the next bigger swing.

**"Against this station's own ends"** is a section drawing rather than a chart. On one vertical scale: the station's HAT and LAT, the fortnight's highest high and lowest low, and the selected turn. Each line carries its own height; extension lines run back to a chain of differences, with an outer chain for the station's whole range. The caption's number is one of those drawn dimensions rather than a separate calculation beside them. Two levels closer on screen than the minimum separation draw as one line keeping the surviving level's name, because the shared scale is the premise and nudging either apart would break it. The whole section is absent where the station has no astronomical bounds.

**"When this station runs biggest"** is twelve whole calendar months around the selection, drawn as the envelope the monthly highest high and lowest low trace, with the widest months marked and the reader's own month ruled. Whole months because a window cut mid-month leaves a shallower half-month at each end, which draws as a season that is really an artefact of the cut. Captioned "Widest around <month>."

This section is **not** gated on the station's astronomical bounds, unlike the one above it. The rule that a yearly claim needs a non-zero `SA` or `SSA` governs claims about *level* — the gap to a datum, "the lowest low of the year" — because those depend on where the season puts mean water level. This claim is about *range*. Sa and Ssa move mean level, and within a month that offset lifts the month's highest high and its lowest low together, so it cancels out of the span; what widens the range across a year is the solar and declinational structure, which every constituent set carries. Measured across the bundle, Chignik has no bounds and varies 1.24× across the year while Portland has them and varies 1.16×.

At a seasonally dominated station the sheet then adds a "Yearly change" row: "about the same as the daily tide" when the ratio rounds to 1, or "about N× the daily tide", rounded to tens from 10 and to tenths below.

The seasonal ratio is the larger of the Sa and Ssa amplitudes over the largest tidal constituent, taken from the reference station's model for a subordinate. It exists only for stations the database flags as seasonally dominated. [The yearly tidal claims rule](../CONTRIBUTING.md#yearly-tidal-claims) applies: never infer it from the data source.

The explanation depends on the ratio:

- **3 or more:** "The water at <place> rises and falls far more across a year than it does across a day. Rivers, lakes and lagoons behave this way: the level follows the seasons — runoff, rainfall, wind — and the daily tide is a ripple on top of it." and "The highs and lows below are still computed the same way and are still correct. They are just a small movement inside a much larger seasonal one, so a whole day can sit above or below what the same day looks like six months from now."
- **Below 3:** "The water at <place> has a real tide, and a yearly cycle of about the same size. The times below are unaffected — high and low arrive when they arrive — but the heights drift across the year as the seasonal level rises and falls underneath them."

### 6.5 Next max sheet

Title "Next max", with Done. It opens with the speed and "The hardest the water runs before it turns, at <place>." Then two sections, each with its own figure.

**"Is this beyond normal?"** One bar per whole station-local day across the fortnight, each carrying that day's hardest maximum *in the selected direction*, on one scale. The selected day is marked and the next harder day flagged ahead of it. Labelled "Each bar is one day's hardest flood" or "…hardest ebb". Captioned "The hardest flood of the fortnight." or "Harder than all but N of this fortnight's M.", the latter tapping through to that maximum.

Beneath it, what the maximum costs: **"Slack runs N minutes around it, against about M here usually."** A slack window is a threshold crossing, so a harder maximum drives the water through that band faster and the window closes sooner. Both figures are measured from the loaded timeline against the reader's own slack-speed setting, which the fortnight scan does not carry. The sentence is omitted when the window is within a tenth of this station's usual, which is most maxima.

**"When this gate runs hardest"** is twelve whole calendar months, drawn as the envelope that direction's monthly maxima trace — its strongest and its weakest — with the strongest months marked and the reader's own month ruled. Captioned "Hardest around <month>."

Per direction rather than flood-to-ebb: a band drawn from the hardest ebb to the hardest flood is centred on zero, which makes a tenth's seasonal variation a twentieth of the drawn height and the year reads as a flat ribbon. One direction's own spread is the question the sheet is asking anyway.

There is deliberately **no section measured against the station's own ends**, as the Range sheet has. LAT and HAT are hydrographic datums for water *level*; no equivalent astronomical floor and ceiling is published for current *speed*, and `CurrentStationRecord` carries no datum fields at all. Nothing to measure against is not the same as a value we happen to lack.

### 6.6 Moon (every kind)

- **Glyph:** the Moon's lit shape, or the eclipse, at the selected instant.
- **Value:** an eclipse in progress ("Solar Eclipse", "Total Eclipse", "Partial Eclipse", "Penumbral Eclipse"), otherwise the phase: "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent". New and full span 1.7 days either side; the quarters span 1.4.
- **Caption:** the tide the Moon is driving: "Perigean spring tide", "Apogean spring tide", "Perigean neap tide", "Apogean neap tide", "Perigean tide", "Apogean tide", "Spring tide", or "Neap tide". Perigee and apogee count within 2 days. When none applies, "<N>% lit".
- **Absent** outside the years the astronomy library supports (1950–2101 today).

The tile opens the Moon sheet.

### 6.6 Moon sheet

Title "Moon", with Done. From top to bottom:

1. the glyph, the phase or eclipse name, "<N>% lit", a sentence about the phase, and the tide label with its explanation;
2. "Distance from Earth" in kilometres rounded to 100, with a schematic orbit marking "Closest" and "Farthest" dates;
3. moonrise and moonset times, or "—";
4. the next full and next new Moon;
5. the last visible lunar and solar eclipses, or "None visible from here."; and
6. upcoming eclipses: the next of each lunar kind within five years in date order ("Next lunar eclipse", then "Then"), and the next solar eclipse.

Every row with a time is a button. Activating it closes the sheet and moves the scrubber to that time: an eclipse goes to its first contact, and a full or new Moon goes to the night the Moon stands highest between nautical dusk and dawn. Dates show the year only when it differs from the selected instant's year.

## 7. Station links

A row of small go-green links with a branch icon, each at least 44 units tall. They sit side by side, aligned to the trailing edge, and stack vertically at accessibility text sizes. Following one pushes a page, so Back returns here.

| Link | Shown on | Copy |
|---|---|---|
| Tide at port | Current, online gate, derived gate | "Tide at <port>" |
| Nearby station | Tide (nearest current); current and online gate (nearest tide when no port is paired) | "Currents at <name> · <distance>" or "Tide at <name> · <distance>" |
| Other locations | Every page with a link row, when same-named stations of the same series exist | "Other locations (N)" |

A nearby-station link appears only within 20 km. A current's paired tide port comes from the data, not from distance. A derived gate always links its own reference port.

"Other locations" opens the namesake chooser. A choice there replaces this station in the list's Near Me and search (list §5.3).

## 8. Schedule

The schedule card lists the station's events for seven calendar days, grouped by day. It heads with the week-range bar (§9).

### 8.1 Span

The schedule starts at the anchor, the station-local midnight of the schedule week, and runs seven calendar days built with the station's calendar. A daylight-saving week still has seven days. The anchor and the window are defined in scrubber §4.1 and §4.2; the schedule must not derive its own.

The anchor is today's midnight when a page opens. It moves:

- to a picked day (§9);
- to the selected day after the scrubber has rested for 600 ms outside the current window, on tide, current, and derived-gate pages (scrubber §4.2); the online gate does not follow; and
- back to today when Now is activated.

### 8.2 Events

| Kind | Rows |
|---|---|
| Tide | Highs and lows, each with its height |
| Current | Slacks with no value; maximum flood and ebb with speed and set |
| Online gate | As current |
| Derived gate | Slacks only, with no value |

Every kind also lists lunar and solar eclipses visible from the station, timed at first contact, with the time of greatest eclipse as the value.

### 8.3 Days

Each day with at least one event gets a header. A day with no events gets none.

- **Left:** "Today", "Tomorrow", or "Yesterday" relative to the real today, otherwise the short weekday. A localized short date sits beneath the label. Beneath the date, the sunrise time in sunrise ink (`#F0D890`) and the sunset time in sunset ink (`#C8A86A`), each when the sun rises or sets that day.
- **Right:** a chevron that turns over when the day is open.

Only one day is open at a time. The anchor day starts open. Tapping an open day closes it; tapping another day opens it and closes the first.

### 8.4 Rows

```text
 6:42 AM                     6.2 ft     [ ↑ HIGH ]
```

- **Time:** station-local clock, monospaced, at least 58 units wide.
- **Value:** the height or speed, or "—" when there is none.
- **Pill:** a trailing column at least 120 units wide. Long labels wrap at larger text sizes.

| Pill | Glyph and word | Ink on fill |
|---|---|---|
| High | ↑ HIGH | Navy on high teal `#2DD4BF` |
| Low | ↓ LOW | Navy on low amber `#FBBF24` |
| Flood | Set arrow, 16-point compass, FLOOD | Navy on flood `#4A9FD8` |
| Ebb | Set arrow, 16-point compass, EBB | Navy on ebb `#E8A33D` |
| Slack | Opposed arrows, SLACK | Navy on go `#88B868` |
| Lunar eclipse | 🌘 ECLIPSE | Foam on umbra `#6B2A18` |
| Solar eclipse | Sun, SOLAR ECLIPSE | Foam on umbra `#6B2A18` |

Past rows are not dimmed. The highlight is the time cue.

### 8.5 Highlight and taps

The row nearest the scrubber's selected instant is highlighted with go green at 13%, a 2-unit go-green bar on its leading edge, and a white time. The highlight follows the scrubber continuously and is visible only when its day is open.

Tapping a row moves the scrubber to that event, using the scrubber's programmatic movement (scrubber §8).

## 9. Week-range bar and date picker

The bar heads the schedule card: a calendar icon, the range of the seven days shown, and a chevron. The range uses the locale's interval format, with the year only when the week, its last day, and today do not share one:

- "Aug 11 – 17"
- "Aug 28 – Sep 3"
- "Dec 29, 2026 – Jan 4, 2027"
- "11–17 août" (French)

Tapping the bar, or a date in the scrubber's day row (scrubber §6.5), opens the picker sheet "Choose a date": a graphical calendar laid out in the station's calendar and time zone, with Cancel and Show. The sheet sizes to its content so a six-week month is never clipped. Any date may be picked, past or future.

On Show:

1. the anchor becomes the picked day's station-local midnight; the week starts on the picked day, not on a calendar week boundary;
2. if the selected instant lies outside the new window, it moves to station-local noon of the picked day; and
3. the page loads that week. The online gate re-picks its downloaded window and fetches if none covers the week.

Picking does not change today or now. The Now pill appears because the selection has moved away (scrubber §10.2), and Now restores today's anchor.

## 10. Footer

### 10.1 Provenance

The footer starts with "Predictions — not for navigation" in small uppercase, then one line naming the source:

| Station | Line |
|---|---|
| NOAA tide | "<datum> chart datum. NOAA harmonic prediction." |
| NOAA subordinate tide | "<datum> chart datum. Based on <reference> tides and NOAA's published offsets; computed on this device." |
| TICON tide | "<datum> chart datum. TICON-4 harmonic prediction." |
| Canadian tide | "<datum> chart datum. Downloaded from CHS (IWLS), then fitted and computed on this device. These are not CHS-published predictions." |
| NOAA current | "NOAA harmonic current prediction. Flood sets N°T. Speeds use <unit>." |
| NOAA subordinate current | "NOAA subordinate station: <reference>'s slacks and maxima, corrected by published offsets. Flood sets N°T." The reference name is omitted when it is the station's own name. |
| Canadian current | "Downloaded from CHS (IWLS), then fitted and computed on this device. These are not CHS-published predictions. Flood sets N°T." |
| Derived gate | "Slackwater estimates <gate> slack times from high and low water at <port>, using a cruising rule of thumb. CHS does not publish current predictions for this pass." |
| Online gate | "CHS-published predictions downloaded <date>; available through <date>. Not computed on this device." then its validity and a Refresh button |

The online gate's validity reads "Available offline for N more days", "Expires in N days" within three days, "Expires today", or "Offline download expired". Refresh fetches from today and is disabled while fetching or offline.

### 10.2 Report a problem

A menu, "Concerns or Feedback", offers "Station is in the wrong place", "Station name or details are wrong", and "Predictions look wrong". Each composes an email to slackwater@openwaters.io with a prompt, then "— details —", the station name and id, the selected moment with its time zone, the share link, and the app version. Without a mail app the message is copied and an alert titled "Mail unavailable" says "Your report was copied. Send it to slackwater@openwaters.io."

### 10.3 Station details

A disclosure, "Station details", collapsed by default and at least 44 units tall. Its rows are label and value:

- **Tide:** Datum, with the note "Heights are measured from chart datum. A negative value predicts less water than the charted depth."; Station; Position; Time zone; Reference with its distance, for a subordinate; Prediction; and Data downloaded, for Canadian stations.
- **Current:** Station, Position, Time zone, Flood sets, Ebb sets (°T); Mean flow ("None measured" below 0.05, otherwise speed toward flood or ebb), with the note "Mean flow is the net drift remaining after the tide averages out." for non-subordinates; Reference; Prediction; Time offsets and Speed ratios for a subordinate; Fit window and Data downloaded for Canadian gates.
- **Derived gate:** Gate, Position, Time zone, Reference, Slack lags ("N min after <port> high · M min after low"), Prediction ("Estimated slack times only. No speed prediction is available for this pass."), and the note "The curve between slack times is a guide, not a speed measurement. Only its zero crossings represent predicted times."
- **Online gate:** Gate, Position, Time zone, Reference when paired, Prediction ("CHS-published predictions downloaded for offline use; not computed on this device"), On-device fit unavailable, and Downloaded ("<date>, covers to <date>").

## 11. Nearby

A "Nearby" heading with the series filter shared with the list (list §5.2), then the six nearest stations in that series, each showing "<region> · <kind>" and the distance with a 16-point compass direction from this station. Kinds read "Tide · NOAA", "Current · NOAA", "Tide · CHS", or "Current · CHS". A 220-unit map frames those stations with this station marked; tapping the map away from a pin opens the full map.

## 12. Pages and cards instead of a scrubber

### 12.1 Waiting page

A Canadian station that has not downloaded shows a short page: the header (sharing the bare station link), a status card, and "Predictions — not for navigation". It has no Nearby section and no map.

| State | Title | Text | Expectation | Action |
|---|---|---|---|---|
| Queued | "Waiting" | "This station's predictions aren't on this device yet. Downloading Canadian tidal predictions…" | "It's 3rd in line — moved up because you opened it. Estimated wait: about 2 minutes. The station downloads once and stays available offline." | "See all downloads" |
| Downloading | "Downloading…" | "Downloading Canadian tidal predictions…" | "This station stays available offline when finished." | "See all downloads" |
| Retrying | "Retrying" | "This station's predictions didn't finish downloading. Slackwater will try again." | "Slackwater retries automatically when a connection is available." | "See all downloads" |
| Offline | "Waiting for signal" | "This station's predictions need a connection before they can download." | "Connect once to download this station for permanent offline use." | "See all downloads" |
| Failed | "Download failed" | "This station's predictions couldn't be downloaded." | "Retry this station. Once downloaded, it stays available offline." | "Retry", with "See all downloads" below the card |

"Current" replaces "tidal" for a gate. A derived gate names its reference port: "<port>'s tide predictions aren't on this device yet." The first in line reads "It's first in line — moved to the front because you opened it." Wait estimates read "under a minute" below 90 seconds, then "about N minutes", "about an hour", or "about N hours".

Retries are automatic, backing off from 60 seconds and doubling to a 15-minute ceiling. "See all downloads" opens the Downloads sheet.

### 12.1.1 Downloaded tide preview

An iPhone tide port becomes useful after its first seven-elapsed-day IWLS request, covering the preceding 48 hours and about five days ahead. Heights interpolate the downloaded 15-minute predictions; highs and lows come from those samples. The detail identifies these as official CHS predictions, shows “Predictions available through <date>”, and describes additional downloading separately from the available reading. The notice is centered between the scrubber and the summary cards. It says “Additional data is required to improve accuracy” above the station’s retained download progress meter, followed by the available-through date. Queued work is represented by the meter rather than a separate “more data is queued” sentence. Offline, retry, and failure messages appear when applicable, and the downloaded prediction stays visible inside its coverage.

The preview scrubber stops at the actual downloaded bounds. Date picking and tide alerts are unavailable until the full model lands. The schedule contains only downloaded turns. A completed 60-day fit replaces the preview in the same open detail, preserves the selected instant, and enables the ordinary continuous timeline. The footer and station details then identify the on-device fitted prediction. Derived gates, paired-current tides, and watch model transfer continue to require that full model.

### 12.2 Additional current downloading

A Canadian gate with a usable 60-day model keeps its scrubber visible while the remaining data downloads toward its validated full model. The centered notice sits below the scrubber and above the summary cards, matching the tide preview notice:

- “Additional data is required to improve accuracy” above the station’s retained download progress meter;
- the station’s measured timing uncertainty: “Slack at <gate> can be off by N min.”; and
- offline, retry, or failure copy when applicable.

There is no separate “Refining” or “Fast answer” UI state. The station remains in the ordinary download queue until its full model meets the quality bar. Readings remain usable during queued, interrupted, or failed additional downloads. The notice disappears when the full model lands. Until then, numeric readings retain “~” (scrubber §9.2).

### 12.3 Online honesty card

An online gate whose downloaded windows do not cover the week shows this card in place of its footer, then the link "Try <nearest gate with a model> instead".

| State | Title | Action |
|---|---|---|
| Never downloaded | "Download for offline use" | "Download" |
| Downloading | "Downloading" | "Downloading…" |
| Waiting to retry | "Waiting to retry" | "Retry now" |
| Failed | "Download failed" | "Retry" |
| Offline | "Waiting for signal" | "Connect to download" |

The text is the gate's own note on why it has no on-device model. The expectation is "Downloads cover about a month and can be refreshed at any time." (offline: "Connect for a moment to download about a month of predictions."), followed by the stored window's validity when there is one, and "Slackwater will try again automatically." while a retry is pending.

A download covers 30 days from the anchor's week, and downloaded windows are kept for 60 days. The page fetches on its own when it opens online without coverage and when the connection returns.

## 13. Unavailable page

A station the catalog lists without predictions opens this page: the header without a favorite star, an explanation card, the Nearby section, and a provenance line. It has no footer disclaimer, report menu, schedule, or tiles. It deliberately gives no reason for the gap.

- "Predictions unavailable" with a lock icon, then "Slackwater doesn't have predictions for this tide station."
- "Can you help?" then "If you know who operates this station or how its data is licensed, let us know." with the action "Share station details", which composes an email titled "I can help with an unavailable station".
- "Station name from <source> (SEANOE). Its record is licensed under <licence>."

## 14. Alerts

On tide, current, and derived-gate pages, a press held on the scrubber parks that moment and opens the alert popup over the centerline (scrubber §6.5.1; alerts.md §7). The online gate offers no alerts.

## 15. Sharing a moment

The Share button shares `https://slackwater.xyz/<tides|currents>/<slug>`. When the scrubber has moved more than 200 seconds from now (the Now pill's threshold), the link carries that instant: `/<yyyy-MM-dd'T'HH:mm±hh:mm>` in the station's UTC offset. A shared link opens the station at that instant (list §9.2). The waiting page shares the bare link.

## 16. Accessibility

- The header's three buttons have labels "Back", "Share", and "Add favorite" / "Remove favorite", and stay 44 units at every text size.
- A day header is one button whose value is "Expanded" or "Collapsed". Its sunrise and sunset read "Sunrise <time>" and "Sunset <time>".
- A schedule row is one button whose value is its time; the pill's glyphs are hidden.
- The week-range bar reads "Showing <range>. Tap to choose a date."
- Each tile is one element; it is a button only when it has a sheet.
- Moon-sheet rows with a time are buttons.
- A status card's icon speaks the status sentence (list §6.3).
- At accessibility text sizes the station links stack, the pill column keeps room for "ECLIPSE", and every link, menu, disclosure, and card action is at least 44 units tall (48 dp on Android).
- With Reduce Motion, day disclosure and scrolling land without animation.

## 17. Reference tokens

| Token | Value |
|---|---:|
| Schedule length | 7 calendar days |
| Re-anchor rest | 600 ms |
| Share instant threshold | 200 s |
| Nearby-station link radius | 20 km |
| Nearby count | 6 |
| Nearby map height | 220 |
| Map focus zoom | 12.5 |
| Seasonal ratio, "mostly seasonal" | ≥ 3 |
| Mean flow "None measured" | < 0.05 |
| Perigee and apogee window | ± 2 days |
| New and full Moon window | ± 1.7 days |
| Quarter Moon window | ± 1.4 days |
| Eclipse look-ahead | 5 years |
| Online download | 30 days |
| Online retention | 60 days |
| Provisional fit | 60 days |
| Retry backoff | 60 s doubling, 15 min ceiling |
| "Expires in N days" | within 3 days |
| Schedule pill column | 120 |
| Header buttons | 44 |
| Card radius | 24 |

## 18. Conformance scenarios

### Composition

1. **Tide page:** shows header, scrubber, Range and Moon, the nearby-current link when a current lies within 20 km, the schedule, the footer, collapsed Station details, and Nearby, in that order.
2. **Derived gate:** shows "Shape only / No speed", links its reference port, and lists only slacks with no values.
3. **Online gate, never downloaded:** shows the honesty card, no scrubber, no week bar, and the "Try … instead" link; the star still works.
4. **Unavailable station:** has no star, no schedule, no tiles, and gives no reason.

### Schedule

5. **Opening:** the schedule starts at today, today's day is open, and the row nearest now is highlighted.
6. **One open day:** opening Wednesday closes Today; tapping Wednesday again closes it.
7. **Row tap:** tapping a row moves the scrubber to that event, and the highlight lands on that row.
8. **Re-anchor:** scrubbing past the end of the week and resting 600 ms moves the schedule to the selected day without moving the graph. The online gate's schedule stays put.
9. **DST week:** the schedule still shows seven local days, each with its station-local date.
10. **Eclipses:** lunar rows show 🌘 and "Eclipse"; solar rows show a sun and "Solar Eclipse".

### Picker and Now

11. **Pick a week:** picking a date three weeks ahead moves the bar's range to start that day, centres local noon of that day, and shows the Now pill.
12. **Return:** Now restores today's range and the current instant.
13. **Date in the strip:** tapping a date in the scrubber's day row opens the picker; tapping a sunrise moves the scrubber.

### Tiles and links

14. **Provisional current:** the Next max value has a "~" and attention amber ink until the model is final.
15. **Range follows the scrub:** moving across an extreme flips the caption between "low to high" and "high to low", at a station whose swing is not marked.
16. **Seasonal station:** a seasonally dominated station's Range tile reads "mostly seasonal" or "partly seasonal" and carries a calendar glyph, whatever its swing ranks.
17. **A marked swing:** a swing in the top tenth of its fortnight captions "beyond normal here", or "the fortnight's biggest" when nothing in the window goes further, and carries the span glyph. An ordinary swing carries neither.
18. **The sheet opens anywhere:** an ordinary station's Range tile is a button and its sheet leads with the three sections.
19. **A station with no bounds:** a CHS station's sheet keeps the fortnight and the year, and drops only the section measured against the station's own ends — absent rather than empty or zeroed.
20. **The next bigger swing:** tapping the first section's caption moves the scrubber to that swing and closes the sheet.
21. **A marked maximum:** a current maximum in the top tenth of its own direction's fortnight captions "Strong flood · <time>", or "Hardest flood · <time>" when nothing in the window runs harder, and keeps its time in both.
22. **The Next max sheet:** a harmonic current station's marked tile opens a sheet with the fortnight and the year sections, and no section measured against the station's ends.
23. **An online gate stays inert:** its Next max tile is not a button — nine and a half days is not a fortnight to rank against.
24. **Moon jump:** choosing "Next full" in the Moon sheet closes it and moves the scrubber to that night.
25. **Pushed link:** following "Tide at <port>" and pressing Back returns to the current page as it was.

### Waiting and sharing

26. **Waiting page fills in:** a queued Canadian station shows its place in line and becomes the tide detail when its download finishes, without navigation.
27. **Failed download:** shows "Retry"; retrying moves it to the front of the queue.
28. **Share at now:** sharing an untouched page shares the bare station link.
29. **Share a moment:** sharing after scrubbing a day ahead includes that instant in the station's offset, and opening the link lands on it.

## 19. Known iOS deviations from the intended contract

These are implementation gaps, not behavior to copy:

- The share link compares the selection with the device clock rather than the page's reference now. On an untouched page left open for more than 200 seconds, Share includes an instant while the Now pill stays hidden.
- Kartverket (Norwegian) tide stations show "TICON-4 harmonic prediction." in their footer; any tide station outside NOAA and CHS falls into that line.
- The online gate's honesty path has no "Predictions — not for navigation" line and no report menu.
- Day disclosure animates under Reduce Motion, and so does the first-run tour's scroll.

Fixing one of these should update this section and add or amend a conformance scenario.

## 20. Reference implementation map

| Concern | iOS source |
|---|---|
| Shared page composition, schedule card, week bar and picker, footer, station details, station links | `Slackwater/Theme.swift` |
| Header, share link | `Slackwater/DetailHeader.swift`, `Slackwater/DeepLink.swift` |
| Tide page, Range tile | `Slackwater/TideDetailView.swift`, `Slackwater/RangeDetailSheet.swift`, `Slackwater/TideStation.swift` |
| Next max tile and sheet | `Slackwater/CurrentLead.swift`, `Slackwater/CurrentDetailView.swift`, `Slackwater/MaxDetailSheet.swift`, `Slackwater/CurrentStanding.swift`, `Slackwater/CurrentStandingStore.swift` |
| Range sheet's three sections | `Slackwater/TideStanding.swift`, `Slackwater/TideStandingStore.swift`, `Slackwater/SwingFigure.swift`, `Slackwater/StandingFigure.swift`, `Slackwater/YearFigure.swift` |
| Current page, Next max | `Slackwater/CurrentDetailView.swift`, `Slackwater/CurrentLead.swift` |
| Derived gate | `Slackwater/DerivedGateDetailView.swift` |
| Online gate and its honesty card | `Slackwater/OnlineGateDetailView.swift`, `Slackwater/OnlineGates.swift` |
| Canadian routing, waiting page, amber cards | `Slackwater/ChsDetailView.swift`, `Slackwater/CardStatus.swift` |
| Unavailable page | `Slackwater/UnavailableDetailView.swift` |
| Schedule rows, day disclosure, pills | `Slackwater/TimelineStrip.swift` (`MultiDaySchedule`) |
| Summary tiles, Moon phase and tide labels, week label | `Slackwater/DetailPieces.swift` |
| Moon sheet | `Slackwater/MoonDetailSheet.swift`, `Slackwater/MoonMarks.swift` |
| Nearby | `Slackwater/NearbySection.swift` |
| Report a problem | `Slackwater/ReportProblem.swift` |
| Pure behavior checks | `SlackwaterTests/TimelineTests.swift`, `SlackwaterTests/StationLinkTests.swift`, `SlackwaterTests/ReportProblemTests.swift`, `SlackwaterTests/SeasonalWaterTests.swift`, `SlackwaterTests/EclipseTests.swift`, `SlackwaterTests/DetailLeadTests.swift` |
| End-to-end checks | `SlackwaterUITests/DetailAndScrubTests.swift`, `SlackwaterUITests/ListAndFavoritesTests.swift`, `SlackwaterUITests/MapSearchAndNavigationTests.swift`, `SlackwaterUITests/OfflineCoverageTests.swift`, `SlackwaterUITests/OfflineTransitionTests.swift` |

The watch's place page (`SlackwaterWatch/PlaceDetail.swift`) shows a reading card, the Crown-driven strip, and a sheet with the rest of the selected day's events and the favorite toggle. It has no week schedule, tiles, picker, provenance, or share.

## 21. Maintaining this specification

Any user-visible detail change updates this file in the same change as the reference implementation, and reviews every page kind in §3. When an implementation differs intentionally, record the deviation and its reason here, decide whether the platform or the shared contract is wrong, and add a conformance scenario for the decision.
