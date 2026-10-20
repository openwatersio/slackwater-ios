// Slackwater — GPL v3. The detail hero's compact commentary content and the
// stops a current lead walks it to.
//
// Both are plain values on `CurrentLead`, not rendered output, which is the
// only reason a unit test can reach them at all — this target renders no text
// and walks no accessibility tree (RenderProbes.swift).
import XCTest
@testable import Slackwater
import SlackwaterKit

@MainActor final class DetailLeadTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    /// 2026-08-10 12:00 UTC. A fixed wall-clock moment, so the captions this
    /// file asserts are readable strings rather than epoch arithmetic.
    private var t0: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
    }

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    /// Drawn samples covering every stop these fixtures name.
    private var wholeDay: ClosedRange<Date> { at(-86_400)...at(86_400) }

    // MARK: - Commentary

    /// Catches sentence glue in visual copy, incomplete spoken units, and missing or swapped tide arrows.
    func testCommentaryContentKeepsVisualCopyCompactAndSpeaksTheRelationship() {
        let locale = Locale(identifier: "en_US")
        let high = CommentaryStop(
            time: at(28 * 60),
            label: "High",
            spokenLabel: "High tide",
            systemImage: "arrow.up"
        )
        let low = CommentaryStop(
            time: at((3 * 60 + 28) * 60),
            label: "Low",
            spokenLabel: "Low tide",
            systemImage: "arrow.down"
        )
        let current = CommentaryStop(
            time: at(90 * 60),
            label: "Max flood"
        )

        XCTAssertEqual(
            commentaryContent(high, from: t0, locale: locale),
            CommentaryContent(
                label: "High",
                duration: "28m",
                systemImage: "arrow.up",
                accessibilityLabel: "High tide in 28 minutes"
            )
        )
        XCTAssertEqual(
            commentaryContent(low, from: t0, locale: locale),
            CommentaryContent(
                label: "Low",
                duration: "3h 28m",
                systemImage: "arrow.down",
                accessibilityLabel: "Low tide in 3 hours, 28 minutes"
            )
        )
        XCTAssertEqual(
            commentaryContent(current, from: t0, locale: locale),
            CommentaryContent(
                label: "Max flood",
                duration: "1h 30m",
                accessibilityLabel: "Max flood in 1 hour, 30 minutes"
            )
        )
    }

    func testEveryCommentaryEventUsesItsOwnSymbolAndFullSpokenLabel() throws {
        let currentCases: [(scrub: Date, label: String, spoken: String, symbol: String)] = [
            (at(-100), "Max flood", "Maximum flood current", "arrow.forward"),
            (at(10), "Slack", "Slack current", "arrow.right.and.line.vertical.and.arrow.left"),
            (at(3600), "Ebb", "Ebb current", "arrow.backward"),
            (at(4300), "Max ebb", "Maximum ebb current", "arrow.backward"),
            (at(9000), "Flood", "Flood current", "arrow.forward"),
        ]

        for expected in currentCases {
            let stop = try XCTUnwrap(lead(scrub: expected.scrub).nextSignificant)
            let content = commentaryContent(stop, from: expected.scrub,
                                            locale: Locale(identifier: "en_US"))
            XCTAssertEqual(stop.label, expected.label)
            XCTAssertEqual(content.systemImage, expected.symbol, expected.label)
            XCTAssertTrue(content.accessibilityLabel.hasPrefix("\(expected.spoken) in "),
                          "\(expected.label) was spoken as '\(content.accessibilityLabel)'")
        }

        let day = TimelineDay(offset: 0, start: t0, sunrise: at(1000), sunset: at(2000),
                              moonrise: nil, moonset: nil)
        let sunrise = try XCTUnwrap(nextCommentaryStop(nil, sun: [day], after: t0, drawn: wholeDay))
        let sunset = try XCTUnwrap(nextCommentaryStop(nil, sun: [day], after: at(1000), drawn: wholeDay))

        XCTAssertEqual(sunrise.systemImage, "sunrise")
        XCTAssertEqual(sunset.systemImage, "sunset")
        XCTAssertTrue(commentaryContent(sunrise, from: t0).accessibilityLabel.hasPrefix("Sunrise in "))
        XCTAssertTrue(commentaryContent(sunset, from: at(1000)).accessibilityLabel.hasPrefix("Sunset in "))
    }

    // MARK: - The stops a current lead walks

    /// A synthetic current day: a flood max, a slack with a window either side
    /// of it, an ebb max, a second window, and a slack at the series' end that
    /// no window covers. Velocities interpolate between the listed points, which is what
    /// tells a window's CLOSING whether the run after it floods or ebbs.
    private func timeline(days: [TimelineDay] = [], drawnUntil: Double = 18_000,
                          windows: [(slack: Date, start: Date, end: Date)]? = nil) -> TimelineData {
        TimelineData(
            tz: utc, anchor: t0, today: t0, start: at(-3600), end: at(18_000),
            days: days, tidePoints: [], tideRates: [], tideExtremes: [],
            currentPoints: [
                CurrentPoint(time: at(-3600), speed: 0),
                CurrentPoint(time: t0, speed: 2.4),
                CurrentPoint(time: at(3600), speed: 0),
                CurrentPoint(time: at(6000), speed: -1.8),
                CurrentPoint(time: at(9000), speed: 0),
                CurrentPoint(time: at(12_600), speed: 2.4),
                CurrentPoint(time: at(18_000), speed: 0),
            ].filter { $0.time <= at(drawnUntil) },
            currentEvents: [
                CurrentEvent(time: t0, speed: 2.4, kind: .maxFlood),
                CurrentEvent(time: at(3600), speed: 0, kind: .slack),
                CurrentEvent(time: at(6000), speed: -1.8, kind: .maxEbb),
                CurrentEvent(time: at(9000), speed: 0, kind: .slack),
                CurrentEvent(time: at(12_600), speed: 0, kind: .slack),
            ],
            snapTimes: [],
            slackWindows: windows ?? [
                (slack: at(3600), start: at(3000), end: at(4200)),
                (slack: at(9000), start: at(8400), end: at(9600)),
            ])
    }

    private func lead(scrub: Date, signed: Double = 1, provisional: Bool = false,
                      days: [TimelineDay] = [], timeline tl: TimelineData? = nil) -> CurrentLead {
        CurrentLead(timeline: tl ?? timeline(days: days), scrubTime: scrub, now: t0, signed: signed,
                    floodDeg: 0, ebbDeg: 180, speedUnit: "kn", tz: utc, provisional: provisional)
    }

    /// Sunset at 12:33, inside the fixture day and ahead of the 1:00 window.
    private var sunsetDay: TimelineDay {
        TimelineDay(offset: 0, start: t0, sunrise: at(-3000), sunset: at(2000),
                    moonrise: nil, moonset: nil)
    }

    private func assertNext(_ scrub: Date, _ time: Date, _ text: String,
                            _ message: String, in tl: TimelineData? = nil, line: UInt = #line) {
        guard let next = lead(scrub: scrub, timeline: tl).nextSignificant else {
            return XCTFail("no stop after the scrub — \(message)", line: line)
        }
        XCTAssertEqual(next.time, time, message, line: line)
        XCTAssertEqual(next.label, text, message, line: line)
    }

    /// The strip's spoken value is the lead in words: the state, then the
    /// magnitude with its unit written out (§ 15), never "kn", then the set outside slack.
    func testSpokenLeadNamesStateAndUnitInFull() {
        XCTAssertEqual(lead(scrub: at(0)).spoken, "Max flood 1.0 knots N")
        XCTAssertEqual(lead(scrub: at(3600)).spoken, "Slack 1.0 knots", "slack claims no set")
        XCTAssertEqual(lead(scrub: at(5000), signed: -1).spoken, "Ebbing 1.0 knots S", "an ebb speaks the ebb set")
        XCTAssertEqual(spokenUnit("km/h"), "kilometres per hour")
        XCTAssertEqual(spokenUnit("ft"), "feet")
    }

    /// Slack is the measured window and nothing else: weak water outside a
    /// window still names its direction, and the window holds Slack at any speed.
    func testTheLeadSaysSlackOnlyInsideAWindow() {
        XCTAssertEqual(lead(scrub: at(5000), signed: 0.1).spoken, "Flooding 0.1 knots N")
        XCTAssertEqual(lead(scrub: at(5000), signed: -0.1).spoken, "Ebbing 0.1 knots S")
        XCTAssertEqual(lead(scrub: at(3600), signed: 0.4).spoken, "Slack 0.4 knots")
    }

    /// Parked on a slack no window covers, the lead agrees with its green dot and the pill that named it.
    func testTheLeadSaysSlackOnASlackNoWindowCovers() {
        XCTAssertEqual(lead(scrub: at(12_600), signed: 0).spoken, "Slack 0.0 knots", "the magnet's own second")
        XCTAssertEqual(lead(scrub: at(12_600.5), signed: 0.1).spoken, "Slack 0.1 knots", "within a second")
        XCTAssertEqual(lead(scrub: at(12_602), signed: 0.1).spoken, "Flooding 0.1 knots N", "off the dot, the flow")
    }

    func testAClosingSlackIsNamedSlackByBothTheCommentaryAndLead() {
        let tl = timeline(windows: [(slack: at(3600), start: at(1800), end: at(3600))])
        assertNext(at(2000), at(3600), "Slack", "the slack owns the closing instant", in: tl)
        XCTAssertEqual(lead(scrub: at(3600), signed: 0, timeline: tl).spoken, "Slack 0.0 knots")
        assertNext(at(3600), at(6000), "Max ebb", "parked on the slack, the commentary advances", in: tl)
    }

    /// Every kind of stop the commentary can walk to, in the order the day
    /// presents them. A window contributes TWO stops — its opening is the
    /// slack, its closing is the run that begins. A slack inside a window is
    /// never a stop itself, so the pill never says "Slack" twice for one turn;
    /// a slack no window covers is drawn as a dot, so it is one stop, at its instant.
    func testNextSignificantNamesEveryKindOfStop() {
        assertNext(at(-100), t0, "Max flood", "the flood max is the first stop of the day")
        assertNext(at(10), at(3000), "Slack", "a window's opening is a slack")
        assertNext(at(3600), at(4200), "Ebb", "inside a window, the next stop is its closing")
        assertNext(at(4300), at(6000), "Max ebb", "the ebb max")
        assertNext(at(6100), at(8400), "Slack", "the second window opens")
        assertNext(at(9000), at(9600), "Flood",
                   "a closing is named by the velocity after it, not by the one before")
        assertNext(at(9700), at(12_600), "Slack", "a slack no window covers is one stop, at its instant")
        XCTAssertNil(lead(scrub: at(12_600)).nextSignificant, "parked on it, nothing follows")
    }

    /// Land exactly on a stop and the pill points at the NEXT one. Otherwise
    /// tapping the commentary scrubs you to where you already are, and the
    /// walk stops dead — the magnet snaps onto these times exactly.
    func testScrubOnAStopAdvancesToTheFollowingOne() {
        assertNext(t0, at(3000), "Slack", "parked on the flood max, the next stop is the window")
        assertNext(at(3000), at(4200), "Ebb", "parked on the opening, the next stop is the closing")
    }

    /// The summary tile: the maximum the water is heading FOR. Slack events
    /// are not maxima, so the tile skips them however near they are.
    func testNextMaxIsTheComingMaximumWithItsDirectionAndTime() throws {
        let flood = try XCTUnwrap(lead(scrub: at(-100)).nextMax)
        XCTAssertEqual(flood.label, "Next max")
        XCTAssertEqual(flood.value, "2.4\u{00a0}kn")
        XCTAssertEqual(flood.caption, "Flood at \(chartTime(t0, utc))")

        // Past the flood max, the next one is the ebb — reported unsigned,
        // because the direction is the caption's job.
        let ebb = try XCTUnwrap(lead(scrub: at(10)).nextMax)
        XCTAssertEqual(ebb.value, "1.8\u{00a0}kn")
        XCTAssertEqual(ebb.caption, "Ebb at \(chartTime(at(6000), utc))")

        XCTAssertNil(lead(scrub: at(12_700)).nextMax, "no maximum left in the window")
    }

    /// A fast answer marks every number it prints, in the tile and in the
    /// pill alike — one tilde rule, not two. The tilde is printed, never spoken.
    func testProvisionalMarksTheTileAndTheCommentary() throws {
        let provisional = lead(scrub: at(-100), provisional: true)
        XCTAssertEqual(try XCTUnwrap(provisional.nextMax).value, "~2.4\u{00a0}kn")
        XCTAssertEqual(
            provisional.commentary,
            CommentaryContent(
                label: "~Max flood",
                duration: "1m",
                systemImage: "arrow.forward",
                accessibilityLabel: "Maximum flood current in 1 minute"
            )
        )
        XCTAssertEqual(provisional.spoken, "Flooding 1.0 knots N")
        XCTAssertEqual(leadSpokenValue("~1.0", unit: "kn"), "1.0 kn", "the lead's value is spoken without its tilde")
        XCTAssertEqual(leadSpokenValue("-0.4", unit: "m"), "-0.4 m")
        XCTAssertEqual(leadSpokenValue("2.1", unit: nil), "2.1")
    }

    /// VoiceOver reads a lead glyph by its unrotated symbol name ("up arrow" for a set to the south), so every eyebrow glyph goes through the hidden `LeadGlyph`.
    func testEveryLeadGlyphIsHiddenFromVoiceOver() throws {
        var leads = 0
        for (name, source) in try appSources() {
            var rest = source[...]
            while let call = rest.range(of: "LeadCard(") {
                let eyebrow = try XCTUnwrap(trailingClosure(after: call.upperBound, in: source), "\(name): no eyebrow")
                XCTAssertTrue(eyebrow.contains("LeadGlyph("), "\(name): a lead eyebrow without its glyph")
                XCTAssertFalse(eyebrow.contains("Image(systemName:"), "\(name): a spoken eyebrow glyph")
                XCTAssertFalse(eyebrow.contains("CompassArrow("), "\(name): a spoken set arrow")
                leads += 1
                rest = source[eyebrow.endIndex...]
            }
        }
        XCTAssertEqual(leads, 3, "the tide, current, and derived-gate leads")
        let glyph = try repoSource("Slackwater/DetailPieces.swift")
        let body = try XCTUnwrap(glyph.range(of: "struct LeadGlyph: View {")).upperBound
        XCTAssertTrue(try XCTUnwrap(trailingClosure(after: body, in: glyph, opened: true)).contains(".accessibilityHidden(true)"))
    }

    /// The text of the brace block that follows `index`: a call's trailing closure, or with `opened` the block `index` is already inside.
    private func trailingClosure(after index: String.Index, in source: String, opened: Bool = false) -> Substring? {
        var depth = opened ? 1 : 0, parens = opened ? 0 : 1
        var start = opened ? index : nil
        var i = index
        while i < source.endIndex {
            switch source[i] {
            case "(": parens += 1
            case ")": parens -= 1
            case "{" where parens == 0:
                if start == nil { start = source.index(after: i) }
                depth += 1
            case "}" where parens == 0:
                depth -= 1
                if depth == 0, let start { return source[start..<i] }
            default: break
            }
            i = source.index(after: i)
        }
        return nil
    }

    /// Dark is a stop like any other: whichever comes first — the water's turn
    /// or the sun's — is what every detail's pill names and its tap walks to.
    func testTheSunIsAStopWhenItComesFirst() {
        let day = sunsetDay
        let high = CommentaryStop(time: at(3600), label: "High")
        XCTAssertEqual(nextCommentaryStop(high, sun: [day], after: t0, drawn: wholeDay)?.label, "Sunset",
                       "sunset at 12:33 beats the 1:00 high")
        XCTAssertEqual(nextCommentaryStop(high, sun: [day], after: at(2000), drawn: wholeDay)?.label, "High",
                       "past sunset, the water's turn is next again")
        XCTAssertEqual(nextCommentaryStop(nil, sun: [day], after: t0, drawn: wholeDay)?.label, "Sunset",
                       "the sun still stands when the water has no stop at all")
        XCTAssertNil(nextCommentaryStop(nil, sun: [day], after: at(3600), drawn: wholeDay),
                     "nothing left in the day, nothing for the pill to say")

        // The cutoff is the helper's own, held for both candidates: a caller
        // that hands over the stop it is parked on still walks forward.
        XCTAssertNil(nextCommentaryStop(high, sun: [day], after: at(3600), drawn: wholeDay),
                     "the stop under the scrub is not a stop ahead of it")
        XCTAssertEqual(nextCommentaryStop(high, sun: [day], after: at(1990), drawn: wholeDay)?.label, "Sunset",
                       "ten seconds out, the sun is still ahead")
    }

    /// A turn half a second ahead is already reached, so every detail names the stop after it.
    func testEveryDetailTakesTheFirstStopMoreThanASecondAhead() {
        let extremes = [TideExtreme(time: at(0.5), height: 2, kind: .high),
                        TideExtreme(time: at(6 * 3600), height: 0, kind: .low)]
        XCTAssertEqual(firstCommentaryStop(extremes, at: \.time, after: t0, drawn: wholeDay)?.time,
                       at(6 * 3600), "the tide's walk skips the turn it is on")
        XCTAssertEqual(firstCommentaryStop([at(0.5), at(3600)], at: { $0 }, after: t0, drawn: wholeDay),
                       at(3600), "and so does a derived gate's")
        assertNext(at(2999.5), at(4200), "Ebb", "the current's walk skips the opening it is on")
    }

    /// A stop past the last drawn sample, water or sun, would send the tap past the data.
    func testCommentaryNeverNamesAStopPastTheDrawnSamples() {
        let day = sunsetDay
        let high = CommentaryStop(time: at(3600), label: "High")
        XCTAssertNil(nextCommentaryStop(high, sun: [day], after: t0, drawn: at(-3600)...at(1800)),
                     "both the sunset and the high lie past the drawn data")
        XCTAssertEqual(nextCommentaryStop(high, sun: [day], after: t0, drawn: at(-3600)...at(2500))?.label,
                       "Sunset")
        XCTAssertNil(nextCommentaryStop(high, sun: [day], after: t0, drawn: nil), "no samples, no stops")

        // The ebb max at 1:40 is a padded event the series stops short of.
        let short = timeline(drawnUntil: 5000)
        XCTAssertNil(lead(scrub: at(4300), timeline: short).nextSignificant,
                     "the max past the last sample is not named")
        XCTAssertEqual(lead(scrub: at(10), timeline: short).nextSignificant?.time, at(3000),
                       "a stop inside the samples still is")
    }

    /// A run drawn as one dot is one stop, so the walk never names an opening and closing around a single mark.
    func testADotRunIsOneStopAtItsCentre() {
        let dot = timeline(windows: [(slack: at(3600), start: at(3200), end: at(3800))])
        assertNext(at(10), at(3500), "Slack", "the dot's centre is the stop", in: dot)
        assertNext(at(3500), at(6000), "Max ebb", "a dot has no closing to name", in: dot)
    }

    /// The sun's clock is exact even when the velocities are a fast answer —
    /// the tilde marks the water's numbers and nothing else.
    func testACurrentLeadWalksToTheSunUntilded() {
        let sun = lead(scrub: at(10), provisional: true, days: [sunsetDay])
        XCTAssertEqual(sun.nextSignificant?.time, at(2000), "sunset beats the window's opening")
        XCTAssertEqual(
            sun.commentary,
            CommentaryContent(
                label: "Sunset",
                duration: "33m",
                systemImage: "sunset",
                accessibilityLabel: "Sunset in 33 minutes"
            )
        )

        // The tilde belongs to the provisional water event, not the exact sun clock.
        XCTAssertEqual(
            lead(scrub: at(2010), provisional: true, days: [sunsetDay]).commentary,
            CommentaryContent(
                label: "~Slack",
                duration: "16m",
                systemImage: "arrow.right.and.line.vertical.and.arrow.left",
                accessibilityLabel: "Slack current in 16 minutes"
            )
        )
    }

    func testFastTideCommentaryWalksFromRatePeakToItsTurn() {
        for sign in [1.0, -1.0] {
            let rates: [Double] = [0, 0.8, 1.8, 1.0, 0, -0.8, -1.8, -1.0, 0, 0.8, 1.8, 1.0, 0]
            let timeline = TimelineData(
                tz: utc, anchor: t0, today: t0, start: t0, end: at(12 * 3600),
                days: [],
                tidePoints: rates.enumerated().map { TidePoint(time: at(Double($0.offset) * 3600), height: 0) },
                tideRates: rates.enumerated().map { TideRatePoint(time: at(Double($0.offset) * 3600), rate: sign * $0.element) },
                tideExtremes: [
                    TideExtreme(time: at(4 * 3600), height: 0, kind: sign > 0 ? .high : .low),
                    TideExtreme(time: at(8 * 3600), height: 0, kind: sign > 0 ? .low : .high),
                    TideExtreme(time: at(12 * 3600), height: 0, kind: sign > 0 ? .high : .low),
                ],
                currentPoints: [], currentEvents: [], snapTimes: [], slackWindows: [])
            let cases: [(hours: Double, target: Double)] = [
                (1, 2), (2, 4), (2 + 0.5 / 3600, 4), (3, 4), (5, 6), (6, 8), (7, 8), (9, 10),
            ]
            for c in cases {
                XCTAssertEqual(tideCommentaryTarget(in: timeline, at: at(c.hours * 3600),
                                                    nextStop: at((c.hours < 3 ? 3 : 7.5) * 3600)),
                               at(c.target * 3600), "sign \(sign), hour \(c.hours)")
            }
            XCTAssertEqual(tideCommentaryTarget(in: timeline, at: t0, nextStop: at(1800)), at(1800),
                           "a quiet tide still walks to the earlier sun event")
        }
    }

    /// The pill explains the yellow line: the rate, direction first, in the
    /// station's height unit per hour, and nothing at all below the ramp's
    /// first anchor.
    func testFastTideCommentaryNamesTheRate() {
        XCTAssertNil(tideRateCommentary(rate: 0.3, imperial: true))
        XCTAssertNil(tideRateCommentary(rate: -0.59, imperial: false))
        XCTAssertEqual(tideRateCommentary(rate: 0.6, imperial: false), "Rising 0.60 m/hr")
        XCTAssertEqual(tideRateCommentary(rate: -1.6, imperial: true), "Falling 5.2 ft/hr")
    }
}
