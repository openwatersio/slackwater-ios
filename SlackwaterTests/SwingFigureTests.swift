import XCTest
import SlackwaterKit
@testable import Slackwater

/// Section 1's figure: every swing in the fortnight as a bar on a time axis.
/// The spring/neap beat IS the answer to "is this beyond normal", so the
/// layout's job is to keep that beat readable and put the reader on it.
final class SwingFigureTests: XCTestCase {
    private let station = TideStationRecord.record(id: TideStationRecord.fridayHarborID)!
    private let at = Date(timeIntervalSince1970: 1_780_000_000)
    private let size = CGSize(width: 320, height: 120)

    private func standing(pick: (([TideRange]) -> TideRange)? = nil) -> SwingStanding {
        let w = TideStanding.window(around: at, tz: station.tz)
        let all = station.engineStation.extremes(from: w.start, to: w.end)
        let ranges = all.ranges()
        let chosen = pick?(ranges) ?? ranges.sorted { $0.height < $1.height }[ranges.count / 2]
        return SwingStanding.at(chosen.height, time: chosen.time, among: all)!
    }

    func testEverySwingGetsABar() {
        let s = standing()
        XCTAssertEqual(SwingFigure.bars(s, size: size).count, s.all.count)
        XCTAssertGreaterThan(s.all.count, 40, "a fortnight either side is ~58 swings")
    }

    func testBarHeightsShareOneScale() {
        let s = standing()
        let bars = SwingFigure.bars(s, size: size)
        let tallest = bars.max { $0.height < $1.height }!
        let biggest = s.all.max { $0.height < $1.height }!
        XCTAssertEqual(tallest.height, size.height, accuracy: 0.5, "the biggest swing fills the box")
        let half = s.all.min { abs($0.height - biggest.height / 2) < abs($1.height - biggest.height / 2) }!
        let halfBar = bars[s.all.firstIndex { $0.time == half.time }!]
        XCTAssertEqual(halfBar.height / tallest.height, half.height / biggest.height, accuracy: 0.02)
    }

    func testTheSelectedSwingIsMarkedExactlyOnce() {
        let bars = SwingFigure.bars(standing(), size: size)
        XCTAssertEqual(bars.filter(\.isSelected).count, 1)
    }

    /// The fact worth tapping, and it has to be ahead — a bigger swing last
    /// week is not something a reader can go and use.
    func testTheNextBiggerSwingIsFlaggedAheadOfTheSelection() {
        let s = standing { $0.sorted { $0.height < $1.height }[$0.count / 3] }
        let bars = SwingFigure.bars(s, size: size)
        let selected = bars.first(where: \.isSelected)!
        let flagged = bars.first(where: \.isNextBigger)!
        XCTAssertGreaterThan(flagged.x, selected.x)
        XCTAssertGreaterThan(flagged.height, selected.height)
    }

    /// Nothing to flag when this swing is the fortnight's biggest.
    func testTheBiggestSwingFlagsNothingAhead() {
        let s = standing { $0.max { $0.height < $1.height }! }
        XCTAssertFalse(SwingFigure.bars(s, size: size).contains(where: \.isNextBigger))
    }

    func testBarsSpanTheBoxInTimeOrder() {
        let bars = SwingFigure.bars(standing(), size: size)
        XCTAssertEqual(bars.map(\.x), bars.map(\.x).sorted())
        XCTAssertLessThan(bars.first!.x, size.width * 0.1)
        XCTAssertGreaterThan(bars.last!.x, size.width * 0.9)
    }
}
