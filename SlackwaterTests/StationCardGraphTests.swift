import XCTest
import SwiftUI
import SlackwaterKit
@testable import Slackwater

final class StationCardGraphTests: XCTestCase {
    @MainActor
    func testFortCaswellRelaxationHangsOppositeItsNeighbouringEbbs() throws {
        let record = try XCTUnwrap(CurrentStationRecord.all.first { $0.name.contains("Fort Caswell") })
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T14:00:00Z"))
        let afternoonStart = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T17:00:00Z"))
        let graph = record.cardGraph(at: now, unit: "kn")
        let afternoon = graph.extremes.filter { $0.time >= afternoonStart
            && $0.time <= afternoonStart.addingTimeInterval(4 * 3600) }
        let image = try XCTUnwrap(ImageRenderer(content: graph.frame(width: 356, height: 114)
            .background(SN.canvas).preferredColorScheme(.dark)).uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "fort-caswell-card"
        attachment.lifetime = .keepAlways
        add(attachment)
        var bare = graph
        bare.showsReadings = false
        let background = try XCTUnwrap(ImageRenderer(content: bare.frame(width: 356, height: 114)
            .background(SN.canvas).preferredColorScheme(.dark)).uiImage)
        // This patch is below the lull; both neighbouring ebb readings hang above the curve.
        let belowLull = CGRect(x: 201, y: 88, width: 25, height: 20)
        let readingPixels = try XCTUnwrap(image.cgImage?.cropping(to: belowLull)?.dataProvider?.data) as Data
        let barePixels = try XCTUnwrap(background.cgImage?.cropping(to: belowLull)?.dataProvider?.data) as Data
        XCTAssertNotEqual(readingPixels, barePixels, "the lull's reading must actually draw below the curve after the edge flip")
        XCTAssertEqual(afternoon.count, 3)
        XCTAssertTrue(afternoon.allSatisfy { $0.value < 0 })
        XCTAssertEqual(afternoon.map(\.high), [false, true, false],
                       "the relaxation crest must hang below the curve, between two ebb troughs hanging above")
        XCTAssertTrue(afternoon.allSatisfy { $0.deg == record.ebbDirection })
    }

    func testCardSpeedInterpolatesAndRejectsAMissingApproach() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let points = [CurrentPoint(time: start, speed: -1.1),
                      CurrentPoint(time: start.addingTimeInterval(600), speed: -0.85)]
        XCTAssertEqual(try XCTUnwrap(cardSpeed(points, at: start.addingTimeInterval(300))), -0.975, accuracy: 0.000001)
        XCTAssertEqual(cardSpeed(points, at: start), -1.1)
        XCTAssertEqual(cardSpeed(points, at: start.addingTimeInterval(600)), -0.85)
        XCTAssertNil(cardSpeed(points, at: start.addingTimeInterval(-1)))
        XCTAssertNil(cardSpeed(points, at: start.addingTimeInterval(601)))
        XCTAssertNil(cardSpeed([], at: start))
    }

    func testOnlinePeaksKeepTheirSidesAndBearings() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        for speeds in [[0.0, 1, 2, 1, 0, -1, -2, -1, 0],
                       [2.0, 2, 2, 2, 0, -2, -2, -2, 0]] {
            let times = speeds.indices.map { now.addingTimeInterval(Double($0) * 600).timeIntervalSince1970 }
            let model = ChsOnlineWindow(stationID: "test", iwlsName: "Test", timezone: "UTC", fetchedAt: now,
                                        start: now, end: Date(timeIntervalSince1970: times.last!),
                                        floodDirection: 90, ebbDirection: 270, times: times, speeds: speeds)
            let graph = model.cardGraph(at: now, unit: "kn")
            XCTAssertEqual(graph.extremes.map(\.high), [true, false])
            XCTAssertEqual(graph.extremes.map(\.deg), [90, 270])
        }
    }

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
