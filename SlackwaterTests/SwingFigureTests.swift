import XCTest
import SlackwaterKit
import Almanac
@testable import Slackwater

/// Section 1's figure: the day's biggest swing, for each day of the fortnight.
/// The spring/neap beat IS the answer to "is this beyond normal", so the
/// layout's whole job is to keep that beat readable.
@MainActor final class SwingFigureTests: XCTestCase {
    private let station = TideStationRecord.record(id: TideStationRecord.fridayHarborID)!
    private let at = Date(timeIntervalSince1970: 1_780_000_000)
    private let size = CGSize(width: 320, height: 120)

    private func standing(pick: (([TideRange]) -> TideRange)? = nil) -> PeakStanding {
        let w = TideStanding.window(around: at, tz: station.tz)
        let all = station.engineStation.extremes(from: w.start, to: w.end)
        let ranges = all.ranges()
        let chosen = pick?(ranges) ?? ranges.sorted { $0.height < $1.height }[ranges.count / 2]
        return PeakStanding.at(chosen.height, time: chosen.time, among: PeakStanding.swings(all), window: w)!
    }

    /// One bar per station-local day, not per swing. Every swing buries the
    /// fortnightly beat under the diurnal inequality: consecutive rises and
    /// falls alternate large and small, four times a day against a beat that
    /// turns over a fortnight. Measured on real Friday Harbor predictions the
    /// daily maximum runs 1.8 → 3.7 → 1.9 → 3.0 → 1.8 ft across the window,
    /// while the per-swing series shows no beat at all.
    func testRangeOutlookShowsSevenDaysFromItsWeek() throws {
        let week = dayLocal(at, station.tz)
        let timeline = TimelineData.build(tide: station, current: nil, now: at, anchor: week)
        let days = RangeOutlook.days(timeline, week: week)
        XCTAssertEqual(days.count, 7)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        for (offset, day) in days.enumerated() {
            XCTAssertEqual(day.start, cal.date(byAdding: .day, value: offset, to: week))
            let peak = try XCTUnwrap(day.peak)
            XCTAssertEqual(cal.startOfDay(for: peak.time), day.start)
            let biggest = PeakStanding.swings(timeline.tideExtremes)
                .filter { cal.isDate($0.time, inSameDayAs: day.start) }
                .map(\.magnitude).max()
            XCTAssertEqual(peak.magnitude, try XCTUnwrap(biggest))
        }
    }

    func testRangeOutlookFollowsDistantTimelineDatesAndDST() throws {
        for text in ["2027-01-02T12:00:00Z", "2026-11-01T12:00:00Z"] {
            let week = dayLocal(ISO8601DateFormatter().date(from: text)!, station.tz)
            let timeline = TimelineData.build(tide: station, current: nil, now: at, anchor: week)
            let days = RangeOutlook.days(timeline, week: week)
            XCTAssertEqual(days.count, 7)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = station.tz
            for (offset, day) in days.enumerated() {
                XCTAssertEqual(day.start, calendar.date(byAdding: .day, value: offset, to: week))
                XCTAssertEqual(calendar.startOfDay(for: try XCTUnwrap(day.peak).time), day.start)
            }
        }
    }

    /// A day the loaded timeline does not yet hold keeps its slot empty, so
    /// the bars either side of it stay where they stood.
    func testRangeOutlookKeepsAnUnloadedDaysSlot() throws {
        let anchor = dayLocal(at, station.tz)
        let timeline = TimelineData.build(tide: station, current: nil, now: at, anchor: anchor)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let week = try XCTUnwrap(cal.date(byAdding: .day, value: 5, to: anchor))
        let days = RangeOutlook.days(timeline, week: week)
        XCTAssertEqual(days.count, 7)
        XCTAssertNotNil(days.first?.peak)
        XCTAssertNil(days.last?.peak, "the timeline ends before the week does")
    }

    private func noon(_ offset: Int, from week: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        return noonLocal(cal.date(byAdding: .day, value: offset, to: week)!, station.tz)
    }

    func testRangeOutlookPreservesSmallRangeDifferencesAboveTheWeekdayLabel() {
        let small = RangeOutlook.barHeight(magnitude: 0.5, biggest: 4, height: 52)
        let larger = RangeOutlook.barHeight(magnitude: 1.5, biggest: 4, height: 52)
        XCTAssertEqual(small, 24)
        XCTAssertEqual(larger, 32)
        XCTAssertEqual(RangeOutlook.barHeight(magnitude: 4, biggest: 4, height: 52), 52)
        XCTAssertEqual(RangeOutlook.barHeight(magnitude: 1, biggest: 4, height: 12), 12)
    }

