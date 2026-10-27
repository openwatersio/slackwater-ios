# Range sheet: sliding bars, moon strip, solstice and equinox marks

Design for three changes to the Range sheet's figures (docs/detail.md §6.4), two of which also land on the Next max sheet (§6.5) because it shares the figures.

## Intent

Feedback on the Range sheet: the "Is this beyond normal?" bars look touchable and are not; people put a finger on a bar expecting it to light up, and expect lifting the finger to take them to that day. And the fortnight's beat in the bars is the spring/neap rhythm, which is the moon's doing — NOAA draws the moon phases under the same curve and the relationship is obvious at once. The sheet should show it.

The annual envelope ("When this station runs biggest") is a different question with a different driver: across a year the moon's fortnightly cycle averages out and what shapes the envelope is the sun's declination. At a station whose daily tides are unequal (most of the Pacific and the Gulf) the widest months sit near the solstices; at a semidiurnal station (most of the Atlantic) they sit near the equinoxes. The figure currently rules the two widest months with dotted lines; a comment says this is "the equinoxes" but the code just takes the top two spans, which need not be six months apart and are not the thing that explains them. Replace those with the real solstices and equinoxes and say which pair the station follows.

## Goals

- Sliding a finger along the bars lights the bar under it and shows its day and value; lifting jumps the timeline to that day and closes the sheet.
- Moon phases drawn along the bar axis at the days they fall on, so springs visibly sit under new and full.
- Solstices and equinoxes marked on the annual envelope at their true dates, with a caption naming which pair the station's widest months follow.
- All three on the Next max sheet too where the figure is shared: the bars and moon strip there (max current speed follows the same beat); the season marks on its year figure.

## Non-goals

- No moon icons on the annual envelope. The moon's year-to-year nudge (perigee lining up with a spring) is real but is not what the envelope shows, and drawing it would claim a relationship the figure cannot support.
- No new station field for tide type. Which pair the station follows is read off the data (below), never inferred from the source or stored.
- No change to which days the bars cover, how they are scaled, or the "next bigger" caption and its jump.
- No change to the `RangeOutlook` strip on the tide page, which only shares `dailyPeaks`.

## Anti-goals

