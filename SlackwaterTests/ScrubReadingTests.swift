// Slackwater — GPL v3. The watch card's words at a scrub time (#522).
import XCTest
@testable import Slackwater

final class ScrubReadingTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func tide() throws -> TimelineData {
        let r = try XCTUnwrap(TideStationRecord.record(id: TideStationRecord.fridayHarborID))
        return TimelineData.build(tide: r, current: nil, now: at, anchor: at)
    }

    private func current() throws -> TimelineData {
        let r = try XCTUnwrap(CurrentStationRecord.byId["noaa/PUG1515"])
        return TimelineData.build(tide: nil, current: r, now: at, anchor: at)
    }

    func testBetweenALowAndAHighReadsRising() throws {
        let tl = try tide()
        let pair = try XCTUnwrap(zip(tl.tideExtremes, tl.tideExtremes.dropFirst())
            .first { $0.0.kind == .low && $0.0.time > at })
        let mid = pair.0.time.addingTimeInterval(pair.1.time.timeIntervalSince(pair.0.time) / 2)
        let r = ScrubReading.at(mid, in: tl, imperial: true, speedUnit: "kn")
        XCTAssertEqual(r.title, "Rising")
        XCTAssertEqual(r.unit, "ft")
        XCTAssertTrue(r.next?.hasPrefix("High") == true, r.next ?? "nil")
    }

    func testAtATurnReadsItsName() throws {
        let tl = try tide()
        let high = try XCTUnwrap(tl.tideExtremes.first { $0.kind == .high && $0.time > at })
        XCTAssertEqual(ScrubReading.at(high.time, in: tl, imperial: true, speedUnit: "kn").title, "High")
    }

    func testNextSkipsTheEventUnderTheScrub() throws {
        let tl = try tide()
        let high = try XCTUnwrap(tl.tideExtremes.first { $0.kind == .high && $0.time > at })
        let r = ScrubReading.at(high.time, in: tl, imperial: true, speedUnit: "kn")
        XCTAssertTrue(r.next?.hasPrefix("Low") == true, r.next ?? "nil")
    }

    func testAtAMaxFloodReadsFloodingWithSpeed() throws {
        let tl = try current()
        let flood = try XCTUnwrap(tl.currentEvents.first { $0.kind == .maxFlood && $0.time > at })
        let r = ScrubReading.at(flood.time, in: tl, imperial: true, speedUnit: "kn")
        XCTAssertEqual(r.title, "Flooding")
        XCTAssertNotNil(r.value)
        XCTAssertEqual(r.unit, "kn")
    }

    func testSchematicCurrentHasNoValue() throws {
        var tl = try current()
        tl.speedsAreSchematic = true
        let r = ScrubReading.at(at.addingTimeInterval(3_600), in: tl, imperial: true, speedUnit: "kn")
        XCTAssertNil(r.value)
        XCTAssertNil(r.unit)
    }

    func testTodaysEventsAreAfterTheScrubAndOnItsDay() throws {
        let tl = try tide()
        let events = ScrubReading.todaysEvents(after: at, in: tl, imperial: true, speedUnit: "kn")
        XCTAssertLessThanOrEqual(events.count, 4)
        XCTAssertTrue(events.allSatisfy { $0.hasPrefix("High") || $0.hasPrefix("Low") }, "\(events)")
    }

    /// A Crown at rest within 0.5 pt of a turn (about 100 s) is not snapped,
    /// and still sits on the turn: the card must call it the turn.
    func testRestingJustShortOfATurnReadsTheTurn() throws {
        let tl = try tide()
        let high = try XCTUnwrap(tl.tideExtremes.first { $0.kind == .high && $0.time > at })
        let r = ScrubReading.at(high.time.addingTimeInterval(-80), in: tl, imperial: true, speedUnit: "kn")
        XCTAssertEqual(r.title, "High")
        XCTAssertTrue(r.next?.hasPrefix("Low") == true, r.next ?? "nil")
    }

    func testACurrentReadsItsSet() throws {
        let tl = try current()
        let flood = try XCTUnwrap(tl.currentEvents.first { $0.kind == .maxFlood && $0.time > at })
        let r = ScrubReading.at(flood.time, in: tl, imperial: true, speedUnit: "kn", floodDeg: 225, ebbDeg: 45)
        XCTAssertEqual(r.set, "SW")
        let ebb = try XCTUnwrap(tl.currentEvents.first { $0.kind == .maxEbb && $0.time > at })
        XCTAssertEqual(ScrubReading.at(ebb.time, in: tl, imperial: true, speedUnit: "kn",
                                       floodDeg: 225, ebbDeg: 45).set, "NE")
    }
}