    private func day(_ offset: Int, from week: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        return cal.date(byAdding: .day, value: offset, to: week)!
    }

    /// The bars stand still while the scrub walks the week's first five days;
    /// only the highlight moves.
    func testTheWeekHoldsThroughItsFirstFiveDays() {
        let week = dayLocal(at, station.tz)
        for offset in 0..<5 {
            XCTAssertEqual(RangeOutlook.week(from: week, scrub: noon(offset, from: week), tz: station.tz),
                           week, "day \(offset + 1)")
        }
    }

    /// The sixth day leaves one day of outlook, so a new week starts there.
    func testTheSixthDayStartsANewWeek() {
        let week = dayLocal(at, station.tz)
        for offset in [5, 6, 9, 30] {
            let next = RangeOutlook.week(from: week, scrub: noon(offset, from: week), tz: station.tz)
            XCTAssertEqual(next, day(offset, from: week))
            XCTAssertEqual(RangeOutlook.week(from: next, scrub: noon(offset, from: week), tz: station.tz),
                           next, "a new week holds where it started")
        }
    }

    /// Scrubbing back past the week lands on the new week's fifth day, so the
    /// way back walks five days before the bars move again, as the way forward does.
    func testScrubbingBehindTheWeekLandsOnItsFifthDay() {
        let week = dayLocal(at, station.tz)
        for offset in [-1, -3, -20] {
            let next = RangeOutlook.week(from: week, scrub: noon(offset, from: week), tz: station.tz)
            XCTAssertEqual(next, day(offset - 4, from: week))
            XCTAssertEqual(RangeOutlook.week(from: next, scrub: noon(offset, from: week), tz: station.tz),
                           next, "a new week holds where it started")
        }
    }

    func testWithNoWeekTheScrubsDayStartsOne() {
        let scrub = noon(3, from: dayLocal(at, station.tz))
        XCTAssertEqual(RangeOutlook.week(from: nil, scrub: scrub, tz: station.tz), dayLocal(scrub, station.tz))
    }

    /// Across the November fall-back, five 86,400-second days from the week's
    /// midnight is 23:00 on its fifth day, an hour short of the sixth.
    func testTheSixthDayIsACalendarDayAcrossDST() {
        let week = dayLocal(ISO8601DateFormatter().date(from: "2026-10-29T19:00:00Z")!, station.tz)
        let lateOnTheFifthDay = day(5, from: week).addingTimeInterval(-30 * 60)
        XCTAssertEqual(RangeOutlook.week(from: week, scrub: lateOnTheFifthDay, tz: station.tz), week)
        XCTAssertEqual(RangeOutlook.week(from: week, scrub: day(5, from: week).addingTimeInterval(30 * 60),
                                         tz: station.tz),
                       day(5, from: week))
    }

    func testOneBarPerDayNotPerSwing() {
        let s = standing()
        XCTAssertGreaterThan(s.all.count, 90, "a fortnight either side is ~99 swings")
        XCTAssertEqual(SwingFigure.bars(s, tz: station.tz, size: size).count, 30,
                       "thirty whole local days")
    }

    /// The window runs local midnight to local midnight, so anything after its
    /// last midnight is a fragment — at Friday Harbor a 0.1 ft swing, which
    /// would draw as a collapse to nothing at the right-hand edge.
    func testThePartialEndDayIsDropped() {
        let bars = SwingFigure.bars(standing(), tz: station.tz, size: size)
        let shortest = bars.map(\.height).min()!, tallest = bars.map(\.height).max()!
        XCTAssertGreaterThan(shortest / tallest, 0.25,
                             "a bar collapsed to nothing means a partial day slipped in")
    }

    /// The bar carries the day's biggest swing, which at a mixed station may
    /// not be the selected one — so the marked bar can stand taller than the
    /// caption's number. What must hold is that the mark lands on the right DAY.
    func testTheSelectedDayIsMarkedExactlyOnce() {
        XCTAssertEqual(SwingFigure.bars(standing(), tz: station.tz, size: size)
            .filter(\.isSelected).count, 1)
    }

