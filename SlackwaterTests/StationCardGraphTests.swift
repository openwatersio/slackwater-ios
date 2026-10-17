import XCTest
@testable import Slackwater

final class StationCardGraphTests: XCTestCase {
    /// The watch complication's canvas: 60 pt tall, times along the bottom.
    private let time = StationCardGraph.axisTimeInk(at: 80, width: 40, height: 60)

    func testAPointerOnTheTimeRowCollidesThoughItsValueHangsPast() {
        // A turn low enough that the pointer lands on the time and the
        // value hangs wholly below it.
        let dot = CGPoint(x: 80, y: 35)
        let reading = StationCardGraph.hangingInk(below: dot, valueWidth: 24)
        XCTAssertGreaterThan(reading.maxY - CurveStyle.hangValueFontSize, time.maxY,
                             "the value's ink starts below the time's")
        XCTAssertTrue(reading.intersects(time))
    }

    func testAValuelessPointerStillCollides() {
        // A derived gate's flow arrow carries no value.
        let reading = StationCardGraph.hangingInk(below: CGPoint(x: 80, y: 35), valueWidth: nil)
        XCTAssertTrue(reading.intersects(time))
    }

    func testAReadingOffAHighTurnClearsTheTimes() {
        // The watch's full-range high: the reading sits just above the row.
        let reading = StationCardGraph.hangingInk(below: CGPoint(x: 80, y: 9), valueWidth: 30)
        XCTAssertFalse(reading.intersects(time))
    }
}
