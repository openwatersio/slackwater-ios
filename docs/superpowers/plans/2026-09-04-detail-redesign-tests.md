# Detail Redesign Test Plan

**Goal:** The test suite describes the redesigned station detail: name header, lead reading over the strip, glass commentary and Now pills, Range or Next max tile beside the Moon tile, one time format, and the four detail kinds sharing one anatomy. Every test that asserts a removed element is rewritten to assert its replacement or deleted with the code it pinned. New tests cover the behaviour the redesign introduced.

**Architecture:** Unit tests stay in `SlackwaterTests`, UI tests in `SlackwaterUITests`. Source-scan tests (the repo's idiom for pinning a rule) keep scanning, retargeted at the new symbols. Screenshots come from the UI tests' `save(app, …)` calls under `TEST_RUNNER_M1_SHOT_DIR`.

## Constraints

- `scripts/test.sh` serialises on `/tmp/slackwater-test.lock`; read the result bundle, not just the exit code (CLAUDE.md).
- A live-network test that fails under load usually passes alone; re-run singly before blaming a change.
- Source-scan tests grep bodies by marker strings. When a scan's anchor moves (`drawCurrent`, `drawTide`, `CurrentLead`), update the anchor before the assertion.

## Unit tests

- [x] **`TimelineTests.testSingleTrackGeometries`** asserts `bodyTop > sunY + 16`, which reads the day chrome as above the plot. It sits below now: assert `timeY > bodyBottom`, `dayY > timeY`, `sunY > dayY`, and `height == sunY + 18`. Add `chromeY + 30 <= padTop` so the pill row always clears the plot's pad.
- [x] **`TimelineTests.testCurrentHeadersLeadWithPlainLanguageAndRestoreNow`** scans both current views for the retired gloss line. Retarget: `CurrentLead.swift` contains `phase.word` and `compass16(`, and both `CurrentDetailView.swift` and `OnlineGateDetailView.swift` contain `CurrentScrubCard(` and `onReturn: returnToNow`.
- [x] **`TimelineTests.testTideTrackUsesCardFillAndRateColouredLine`** describes a two-colour fade; the tide fill is a stop list anchored at datum. Assert `drawTide` contains `datumStop` and `SN.graphLow.opacity(0)`, and `tideRateStops`.
- [x] **`TimelineTests` around line 74, `currentPeakToPeakRange`.** The app no longer calls it (the Next max tile replaced the range). Delete the function and the test.
- [x] **`RenderedStripTests`** (four ink-fraction tests) were calibrated against a 284pt canvas with axis columns; the canvas is 396pt with a 160pt lead pad. Re-measure with `drawnStripInk` and set new floors with a comment stating the canvas height they assume.
- [x] **`HeroChromeTests.testHeroFillsAThirdAndGrowsWithType`** builds `MapHeader`, which has no app caller. Delete `MapHeader.swift` and this test; keep `testNoMaterialImitationOfGlass`.
- [x] **`ColourAndFormTests.testCurrentTrackDoesNotSpeakDirectionInColour`** requires `drawCurrent`'s body over 40 lines; confirm the count after extraction. Add a sibling: the schedule's `.high`/`.low` pills use `SN.graphHigh`/`SN.graphLow` and the tide lead glyph does too, so chart, pills and lead agree.
- [x] **`SlackWindowTests`** `windowDotOpacities` test stays until the card plan removes the end dots.
- [x] **`RenderProbes.swift:12`** comment cites the deleted `ScrubWhenTests`; reword.

New:

- [x] **`commentaryText`**: "High in 28m" when scrub equals now; "High 3h 28m later" once `scrubbedAway`; the same string for a tide and a current stop.
- [x] **`CurrentLead.nextSignificant`** on a synthetic timeline: a window opening yields "Slack", its closing "Flood" or "Ebb" by the velocity after it, each max "Max flood"/"Max ebb", a bare slack with no window "Slack"; a scrub inside a window skips to its closing; a scrub exactly on a stop advances to the next.
- [x] **`CurrentLead.nextMax`**: the first max after the scrub, label "Next max", value with unit and tilde when provisional, caption "Flood at 2:14pm".
- [x] **Axis time thinning**: extract the gap rule into a pure `thinnedAxisTimes(_ times: [Date], x: (Date) -> CGFloat, minGap:)` and assert two times 40pt apart keep only the earlier, two 70pt apart keep both, input order does not matter.
- [x] **Time format**: `cardTime` and `chartTime` return the same string; no source file spells `"HH:mm"`.
- [x] **`TimelineScrubber` jump**: on a token change with Reduce Motion off the coordinator sets `magneting` and `magnetTarget`; with Reduce Motion on it sets the offset directly. Unit-testable through the coordinator with a zero-size scroll view only if `UIAccessibility.isReduceMotionEnabled` is injected; otherwise cover by the UI test below.

## UI tests

- [x] **"NEXT SLACK"** (`LiveFetchTests` lines 105, 119, 146, 334, 397; `MapSearchAndNavigationTests` 24, 169, 355; `OfflineCoverageTests` 62). The tile is gone. `ScreenshotTestCase.assertCurrentDetailRendered(_ app:)` waits for `detail-reading` and the Next max tile, and stands at every site with a speed to lead with. The two derived-gate sites (`LiveFetchTests` 146, `OfflineCoverageTests` 62) wait for `detail-reading` alone — a derived gate predicts no speed, so it has no Next max tile and never had one.
- [x] **`slack-window` identifier** (`MapSearchAndNavigationTests` 120, `OfflineCoverageTests` 349). Replace with the commentary pill: `commentary` exists and its label begins with "Slack" or contains "Max".
- [x] **Uppercase AM/PM regex** (`ScreenshotTestCase` 290, `DetailAndScrubTests` 266). No bare time static text exists to match: `LeadCard` combines its children, so the reading arrives as one label ("Rising, 5.2 ft, 10:45am"). `scrubClock` reads `detail-reading` and pulls `\d{1,2}:\d{2}(am|pm)` out of it.
- [x] **`DetailAndScrubTests.testTideReadoutShowsRateAndRange`** looks for "ft/hr"; the rate is a glyph colour, not text. Renamed `testTideReadoutShowsHeightAndRange`: the lead (`detail-reading`) label contains "ft" and the Range tile exists. The tile's eyebrow is one combined element labelled "Range", not the uppercased `MonoLabel` text, so the query is case-insensitive.
- [x] **`DetailAndScrubTests.testM1Walkthrough`** reads the floating readout's time text. Read the `detail-reading` label instead, before and after a drag, and assert it changed.
- [x] **`testM52ReturnToNowHasItsOwnFixedSlot`** and **`testReturnToNowFromHistory`** comments describe the retired fixed slot; reword to the strip's chrome row. Rename `testM52…` to say what it asserts: the Now pill sits left when scrubbed into the future.
- [x] **`OfflineCoverageTests` line 364** asserts `provisional-reading-badge` is absent; the badge no longer exists anywhere. Delete the assertion.
- [x] **`OfflineCoverageTests.testOnlineGateFetchedRendersDetail`**: replace its NEXT SLACK and slack-window assertions with the helper above; keep the ink check and screenshot.

New:

- [x] **Commentary tap scrubs**: on a tide detail, read the lead time, tap `commentary`, wait for the lead time to change and the commentary to reappear with a different label. Save `commentary-tapped.png`.
- [x] **Commentary phrasing**: after the tap the commentary label ends in "later"; after tapping `detail-return-now` it contains " in ". One test with the item above — `DetailAndScrubTests.testCommentaryTapScrubsToTheStopItNames` — since both read the same pill on the same launch.
- [x] **Derived gate has a way home**: extend `testM46MalibuDerivedGateSeededOffline` to drag the strip, assert `detail-return-now` is hittable, tap it, assert it disappears.
- [x] **Malibu lead** shows the phase word and no value: `detail-reading` label contains "Flooding", "Ebbing" or "Slack" and no "kn". The same test's "LARGE-TIDE CONTEXT" assertion goes with it — the magnitude note is plain caption text under the tiles now, so it asserts the note itself ("9 kn flood & ebb").
- [x] **Download waiting screen**: opening an unfetched CHS station shows `detail-header`, no map header and no strip. Folded into `OfflineCoverageTests.testM53CanadianStationOnDemand`, which already opens that screen, rather than paying a second launch.

## Run

- [ ] `./scripts/test.sh` full, both simulators. Open every saved screenshot. Re-run any single failure alone before treating it as real.

## Follow-ups before the PR

- Chart scaling with Dynamic Type: the lead value is a fixed 44pt while its eyebrow and time scale, inside a fixed 160pt lead zone. Deriving `padTop` and `chromeY` from measured lead height is the fix; spec §7.5's fixed-size rule covers chart labels, not this text.
- The commentary and Now pills are about 30pt tall, under the 44pt HIG target. Deliberate: the large control size read too heavy over the chart. Revisit if taps miss in use.
- Long commentary at accessibility sizes can overlap the Now pill; the row is a bare stack. Reserve the pill's width or drop to a second row past a size threshold.
- Commentary settle fade ignores Reduce Motion. A cross-fade is acceptable, but hiding the pill mid-scrub is content loss; consider keeping it visible and only suppressing taps.
- The Moon tile speaks its phase name twice to VoiceOver.
- Card graph alignment: `2026-09-04-card-graph-detail-look.md`.