    func testBarHeightsShareOneScale() {
        let bars = SwingFigure.bars(standing(), tz: station.tz, size: size)
        XCTAssertEqual(bars.map(\.height).max()!, size.height, accuracy: 0.5,
                       "the biggest day fills the box")
    }

    /// The fact worth tapping, and it has to be ahead — a bigger swing last
    /// week is not something a reader can go and use.
    func testTheNextBiggerDayIsFlaggedAheadOfTheSelection() throws {
        let s = standing { $0.sorted { $0.height < $1.height }[$0.count / 3] }
        let bars = SwingFigure.bars(s, tz: station.tz, size: size)
        let selected = try XCTUnwrap(bars.first(where: \.isSelected))
        let flagged = try XCTUnwrap(bars.first(where: \.isNextBigger))
        XCTAssertGreaterThan(flagged.x, selected.x)
    }

    func testTheBiggestSwingFlagsNothingAhead() {
        let s = standing { $0.max { $0.height < $1.height }! }
        XCTAssertFalse(SwingFigure.bars(s, tz: station.tz, size: size).contains(where: \.isNextBigger))
    }

    func testBarsSpanTheBoxInTimeOrder() {
        let bars = SwingFigure.bars(standing(), tz: station.tz, size: size)
        XCTAssertEqual(bars.map(\.x), bars.map(\.x).sorted())
        XCTAssertLessThan(bars.first!.x, size.width * 0.1)
        XCTAssertGreaterThan(bars.last!.x, size.width * 0.9)
    }

    /// A finger lifted on a bar goes to that bar's own swing, so each bar
    /// carries its peak rather than only its day.
    func testEachBarCarriesItsDaysBiggestSwing() {
        let s = standing()
        let bars = SwingFigure.bars(s, tz: station.tz, size: size)
        let peaks = SwingFigure.dailyPeaks(s, tz: station.tz)
        XCTAssertEqual(bars.map(\.peak), peaks)
    }

    /// A drag that leaves the canvas still lands on the nearest edge bar.
    func testTheBarUnderAnXIsFoundAndClampedAtBothEdges() {
        XCTAssertEqual(SwingFigure.barIndex(atX: 0, count: 30, width: 300), 0)
        XCTAssertEqual(SwingFigure.barIndex(atX: 15, count: 30, width: 300), 1)
        XCTAssertEqual(SwingFigure.barIndex(atX: 299, count: 30, width: 300), 29)
        XCTAssertEqual(SwingFigure.barIndex(atX: -40, count: 30, width: 300), 0)
        XCTAssertEqual(SwingFigure.barIndex(atX: 900, count: 30, width: 300), 29)
        XCTAssertNil(SwingFigure.barIndex(atX: 10, count: 0, width: 300))
    }

    /// The beat the bars show is the moon's, so each phase in the window is
    /// drawn under the bar of the station-local day it falls on.
    func testEachPhaseLandsOnItsDaysBar() throws {
        let s = standing()
        let peaks = SwingFigure.dailyPeaks(s, tz: station.tz)
        let all = SwingFigure.moonPhases(in: s.window).sorted { $0.time < $1.time }
        XCTAssertTrue(all.contains { $0.time < s.window.start } && all.contains { $0.time >= s.window.end },
                      "the search reaches past the window, for the edge days' nearest phase")
        let phases = all.filter { $0.time >= s.window.start && $0.time < s.window.end }
        XCTAssertGreaterThanOrEqual(phases.count, 3, "a 30-day window holds four or five phases, three at the least")
        let marks = SwingFigure.phaseMarks(all, peaks: peaks, tz: station.tz)
        XCTAssertEqual(marks.count, phases.count, "every phase inside the whole days has a bar, and none outside does")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        // Marks come back in time order, so the i-th mark is the i-th phase —
        // matching by kind would pair the wrong instants in a window holding
        // the same phase twice.
        for (mark, phase) in zip(marks, phases) {
            XCTAssertEqual(mark.phase, phase.phase)
            XCTAssertEqual(cal.startOfDay(for: peaks[mark.index].time), cal.startOfDay(for: phase.time))
        }
        XCTAssertEqual(marks.map(\.index), marks.map(\.index).sorted(), "in time order")
    }