- A drag that fights the sheet. The bars region is small; it owns touches that start inside it. A drag that starts outside it still dismisses the sheet as today.
- A cancel gesture. Lifting always jumps (owner's call). The sheet closes and the timeline is one swipe back.
- "Scrub" or "scrubber" in any user-facing string. Say slide, drag, or move.

## 1. Sliding the bars (`SwingFigure`)

**Gesture.** A `DragGesture(minimumDistance: 0)` on the figure's canvas. On change, the bar under the finger's x becomes the *lit* bar (index `Int(x / step)` clamped to the bar range, using the same `step` as `bars()`); when the lit index changes, a `UISelectionFeedbackGenerator().selectionChanged()` tick. On end, call `onJump(peak.time)` with the lit bar's own peak instant — the swing or maximum the bar carries — and dismiss. This is the same contract as the "next bigger" button and the Moon facts, which jump to `nextBigger.time`: the reader lands on the swing whose value they were just shown, not on midnight with the swing somewhere to the right. The figure therefore needs the peak per bar: add `peak: Peak` to `Bar`, taken from `dailyPeaks` in `bars()` (its day is `cal.startOfDay(for: peak.time)`). `SwingFigure` takes `@Environment(\.dismiss)` so the sheet keeps passing `onJump` as it does now (the "next bigger" button in the sheet dismisses itself the same way). When `onJump` is nil the gesture does nothing.

**Drawing while lit.** The lit bar draws at full opacity and the selected bar's width (3.2 pt), with a dot at its top like the selected bar; if the lit bar *is* the selected bar nothing changes except the label. Above the lit bar, a label with the day and the value: the day through the existing `monthDay` formatter ("Oct 6"; a weekday alone is ambiguous across a 30-day window, and `cardTime` is a clock), and the value through `formatHeight` / `formatSpeed` as the sheet's own captions do (`TypeScaleTests` wants those near `monospacedDigit()`). The label keeps inside the canvas horizontally (clamp its x so it does not clip at either edge) and sits in the 12 pt headroom the figure already reserves, raised to make room if that is too tight — the builder sizes it. The selected and next-bigger marks stay as they are throughout.

The value the label shows is the bar's own: the day's biggest swing (Range) or hardest maximum in the direction (Max). `Peak` carries `magnitude`; units and imperial come from the sheet, so `SwingFigure` gains `imperial` and `unit` (Range) or a speed formatter path (Max) — the builder picks the smallest change that lets both sheets caption correctly. If the two sheets need different formatters, `SwingFigure` takes a `format: (Double) -> String` closure and each sheet supplies its own.

**Accessibility.** The canvas stays one element with the spoken ranking. VoiceOver users already have the "next bigger" button; the drag is a sighted shortcut, not the only way to a day.

## 2. Moon strip under the bars (`SwingFigure`)

**Data.** `SwingFigure` gains `phases: [MoonPhaseEvent]` (Almanac), the new, first-quarter, full and last-quarter instants inside the figure's window. The sheet's builder (`TideDetailView.rangeDetail(jump:)` and the Max sheet's equivalent) computes them with `searchMoonPhases(from: window.start, to: window.end)`, the same call `MoonDetailSheet.moonFacts` makes. A phase instant maps to the bar whose station-local day contains it (same calendar as `dailyPeaks`); a phase whose day was dropped as a fragment is not drawn.

**Drawing.** A strip of small glyphs (≈9 pt) centred under each phase's bar, beneath the baseline, in `SN.foam` at the axis opacity the year figure uses for its month initials (0.35). Glyph shapes follow the NOAA convention, which is the calendar convention rather than the Moon sheet's observer orientation: a filled disc for full, an outlined disc for new, a half-filled disc for the quarters with the lit half on the right for first quarter and the left for last. The figure's frame grows by the strip's height so the bars keep their box.

**Caption.** The existing "Each bar is one day's biggest swing." line gains a second sentence: "Springs follow the new and full moon." On the Max sheet: "Each bar is one day's hardest flood. Springs follow the new and full moon." (the second sentence is shared). Localised with comments like the neighbours.

**Accessibility.** The spoken label gains the phases that fall in the window, e.g. "Full moon on Oct 6, new moon on Oct 21." — the builder uses the existing day formatter.

## 3. Solstices and equinoxes on the year (`YearFigure`)

**Data.** `YearFigure` gains `seasons: [SeasonEvent]` (Almanac), computed by the same builders with `seasons(from:to:)` over the year window (`TideStanding.yearWindow`) **widened by six months at each end**. The figure draws only the four inside the window; the classifier below uses the whole list, because a standout month at the window's edge (April, when the window starts in April) has its nearest equinox in the March just outside it, and scoring it against September instead would misclassify the station.

**Drawing.** Replace the two "standout month" dotted rules with one faint dotted rule per season event, at its x position *within* its month: `x(i) + (fraction of the month elapsed - 0.5) * step`, so a 21 June solstice sits two-thirds along June's cell rather than on its centre. Same stroke as today (`SN.foam.opacity(0.28)`, dash `[2, 3]`), from the top of the band to the bottom at that month (the envelope's high and low for the containing month, with the same 6 pt reach). The "today" solid rule and the month initials are unchanged.

**Which pair the station follows.** `YearFigure.follows(months:seasons:) -> SeasonPair?` where `SeasonPair` is `.solstices` or `.equinoxes`. Take the two standout months (existing `standout`). For each, the distance in days from its mid-month to the nearest solstice and to the nearest equinox. Sum each kind across the two months; the smaller sum wins. If the two sums are within 45 days of each other, or there are fewer than two standout months, return nil (the station is between kinds and the caption makes no claim). 45 because months quantise to their midpoint: with real dates, June/December scores solstices 10 vs equinoxes 170 (decided), May/November 71 vs 112 (41 apart, withheld), February/August 113 vs 69 (44 apart, withheld), April/October 132 vs 51 (decided: equinoxes — under four weeks away against nine). A 15-day band would decide every pair and the caption would never be withheld. (An earlier draft of this paragraph had April/October at 102 vs 80 and withheld; the test run showed the arithmetic was wrong and the numbers here are the measured ones.) Pure, `nonisolated static`, unit-tested on synthetic months.

**Caption.** Range sheet: "Widest around June, near the solstice." / "Widest around March, near the equinox." when `follows` is non-nil, else today's "Widest around June." Max sheet: "Hardest around …, near the solstice." likewise. Singular, because the caption names one month. Four new localised strings, with comments.

**VoiceOver.** Unchanged ("The water here runs widest in June and December."), plus "near the solstices" / "near the equinoxes" when known.

**Doc.** Update docs/detail.md §6.4 and §6.5: the bars paragraph (drag to a day; moon strip and why), the year paragraph (solstices and equinoxes replace the widest-month marks, and what the caption's "near the …" means and when it is withheld). Remove the comment on `standout` claiming it marks the equinoxes.

## Constraints

- Swift/SwiftUI, Canvas drawing as the figures do today; no Swift Charts.
- Almanac is already a dependency; use `searchMoonPhases` and `seasons`, do not reimplement either.
- Station-local calendar everywhere (`tz`), as `dailyPeaks` and `months` do.
- Source-wide checks in CONTRIBUTING.md ("Source-wide checks") apply to any new file: run `TimelineTests`, `TypeScaleTests`, `ColourAndFormTests`, `HeroChromeTests` alongside the figure tests.
- Local test runs: compile-check first, run the shards touched (`SlackwaterTests/SwingFigureTests`, `YearFigureTests`, `SlackwaterUITests/RangeSheetTests`, `MaxSheetTests`), not the suite.
- No "scrub" in user-facing text. The internal names (`scrubTime`, `ScrubDetailScaffold`) are untouched.

## Tests

Unit:
- `SwingFigure.bars` carries each bar's peak; the lit index for an x maps to the right bar at both edges (clamped), and lifting jumps to that bar's `peak.time`, not its midnight.
- Phase-to-bar mapping: a phase inside the window lands on its day's bar; one on a dropped fragment day draws nothing.
- `YearFigure.follows`: synthetic months peaking in June and December with real-dated seasons → `.solstices`; March and September → `.equinoxes`; May and November, and February and August → nil; April and October → `.equinoxes`; a standout April with the window starting in April is scored against the March equinox outside the window, not September (which would flip it to `.solstices`).
- Season x placement: 21 June lands two-thirds across June's cell.

UI (`RangeSheetTests`, `MaxSheetTests`):
- Pressing and dragging along the bars, then lifting, closes the sheet and moves the timeline to a different day than before (assert through the same affordance `testTappingTheNextBiggerSwingMovesTheScrubber` uses).
- The caption under the bars mentions the moon; the year caption at the fixture station reads "near the solstice" or "near the equinox" as the fixture dictates (the builder checks which the fixture station is and asserts that).

`WebsiteScreenshots` opens this sheet; re-run it and look at the screenshot.

## Left to the builder

- Exact glyph geometry and label typography; the label's exact day format (an existing formatter, not a new pattern).
- Whether `SwingFigure` takes `format:` or `imperial`/`unit`.
- Whether the lit label needs the headroom raised.
- Keeping `MaxDetailSheet`'s `direction` wording in the moon caption.
