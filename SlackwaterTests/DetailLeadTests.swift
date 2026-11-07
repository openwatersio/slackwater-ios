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

    /// A lead over the fixture day, flooding north and ebbing south. `signed` makes a one-axis point, as a station without cross-flow constants predicts; `point` stands in for a rotary one.
    private func lead(scrub: Date, signed: Double = 1, point: CurrentPoint? = nil, provisional: Bool = false,
                      days: [TimelineDay] = [], timeline tl: TimelineData? = nil) -> CurrentLead {
        CurrentLead(timeline: tl ?? timeline(days: days), scrubTime: scrub, now: t0,
                    point: point ?? CurrentPoint(time: scrub, speed: signed),
                    floodDeg: 0, ebbDeg: 180, speedUnit: "kn", tz: utc, provisional: provisional)
    }

    private let slackGlyph = "arrow.right.and.line.vertical.and.arrow.left"

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
    /// magnitude with its unit written out (§ 15), never "kn", then the set wherever the lead shows one.
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

    // MARK: - The lead's speed and set

    private func reading(_ state: String, _ value: String, set: Double?, _ text: String?,
                         tint: CurrentPhase, spoken: String) -> CurrentLeadReading {
        CurrentLeadReading(state: state, value: value, setDegrees: set, set: text, tint: tint, spoken: spoken)
    }

    /// A station without cross-flow constants reads exactly as it always has: the unsigned major-axis speed, the published bearing for its sign in the flood or ebb colour, and at slack the slack glyph in the go colour with no set.
    func testAOneAxisLeadReadsAsItAlwaysHas() {
        XCTAssertEqual(lead(scrub: at(1000), signed: 1.2).reading,
                       reading("Flooding", "1.2", set: 0, "N", tint: .flood, spoken: "Flooding 1.2 knots N"))
        XCTAssertEqual(lead(scrub: at(5000), signed: -1.3).reading,
                       reading("Ebbing", "1.3", set: 180, "S", tint: .ebb, spoken: "Ebbing 1.3 knots S"))
        XCTAssertEqual(lead(scrub: t0, signed: 2.4).reading,
                       reading("Max flood", "2.4", set: 0, "N", tint: .flood, spoken: "Max flood 2.4 knots N"))
        XCTAssertEqual(lead(scrub: at(6000), signed: -1.8).reading,
                       reading("Max ebb", "1.8", set: 180, "S", tint: .ebb, spoken: "Max ebb 1.8 knots S"))
        XCTAssertEqual(lead(scrub: at(3600), signed: 0).reading,
                       reading("Slack", "0.0", set: nil, nil, tint: .slack, spoken: "Slack 0.0 knots"))
        XCTAssertEqual(lead(scrub: at(3500), signed: 0.1).reading,
                       reading("Slack", "0.1", set: nil, nil, tint: .slack, spoken: "Slack 0.1 knots"),
                       "along the axis there is no crossing flow to point at")
        XCTAssertEqual(lead(scrub: at(1000), signed: 1.2).reading.glyph, "arrow.up")
        XCTAssertEqual(lead(scrub: at(3600), signed: 0).reading.glyph, slackGlyph)
    }

    /// Pollock Rip predicted by the engine, through a day of events and hours: the reading the lead built before vectors, from the signed speed and the published bearings, is the one it builds now.
    func testAnEngineOneAxisStationReadsAsItAlwaysHas() throws {
        let pollock = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/ACT1616"))
        let station = pollock.engineStation
        let events = station.events(from: t0, to: t0.addingTimeInterval(86_400))
        let hours = (0..<24).map { (time: t0.addingTimeInterval(Double($0) * 3600 + 7), slack: false) }
        let instants = events.map { (time: $0.time, slack: $0.kind == .slack) } + hours
        XCTAssertTrue(events.contains { $0.kind == .slack })
        for instant in instants {
            let p = try XCTUnwrap(station.speeds(from: instant.time, to: instant.time.addingTimeInterval(1), step: 1).first)
            let state = instant.slack ? "Slack" : p.speed >= 0 ? "Flooding" : "Ebbing"
            let value = formatSpeed(abs(p.speed), unit: "kn")
            let bearing: Double? = instant.slack ? nil : p.speed >= 0 ? pollock.floodDirection : pollock.ebbDirection
            let set = bearing.map { formatSet($0, format: "compass") }
            let words = "\(state) \(value) knots"
            XCTAssertEqual(currentLeadReading(state, isSlack: instant.slack, point: p,
                                              floodDeg: pollock.floodDirection, ebbDeg: pollock.ebbDirection,
                                              speedUnit: "kn", setFormat: "compass"),
                           reading(state, value, set: bearing, set,
                                   tint: instant.slack ? .slack : p.speed >= 0 ? .flood : .ebb,
                                   spoken: set.map { "\(words) \($0)" } ?? words),
                           "\(instant.time)")
        }
    }

    /// At a major-axis slack the word stays Slack, and the lead shows what the water is still doing across the channel: its full speed, and its arrow and set in the go colour, since there is no flood or ebb to colour by.
    func testARotaryLeadAtSlackShowsTheCrossingFlow() {
        let crossing = CurrentPoint(time: at(3600), speed: 0, magnitude: 0.6, direction: 95)
        XCTAssertEqual(lead(scrub: at(3600), point: crossing).reading,
                       reading("Slack", "0.6", set: 95, "E", tint: .slack, spoken: "Slack 0.6 knots E"))
        XCTAssertEqual(lead(scrub: at(3600), point: crossing).reading.glyph, "arrow.up")
        AppGroup.defaults.set("degrees", forKey: setFormatKey)
        XCTAssertEqual(lead(scrub: at(3600), point: crossing).spoken, "Slack 0.6 knots 095°")
        AppGroup.defaults.set("compass", forKey: setFormatKey)

        let faint = CurrentPoint(time: at(3600), speed: 0, magnitude: 0.03, direction: 95)
        XCTAssertEqual(lead(scrub: at(3600), point: faint).reading,
                       reading("Slack", "0.0", set: nil, nil, tint: .slack, spoken: "Slack 0.0 knots"),
                       "a crossing flow that prints as 0.0 claims no set")
        XCTAssertEqual(lead(scrub: at(3600), point: faint).reading.glyph, slackGlyph)
    }

    /// Inside a slack core the water can still run 0.3 kn along the axis and 0.5 kn in all. The lead prints the full 0.5, not the 0.4 crossing it, and that crossing flow, printing above zero, shows the set in the go colour.
    func testARotaryLeadAtSlackKeepsTheFullSpeedWhileTheAxisStillRuns() {
        let running = CurrentPoint(time: at(3550), speed: 0.3, magnitude: 0.5, direction: 95)
        XCTAssertEqual(lead(scrub: at(3550), point: running).reading,
                       reading("Slack", "0.5", set: 95, "E", tint: .slack, spoken: "Slack 0.5 knots E"))
    }

    /// Kodiak's cross-flow runs at up to about 0.8 of its major axis, so at two of its three slacks on this day the engine-exact lead still has a speed and a set; at the third the crossing flow prints 0.0 and the lead claims no set.
    func testKodiakAtItsSlacksShowsTheCrossingFlow() throws {
        let kodiak = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/KOD0901"))
        let slacks = kodiak.engineStation.events(from: t0, to: t0.addingTimeInterval(86_400)).filter { $0.kind == .slack }
        var crossing = 0, still = 0
        for slack in slacks {
            let p = try XCTUnwrap(kodiak.engineStation.speeds(from: slack.time, to: slack.time.addingTimeInterval(1), step: 1).first)
            let r = currentLeadReading("Slack", isSlack: true, point: p, floodDeg: kodiak.floodDirection,
                                       ebbDeg: kodiak.ebbDirection, speedUnit: "kn", setFormat: "compass")
            let direction = try XCTUnwrap(p.direction)
            XCTAssertEqual(r.value, formatSpeed(p.magnitude, unit: "kn"), "\(slack.time)")
            XCTAssertEqual(r.tint, .slack, "\(slack.time)")
            if r.value == "0.0" {
                still += 1
                XCTAssertNil(r.setDegrees, "\(slack.time)")
                XCTAssertEqual(r.spoken, "Slack 0.0 knots", "\(slack.time)")
            } else {
                crossing += 1
                XCTAssertEqual(r.setDegrees, direction, "\(slack.time)")
                XCTAssertEqual(r.set, compassPoint(direction), "\(slack.time)")
                XCTAssertEqual(r.spoken, "Slack \(r.value) knots \(compassPoint(direction))", "\(slack.time)")
            }
        }
        XCTAssertEqual(crossing, 2, "two of the day's slacks still run across the channel")
        XCTAssertEqual(still, 1)
    }

    /// Outside slack the value is the water's full speed and the set its own direction, not the published bearing, in the flood or ebb colour by the signed speed.
    func testARotaryLeadOutsideSlackFollowsTheWater() {
        let flooding = CurrentPoint(time: at(1000), speed: 1.2, magnitude: 1.5, direction: 40)
        XCTAssertEqual(lead(scrub: at(1000), point: flooding).reading,
                       reading("Flooding", "1.5", set: 40, "NE", tint: .flood, spoken: "Flooding 1.5 knots NE"))
        let ebbing = CurrentPoint(time: at(5000), speed: -1.0, magnitude: 1.4, direction: 230)
        XCTAssertEqual(lead(scrub: at(5000), point: ebbing).reading,
                       reading("Ebbing", "1.4", set: 230, "SW", tint: .ebb, spoken: "Ebbing 1.4 knots SW"))
        let max = CurrentPoint(time: t0, speed: 2.4, magnitude: 2.5, direction: 20)
        XCTAssertEqual(lead(scrub: t0, point: max).reading.spoken, "Max flood 2.5 knots NNE")
    }

    /// Water with no known set claims none: the slack glyph in the go colour, whatever the word.
    func testALeadWithNoSetShowsTheSlackGlyph() {
        let unknown = CurrentPoint(time: at(1000), speed: 1.2, magnitude: 1.5, direction: nil)
        XCTAssertEqual(lead(scrub: at(1000), point: unknown).reading,
                       reading("Flooding", "1.5", set: nil, nil, tint: .slack, spoken: "Flooding 1.5 knots"))
        XCTAssertEqual(lead(scrub: at(1000), point: unknown).reading.glyph, slackGlyph)
        XCTAssertEqual(lead(scrub: at(1000), signed: 0).reading,
                       reading("Flooding", "0.0", set: nil, nil, tint: .slack, spoken: "Flooding 0.0 knots"),
                       "a zero vector has no set")
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
        var hidden = sun
        hidden.showsSun = false
        XCTAssertEqual(hidden.nextSignificant?.label, "~Slack window",
                       "with Settings hiding the sun marks, the commentary walks past sunset")
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