    /// The caption claims springs follow the new and full moon only where the
    /// bars bear it out. Friday Harbor's do; a series that peaks at the
    /// quarters instead — the shape of a diurnal station's declinational
    /// beat — does not get the sentence.
    func testTheMoonSentenceIsEarnedByTheBars() {
        let s = standing()
        let peaks = SwingFigure.dailyPeaks(s, tz: station.tz)
        let phases = SwingFigure.moonPhases(in: s.window)
        XCTAssertTrue(SwingFigure.springsFollowThePhases(peaks: peaks, phases: phases))
        let quarters = phases.filter { $0.phase == .firstQuarter || $0.phase == .lastQuarter }.map(\.time)
        let syzygies = phases.filter { $0.phase == .new || $0.phase == .full }.map(\.time)
        func nearest(_ t: Date, _ e: [Date]) -> TimeInterval { e.map { abs($0.timeIntervalSince(t)) }.min()! }
        let inverted = peaks.map {
            Peak(time: $0.time, magnitude: nearest($0.time, quarters) < nearest($0.time, syzygies) ? 3 : 1)
        }
        XCTAssertFalse(SwingFigure.springsFollowThePhases(peaks: inverted, phases: phases))
        XCTAssertFalse(SwingFigure.springsFollowThePhases(peaks: peaks, phases: []), "no phases, no claim")
    }

    /// VoiceOver steps one bar at a time from the selected day, never past
    /// either end.
    func testVoiceOverStepsAlongTheBarsFromTheSelection() {
        XCTAssertEqual(SwingFigure.step(nil, from: 12, by: 1, count: 30), 13)
        XCTAssertEqual(SwingFigure.step(nil, from: 12, by: -1, count: 30), 11)
        XCTAssertEqual(SwingFigure.step(13, from: 12, by: 1, count: 30), 14)
        XCTAssertEqual(SwingFigure.step(29, from: 12, by: 1, count: 30), 29)
        XCTAssertEqual(SwingFigure.step(0, from: 12, by: -1, count: 30), 0)
        XCTAssertEqual(SwingFigure.step(nil, from: 0, by: -1, count: 0), 0)
    }

    /// A phase on a day with no bar — the window's dropped fragment — draws
    /// nothing rather than landing on a neighbour.
    func testAPhaseOnADayWithoutABarDrawsNothing() throws {
        let s = standing()
        let peaks = SwingFigure.dailyPeaks(s, tz: station.tz)
        let phase = try XCTUnwrap(SwingFigure.moonPhases(in: s.window).first { $0.time >= s.window.start })
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let day = cal.startOfDay(for: phase.time)
        let without = peaks.filter { cal.startOfDay(for: $0.time) != day }
        XCTAssertEqual(without.count, peaks.count - 1, "the phase's own day had a bar to remove")
        XCTAssertEqual(SwingFigure.phaseMarks([phase], peaks: without, tz: station.tz), [])
    }

    /// A finger that goes up or down the sheet is scrolling it, not sliding
    /// along the bars, so lifting after a vertical swipe does not jump. A
    /// slide that drifts upward still does.
    func testAVerticalSwipeIsAScrollNotASlide() {
        XCTAssertTrue(SwingFigure.slideJumps(CGSize(width: 0, height: 0)), "a tap")
        XCTAssertTrue(SwingFigure.slideJumps(CGSize(width: 80, height: 0)), "a slide")
        XCTAssertTrue(SwingFigure.slideJumps(CGSize(width: 60, height: -40)), "a slide that drifts up")
        XCTAssertTrue(SwingFigure.slideJumps(CGSize(width: 0, height: -12)), "a wobble under the threshold")
        XCTAssertFalse(SwingFigure.slideJumps(CGSize(width: 4, height: -60)), "a swipe up")
        XCTAssertFalse(SwingFigure.slideJumps(CGSize(width: -10, height: 90)), "a swipe down")
        XCTAssertFalse(SwingFigure.slideJumps(CGSize(width: 30, height: 50)), "a diagonal scroll")
    }

    /// With nowhere to go, a finger on the bars does nothing: no lit bar and
    /// no sheet closing under it.
    func testWithoutAJumpTheBarsIgnoreTouches() {
        XCTAssertFalse(SwingFigure(standing: standing(), tz: station.tz).respondsToTouch)
        XCTAssertTrue(SwingFigure(standing: standing(), tz: station.tz, onJump: { _ in }).respondsToTouch)
    }
}
