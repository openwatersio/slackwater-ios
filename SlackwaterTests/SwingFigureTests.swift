import XCTest
import SlackwaterKit
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
    func testRangeOutlookShowsTheSelectedDayAndSixComingDays() throws {
        let timeline = TimelineData.build(tide: station, current: nil, now: at,
                                          anchor: dayLocal(at, station.tz))
        let peaks = RangeOutlook.peaks(timeline, at: at)
        XCTAssertEqual(peaks.count, 7)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        let start = cal.startOfDay(for: at)
        for (offset, peak) in peaks.enumerated() {
            let day = cal.date(byAdding: .day, value: offset, to: start)!
            XCTAssertEqual(cal.startOfDay(for: peak.time), day)
            let biggest = PeakStanding.swings(timeline.tideExtremes)
                .filter { cal.isDate($0.time, inSameDayAs: day) }
                .map(\.magnitude).max()
            XCTAssertEqual(peak.magnitude, try XCTUnwrap(biggest))
        }
    }

    func testRangeOutlookFollowsDistantTimelineDatesAndDST() throws {
        for text in ["2027-01-02T12:00:00Z", "2026-11-01T12:00:00Z"] {
            let date = ISO8601DateFormatter().date(from: text)!
            let timeline = TimelineData.build(tide: station, current: nil, now: at,
                                              anchor: dayLocal(date, station.tz))
            let peaks = RangeOutlook.peaks(timeline, at: date)
            XCTAssertEqual(peaks.count, 7)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = station.tz
            let start = calendar.startOfDay(for: date)
            for (offset, peak) in peaks.enumerated() {
                XCTAssertEqual(calendar.startOfDay(for: peak.time),
                               calendar.date(byAdding: .day, value: offset, to: start))
            }
        }
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
}
