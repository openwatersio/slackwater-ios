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
    private var savedSetFormat: Any?

    // The lead reads the set format from the shared defaults, which a Settings tap on this simulator can leave at degrees.
    override func setUp() async throws {
        try await super.setUp()
        savedSetFormat = AppGroup.defaults.object(forKey: setFormatKey)
        AppGroup.defaults.set("compass", forKey: setFormatKey)
    }

    override func tearDown() async throws {
        AppGroup.defaults.set(savedSetFormat, forKey: setFormatKey)
        try await super.tearDown()
    }

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

    func testCommentaryEventsUseAppropriateSymbolsAndFullSpokenLabels() throws {
        let currentCases: [(scrub: Date, label: String, spoken: String, symbol: String?)] = [
            (at(-100), "Max flood", "Maximum flood current", nil),
            (at(10), "Slack window", "Slack window", "arrow.right.and.line.vertical.and.arrow.left"),
            (at(3000), "Slack", "Slack current", "arrow.right.and.line.vertical.and.arrow.left"),
            (at(3600), "Slack window", "Slack window closes", "arrow.left.and.line.vertical.and.arrow.right"),
            (at(4300), "Max ebb", "Maximum ebb current", nil),
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
    /// no window covers. Each window holds a slack core around its slack, short
    /// enough to draw as a dot at its slack.
    /// Velocities interpolate between the listed points, which is what
    /// tells a window's CLOSING whether the run after it floods or ebbs.
    private func timeline(days: [TimelineDay] = [], drawnUntil: Double = 18_000,
                          windows: [(slack: Date, start: Date, end: Date)]? = nil,
                          cores: [(slack: Date, start: Date, end: Date)]? = nil) -> TimelineData {
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
            ],
            slackCores: cores ?? [
                (slack: at(3600), start: at(3500), end: at(3700)),
                (slack: at(9000), start: at(8900), end: at(9100)),
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
        // The closing shows the opening's words; its spoken label tells them apart.
        let spoken = text == "Slack window closes" ? text : nil
        let text = spoken == nil ? text : "Slack window"
        guard let next = lead(scrub: scrub, timeline: tl).nextSignificant else {
            return XCTFail("no stop after the scrub — \(message)", line: line)
        }
        XCTAssertEqual(next.time, time, message, line: line)
        XCTAssertEqual(next.label, text, message, line: line)
        if let spoken { XCTAssertEqual(next.spokenLabel, spoken, message, line: line) }
    }

    /// The strip's spoken value is the lead in words: the state, then the
    /// magnitude with its unit written out (§ 15), never "kn", then the set outside slack.
    func testSpokenLeadNamesStateAndUnitInFull() {
        XCTAssertEqual(lead(scrub: at(0)).spoken, "Max flood 1.0 knots N")
        XCTAssertEqual(lead(scrub: at(3600)).spoken, "Slack 1.0 knots", "slack claims no set")
        XCTAssertEqual(lead(scrub: at(5000), signed: -1).spoken, "Ebbing 1.0 knots S", "an ebb speaks the ebb set")
        AppGroup.defaults.set("degrees", forKey: setFormatKey)
        XCTAssertEqual(lead(scrub: at(5000), signed: -1).spoken, "Ebbing 1.0 knots 180°", "degrees follow the setting (#822)")
        AppGroup.defaults.set("compass", forKey: setFormatKey)
        XCTAssertEqual(spokenUnit("km/h"), "kilometres per hour")
        XCTAssertEqual(spokenUnit("ft"), "feet")
    }

    /// Slack is the measured slack core and nothing else: weak water outside a
    /// window still names its direction, and so does water inside the slack
    /// window but outside its core (#821).
    func testTheLeadSaysSlackOnlyInsideASlackCore() {
        XCTAssertEqual(lead(scrub: at(5000), signed: 0.1).spoken, "Flooding 0.1 knots N")
        XCTAssertEqual(lead(scrub: at(5000), signed: -0.1).spoken, "Ebbing 0.1 knots S")
        XCTAssertEqual(lead(scrub: at(3100), signed: 0.4).spoken, "Flooding 0.4 knots N",
                       "inside the slack window, the water is still flooding")
        XCTAssertEqual(lead(scrub: at(3500), signed: 0.1).spoken, "Slack 0.1 knots", "a core dot holds its own span")
        XCTAssertEqual(lead(scrub: at(3700), signed: -0.1).spoken, "Ebbing 0.1 knots S", "the core's closing is not slack")
    }

    /// A weak station whose whole flood stays under the comfort current: the
    /// window covers the maximum, and the lead still says Max flood there and
    /// Flooding around it (#821, Little Misery Island).
    func testAWindowCoveringAMaximumStillNamesTheFlood() {
        let weak = timeline(windows: [(slack: at(3600), start: at(-3600), end: at(4200))])
        XCTAssertEqual(lead(scrub: t0, signed: 0.4, timeline: weak).spoken, "Max flood 0.4 knots N")
        XCTAssertEqual(lead(scrub: at(1000), signed: 0.4, timeline: weak).spoken, "Flooding 0.4 knots N")
        XCTAssertEqual(lead(scrub: at(3600), signed: 0, timeline: weak).spoken, "Slack 0.0 knots")
    }

    /// A slack whose water never gets under the slack speed has no core. It
    /// keeps its dot, and parked on that dot the lead says Slack.
    func testASlackWithoutACoreReadsSlackOnlyOnItsDot() {
        let rotary = timeline(cores: [(slack: at(9000), start: at(8900), end: at(9100))])
        XCTAssertEqual(lead(scrub: at(3600), signed: 0.3, timeline: rotary).spoken, "Slack 0.3 knots")
        XCTAssertEqual(lead(scrub: at(3602), signed: -0.3, timeline: rotary).spoken, "Ebbing 0.3 knots S")
        assertNext(at(10), at(3000), "Slack window", "the window still opens", in: rotary)
        assertNext(at(3000), at(3600), "Slack", "the slack's own dot", in: rotary)
    }

    /// A comfort current under the slack speed makes the whole window slack: one
    /// stop, named Slack, where the window and its core open together.
    func testAWindowThatIsAllCoreOpensAsSlack() {
        let narrow = timeline(cores: [
            (slack: at(3600), start: at(3000), end: at(4200)),
            (slack: at(9000), start: at(8400), end: at(9600)),
        ])
        assertNext(at(10), at(3000), "Slack", "one stop for the shared opening", in: narrow)
        assertNext(at(3000), at(4200), "Slack window closes", "then the closing", in: narrow)
    }

    /// Parked on a slack no window covers, the lead agrees with its green dot and the pill that named it.
    func testTheLeadSaysSlackOnASlackNoWindowCovers() {
        XCTAssertEqual(lead(scrub: at(12_600), signed: 0).spoken, "Slack 0.0 knots", "the magnet's own second")
        XCTAssertEqual(lead(scrub: at(12_600.5), signed: 0.1).spoken, "Slack 0.1 knots", "within a second")
        XCTAssertEqual(lead(scrub: at(12_602), signed: 0.1).spoken, "Flooding 0.1 knots N", "off the dot, the flow")
    }

    func testAClosingSlackIsNamedSlackByBothTheCommentaryAndLead() {
        let tl = timeline(windows: [(slack: at(3600), start: at(1800), end: at(3600))],
                          cores: [(slack: at(3600), start: at(3400), end: at(3600))])
        assertNext(at(3500), at(3600), "Slack", "the slack owns the closing instant", in: tl)
        XCTAssertEqual(lead(scrub: at(3600), signed: 0, timeline: tl).spoken, "Slack 0.0 knots")
        assertNext(at(3600), at(6000), "Max ebb", "parked on the slack, the commentary advances", in: tl)
    }

    /// Every kind of stop the commentary can walk to, in the order the day
    /// presents them. A window contributes its opening, named Slack window, and
    /// its closing, spoken Slack window closes. Its core contributes Slack at
    /// the core's opening, or its centre when it draws as a dot, as these do.
    /// A slack inside a core is never a stop itself, so the
    /// pill never says "Slack" twice for one turn; a slack no core holds is
    /// drawn as a dot, so it is one stop, at its instant.
    func testNextSignificantNamesEveryKindOfStop() {
        assertNext(at(-100), t0, "Max flood", "the flood max is the first stop of the day")
        assertNext(at(10), at(3000), "Slack window", "a window's opening")
        assertNext(at(3000), at(3600), "Slack", "its core's dot is the slack")
        assertNext(at(3600), at(4200), "Slack window closes", "inside a window, the next stop is its closing")
        assertNext(at(4300), at(6000), "Max ebb", "the ebb max")
        assertNext(at(6100), at(8400), "Slack window", "the second window opens")
        assertNext(at(8400), at(9000), "Slack", "and its core")
        assertNext(at(9000), at(9600), "Slack window closes", "the second window closes")
        assertNext(at(9700), at(12_600), "Slack", "a slack no window covers is one stop, at its instant")
        XCTAssertNil(lead(scrub: at(12_600)).nextSignificant, "parked on it, nothing follows")
    }

    /// Land exactly on a stop and the pill points at the NEXT one. Otherwise
    /// tapping the commentary scrubs you to where you already are, and the
    /// walk stops dead — the magnet snaps onto these times exactly.
    func testScrubOnAStopAdvancesToTheFollowingOne() {
        assertNext(t0, at(3000), "Slack window", "parked on the flood max, the next stop is the window")
        assertNext(at(3000), at(3600), "Slack", "parked on the opening, the next stop is the core")
        assertNext(at(3600), at(4200), "Slack window closes", "parked on the core, the next stop is the closing")
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
        assertNext(at(2999.5), at(3600), "Slack", "the current's walk skips the opening it is on")
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
        let dot = timeline(windows: [(slack: at(3600), start: at(3200), end: at(3800))],
                           cores: [(slack: at(3600), start: at(3500), end: at(3650))])
        assertNext(at(10), at(3575), "Slack", "a window that short is not drawn: its core's dot is the stop", in: dot)
        assertNext(at(3575), at(6000), "Max ebb", "a dot has no closing to name", in: dot)
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
                label: "~Slack window",
                duration: "16m",
                systemImage: "arrow.right.and.line.vertical.and.arrow.left",
                accessibilityLabel: "Slack window in 16 minutes"
            )
        )
    }

    /// A fast run is one stop, at its fastest point, between its turns: once
    /// the selection reaches the peak, the turn is next. A quiet run has none.
    func testFastTideRunIsOneStopAtItsPeak() {
        for sign in [1.0, -1.0] {
            func timeline(scale: Double) -> TimelineData {
                let rates: [Double] = [0, 0.8, 1.8, 1.0, 0, -0.8, -1.8, -1.0, 0, 0.8, 1.8, 1.0, 0]
                return TimelineData(
                    tz: utc, anchor: t0, today: t0, start: t0, end: at(12 * 3600),
                    days: [],
                    tidePoints: rates.enumerated().map { TidePoint(time: at(Double($0.offset) * 3600), height: 0) },
                    tideRates: rates.enumerated().map { TideRatePoint(time: at(Double($0.offset) * 3600), rate: sign * scale * $0.element) },
                    tideExtremes: [
                        TideExtreme(time: at(4 * 3600), height: 0, kind: sign > 0 ? .high : .low),
                        TideExtreme(time: at(8 * 3600), height: 0, kind: sign > 0 ? .low : .high),
                        TideExtreme(time: at(12 * 3600), height: 0, kind: sign > 0 ? .high : .low),
                    ],
                    currentPoints: [], currentEvents: [], snapTimes: [], slackWindows: [])
            }
            let fast = timeline(scale: 1)
            let rise = sign > 0 ? "Fastest rise" : "Fastest fall"
            let fall = sign > 0 ? "Fastest fall" : "Fastest rise"
            let turn = sign > 0 ? "High" : "Low"
            let cases: [(hours: Double, stop: Double, label: String)] = [
                (0, 2, rise), (1, 2, rise), (2 - 0.5 / 3600, 4, turn), (2, 4, turn), (3, 4, turn),
                (4, 6, fall), (5, 6, fall), (7, 8, sign > 0 ? "Low" : "High"), (9, 10, rise),
            ]
            for c in cases {
                let stop = tideWaterStop(in: fast, after: at(c.hours * 3600))
                XCTAssertEqual(stop?.time, at(c.stop * 3600), "sign \(sign), hour \(c.hours)")
                XCTAssertEqual(stop?.label, c.label, "sign \(sign), hour \(c.hours)")
            }
            XCTAssertEqual(tideWaterStop(in: timeline(scale: 0.3), after: t0)?.label, turn,
                           "a run under the rate-warning scale has no peak stop")
        }
    }

    func testFastTidePeakStopNamesTheMomentWithTheLeadsGlyph() {
        let rise = tideRatePeakStop(TideRatePoint(time: t0, rate: 0.7))
        XCTAssertEqual(rise.label, "Fastest rise")
        XCTAssertEqual(rise.spokenLabel, "Fastest rising tide")
        XCTAssertEqual(rise.systemImage, "arrow.up.right")
        let fall = tideRatePeakStop(TideRatePoint(time: t0, rate: -0.7))
        XCTAssertEqual(fall.label, "Fastest fall")
        XCTAssertEqual(fall.systemImage, "arrow.down.right")
    }

    /// The lead explains the yellow line: the rate, direction first, in the
    /// station's height unit per hour, and nothing at all below the ramp's
    /// first anchor.
    func testFastTideLeadNamesTheRate() {
        XCTAssertNil(tideRateReading(rate: 0.3, imperial: true))
        XCTAssertNil(tideRateReading(rate: -0.59, imperial: false))
        XCTAssertEqual(tideRateReading(rate: 0.6, imperial: false), "Rising 0.60 m/hr")
        XCTAssertEqual(tideRateReading(rate: -1.6, imperial: true), "Falling 5.2 ft/hr")
    }
}
