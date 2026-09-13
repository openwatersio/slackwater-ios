// Slackwater — GPL v3. The pure pieces alert occurrences are built from.
import XCTest
@testable import Slackwater
import TideEngine

final class AlertPrimitivesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testCrossingsInterpolateInTheRequestedDirection() {
        let samples: [(time: Date, height: Double)] = [(at(0), 0), (at(600), 2), (at(1200), 0)]
        let up = tideCrossings(samples, level: 1, rising: true)
        let down = tideCrossings(samples, level: 1, rising: false)
        XCTAssertEqual(up.count, 1)
        XCTAssertEqual(up[0].timeIntervalSince(t0), 300, accuracy: 1)
        XCTAssertEqual(down.count, 1)
        XCTAssertEqual(down[0].timeIntervalSince(t0), 900, accuracy: 1)
    }

    func testASampleExactlyOnTheLevelCountsOnce() {
        let samples: [(time: Date, height: Double)] = [(at(0), 0), (at(600), 1), (at(1200), 2)]
        XCTAssertEqual(tideCrossings(samples, level: 1, rising: true).map { $0.timeIntervalSince(t0) }, [600])
    }

    func testDaylightSpansFollowTheSunAcrossTheDSTChange() throws {
        // Friday Harbor. US clocks fall back at 02:00 local on 2026-11-01.
        let iso = ISO8601DateFormatter()
        let from = try XCTUnwrap(iso.date(from: "2026-11-01T08:00:00Z"))
        let spans = daylightSpans(from: from, to: from.addingTimeInterval(86_400), lat: 48.545, lon: -123.013)
        let noonPST = try XCTUnwrap(iso.date(from: "2026-11-01T20:00:00Z"))
        let predawnPST = try XCTUnwrap(iso.date(from: "2026-11-01T09:30:00Z"))
        XCTAssertTrue(spans.contains { $0.contains(noonPST) })
        XCTAssertFalse(spans.contains { $0.contains(predawnPST) })
        // A day of padding either side: Oct 31, Nov 1, Nov 2.
        XCTAssertEqual(spans.count, 3)
    }

    /// Two slacks whose windows touch, then a hairline slack no sample under the
    /// threshold brackets.
    private struct FakeCurrent: CurrentPredicting {
        let points: [CurrentPoint]
        let slacks: [Date]
        func speeds(from: Date, to: Date, step: TimeInterval) -> [CurrentPoint] { points }
        func events(from: Date, to: Date) -> [CurrentEvent] {
            slacks.map { CurrentEvent(time: $0, speed: 0, kind: .slack) }
        }
    }

    func testMergedWindowsOpenOnceAndAHairlineSlackStandsAlone() {
        let speeds: [Double] = [2, 1.5, 1, 0.6, 0.3, 0.1, 0,   // 0…3600: slack A at 3600
                                0.1, 0.3, 0,                   // 4200…5400: slack B at 5400
                                0.3, 0.6, 1, 1.5, 1.2, 1.1, 1, // 6000…9600
                                1, 0.8, -1, -1.5, -2]          // 10200…12600: hairline at 10800
        let points = speeds.enumerated().map { CurrentPoint(time: at(Double($0.offset) * 600), speed: $0.element) }
        let station = FakeCurrent(points: points, slacks: [at(3600), at(5400), at(10_800)])

        let openings = slackWindowOpenings(station, from: t0, to: at(12_600), threshold: 0.5)

        XCTAssertEqual(openings.count, 2)
        XCTAssertEqual(openings[0].event.timeIntervalSince(t0), 2000, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(openings[0].end).timeIntervalSince(t0), 6400, accuracy: 1)
        XCTAssertEqual(openings[1].event, at(10_800))
        XCTAssertNil(openings[1].end)
    }
}
