// Slackwater — GPL v3. The detail hero's two pieces of language: the
// commentary pill's sentence, and the stops a current lead walks it to.
//
// Both are plain values on `CurrentLead`, not rendered output, which is the
// only reason a unit test can reach them at all — this target renders no text
// and walks no accessibility tree (RenderProbes.swift).
import XCTest
@testable import Slackwater
import TideEngine

final class DetailLeadTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    /// 2026-08-10 12:00 UTC. A fixed wall-clock moment, so the captions this
    /// file asserts are readable strings rather than epoch arithmetic.
    private var t0: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
    }

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - Commentary

    /// "in" counts from the reader, "later" from wherever on the strip they
    /// are looking — the whole difference between the two sentences.
    func testCommentaryCountsFromTheReaderUntilTheScrubLeavesNow() {
        let now = t0
        XCTAssertEqual(commentaryText("High", at: at(28 * 60), from: now, now: now),
                       "High in 28m", "parked on now, the countdown is the reader's")

        // An hour off now is unambiguously scrubbed away: the threshold is one
        // point of strip, five minutes.
        let scrub = at(3600)
        XCTAssertTrue(scrubbedAway(scrub, from: now), "the fixture must actually be scrubbed away")
        XCTAssertEqual(commentaryText("High", at: scrub.addingTimeInterval(3 * 3600 + 28 * 60),
                                      from: scrub, now: now),
                       "High 3h 28m later", "scrubbed away, the countdown is the strip's")
    }

    /// One sentence for both kinds of stop. A tide's "High" and a current's
    /// "Max flood" differ in the event word and in nothing else — the phrasing
    /// is the shared function's, so the two details cannot drift apart.
    func testTideAndCurrentStopsShareOneSentence() {
        let now = t0, target = at(90 * 60)
        let tide = commentaryText("High", at: target, from: now, now: now)
        let current = commentaryText("Max flood", at: target, from: now, now: now)
        XCTAssertEqual(tide, "High in 1h 30m")
        XCTAssertEqual(current, "Max flood in 1h 30m")
        XCTAssertEqual(tide.dropFirst("High".count), current.dropFirst("Max flood".count),
                       "only the event word may differ between a tide and a current stop")
    }

    // MARK: - The stops a current lead walks

    /// A synthetic current day: a flood max, a slack with a window either side
    /// of it, an ebb max, a second window, and a bare slack with no window at
    /// all. Velocities interpolate between the listed points, which is what
    /// tells a window's CLOSING whether the run after it floods or ebbs.
    private func timeline(days: [TimelineDay] = []) -> TimelineData {
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
            ],
            currentEvents: [
                CurrentEvent(time: t0, speed: 2.4, kind: .maxFlood),
                CurrentEvent(time: at(3600), speed: 0, kind: .slack),
                CurrentEvent(time: at(6000), speed: -1.8, kind: .maxEbb),
                CurrentEvent(time: at(9000), speed: 0, kind: .slack),
                CurrentEvent(time: at(12_600), speed: 0, kind: .slack),
            ],
            snapTimes: [],
            slackWindows: [
                (slack: at(3600), start: at(3000), end: at(4200)),
                (slack: at(9000), start: at(8400), end: at(9600)),
            ])
    }

    private func lead(scrub: Date, provisional: Bool = false,
                      days: [TimelineDay] = []) -> CurrentLead {
        CurrentLead(timeline: timeline(days: days), scrubTime: scrub, now: t0, signed: 1,
                    floodDeg: 0, ebbDeg: 180, speedUnit: "kn", tz: utc, provisional: provisional)
    }

    /// Sunset at 12:33, inside the fixture day and ahead of the 1:00 window.
    private var sunsetDay: TimelineDay {
        TimelineDay(offset: 0, start: t0, sunrise: at(-3000), sunset: at(2000),
                    moonrise: nil, moonset: nil)
    }

    private func assertNext(_ scrub: Date, _ time: Date, _ text: String,
                            _ message: String, line: UInt = #line) {
        guard let next = lead(scrub: scrub).nextSignificant else {
            return XCTFail("no stop after the scrub — \(message)", line: line)
        }
        XCTAssertEqual(next.time, time, message, line: line)
        XCTAssertEqual(next.text, text, message, line: line)
    }

    /// Every kind of stop the commentary can walk to, in the order the day
    /// presents them. A window contributes TWO stops — its opening is the
    /// slack, its closing is the run that begins — and the window's own slack
    /// event is dropped so the pill never says "Slack" twice for one turn.
    func testNextSignificantNamesEveryKindOfStop() {
        assertNext(at(-100), t0, "Max flood", "the flood max is the first stop of the day")
        assertNext(at(10), at(3000), "Slack", "a window's opening is a slack")
        assertNext(at(3600), at(4200), "Ebb", "inside a window, the next stop is its closing")
        assertNext(at(4300), at(6000), "Max ebb", "the ebb max")
        assertNext(at(6100), at(8400), "Slack", "the second window opens")
        assertNext(at(9000), at(9600), "Flood",
                   "a closing is named by the velocity after it, not by the one before")
        assertNext(at(9700), at(12_600), "Slack", "a slack with no window is still a stop")
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
        XCTAssertEqual(flood.caption, "Flood at 12:00pm")

        // Past the flood max, the next one is the ebb — reported unsigned,
        // because the direction is the caption's job.
        let ebb = try XCTUnwrap(lead(scrub: at(10)).nextMax)
        XCTAssertEqual(ebb.value, "1.8\u{00a0}kn")
        XCTAssertEqual(ebb.caption, "Ebb at 1:40pm")

        XCTAssertNil(lead(scrub: at(12_700)).nextMax, "no maximum left in the window")
    }

    /// A fast answer marks every number it prints, in the tile and in the
    /// pill alike — one tilde rule, not two.
    func testProvisionalMarksTheTileAndTheCommentary() throws {
        let provisional = lead(scrub: at(-100), provisional: true)
        XCTAssertEqual(try XCTUnwrap(provisional.nextMax).value, "~2.4\u{00a0}kn")
        XCTAssertEqual(provisional.commentary, "~Max flood in 1m")
    }

    /// Dark is a stop like any other: whichever comes first — the water's turn
    /// or the sun's — is what every detail's pill names and its tap walks to.
    func testTheSunIsAStopWhenItComesFirst() {
        let day = sunsetDay
        let high = (time: at(3600), text: "High")
        XCTAssertEqual(nextCommentaryStop(high, sun: [day], after: t0)?.text, "Sunset",
                       "sunset at 12:33 beats the 1:00 high")
        XCTAssertEqual(nextCommentaryStop(high, sun: [day], after: at(2000))?.text, "High",
                       "past sunset, the water's turn is next again")
        XCTAssertEqual(nextCommentaryStop(nil, sun: [day], after: t0)?.text, "Sunset",
                       "the sun still stands when the water has no stop at all")
        XCTAssertNil(nextCommentaryStop(nil, sun: [day], after: at(3600)),
                     "nothing left in the day, nothing for the pill to say")

        // The cutoff is the helper's own, held for both candidates: a caller
        // that hands over the stop it is parked on still walks forward.
        XCTAssertNil(nextCommentaryStop(high, sun: [day], after: at(3600)),
                     "the stop under the scrub is not a stop ahead of it")
        XCTAssertEqual(nextCommentaryStop(high, sun: [day], after: at(1990))?.text, "Sunset",
                       "ten seconds out, the sun is still ahead")
    }

    /// The sun's clock is exact even when the velocities are a fast answer —
    /// the tilde marks the water's numbers and nothing else.
    func testACurrentLeadWalksToTheSunUntilded() {
        let sun = lead(scrub: at(10), provisional: true, days: [sunsetDay])
        XCTAssertEqual(sun.nextSignificant?.time, at(2000), "sunset beats the window's opening")
        XCTAssertEqual(sun.commentary, "Sunset in 33m")

        // Past it, the water is back — and marked, because its speeds are.
        XCTAssertEqual(lead(scrub: at(2010), provisional: true, days: [sunsetDay]).commentary,
                       "~Slack 16m later")
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
