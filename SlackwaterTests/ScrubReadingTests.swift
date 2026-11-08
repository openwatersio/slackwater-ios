// Slackwater — GPL v3. The watch card's words at a scrub time (#522).
import XCTest
@testable import Slackwater
import SlackwaterKit

final class ScrubReadingTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func tide() throws -> TimelineData {
        let r = try XCTUnwrap(TideStationRecord.record(id: TideStationRecord.fridayHarborID))
        return TimelineData.build(tide: r, current: nil, now: at, anchor: at)
    }

    private func current() throws -> TimelineData {
        let r = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/PUG1515"))
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

    /// The Crown says Slack exactly where the strip draws slack, so weak water off a slack is still moving.
    func testSlackIsTheStripsSlack() throws {
        let tl = try current()
        for minute in stride(from: 0, through: 24 * 60, by: 5) {
            let t = at.addingTimeInterval(Double(minute) * 60)
            let r = ScrubReading.at(t, in: tl, imperial: true, speedUnit: "kn")
            XCTAssertEqual(r.title == CurrentPhase.slack.word, tl.isSlack(at: t), "at +\(minute) min")
        }
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

    /// A one-axis station's set is its published bearing for the sign, in the chosen format. The engine carries those bearings on its samples, so the ones the watch passes stand in only for samples without a set (an online or derived gate's).
    func testACurrentReadsItsSet() throws {
        let (pollock, tl) = try timeline("noaa/ACT1616")
        let flood = try XCTUnwrap(tl.currentEvents.first { $0.kind == .maxFlood && $0.time > day })
        XCTAssertEqual(reading(flood.time, pollock, tl).set, compassPoint(pollock.floodDirection))
        let ebb = try XCTUnwrap(tl.currentEvents.first { $0.kind == .maxEbb && $0.time > day })
        XCTAssertEqual(reading(ebb.time, pollock, tl).set, compassPoint(pollock.ebbDirection))
        XCTAssertEqual(ScrubReading.at(ebb.time, in: tl, imperial: true, speedUnit: "kn", setFormat: "degrees",
                                       floodDeg: pollock.floodDirection, ebbDeg: pollock.ebbDirection).set,
                       formatSet(pollock.ebbDirection, format: "degrees"))
        XCTAssertNotEqual(compassPoint(pollock.floodDirection), compassPoint(pollock.ebbDirection))
    }

    // MARK: - The watch's tide direction

    /// The watch's 200-second reach is its own: a High reads High on both sides of the turn.
    func testAHundredSecondsEitherSideOfAHighReadsHigh() throws {
        let tl = try tide()
        let high = try XCTUnwrap(tl.tideExtremes.first { $0.kind == .high && $0.time > at })
        for offset in [-100.0, 100.0] {
            let r = ScrubReading.at(high.time.addingTimeInterval(offset), in: tl, imperial: true, speedUnit: "kn")
            XCTAssertEqual(r.title, "High", "\(offset) s")
            XCTAssertEqual(r.symbol, "arrow.up.to.line", "\(offset) s")
        }
    }

    func testAHundredSecondsBeforeALowReadsLow() throws {
        let tl = try tide()
        let low = try XCTUnwrap(tl.tideExtremes.first { $0.kind == .low && $0.time > at })
        let r = ScrubReading.at(low.time.addingTimeInterval(-100), in: tl, imperial: true, speedUnit: "kn")
        XCTAssertEqual(r.title, "Low")
        XCTAssertEqual(r.symbol, "arrow.down.to.line")
    }

    /// With no turn ahead the direction is the sampled rate's sign, not a default of rising.
    func testATideWithNoLaterTurnReadsByItsRate() {
        let hours = Array(-1...5)
        let tl = TimelineData(
            tz: TimeZone(identifier: "UTC")!, anchor: at, today: at,
            start: at.addingTimeInterval(-3600), end: at.addingTimeInterval(18_000),
            days: [],
            tidePoints: hours.map { TidePoint(time: at.addingTimeInterval(Double($0) * 3600), height: 2 - 0.2 * Double($0)) },
            tideRates: hours.map { TideRatePoint(time: at.addingTimeInterval(Double($0) * 3600), rate: -0.2) },
            tideExtremes: [],
            currentPoints: [], currentEvents: [], snapTimes: [], slackWindows: [])
        let r = ScrubReading.at(at.addingTimeInterval(3600), in: tl, imperial: true, speedUnit: "kn")
        XCTAssertEqual(r.title, "Falling")
        XCTAssertEqual(r.symbol, "arrow.down.right")
    }

    // MARK: - The watch's speed and set

    /// 2026-08-10 12:00 UTC, the day the detail lead's Kodiak and Pollock Rip tests read.
    private let day = Date(timeIntervalSince1970: 1_786_363_200)

    private func timeline(_ id: String) throws -> (CurrentStationRecord, TimelineData) {
        let r = try XCTUnwrap(CurrentStationRecord.record(id: id))
        return (r, TimelineData.build(tide: nil, current: r, now: day, anchor: day))
    }

    private func reading(_ t: Date, _ r: CurrentStationRecord, _ tl: TimelineData) -> ScrubReading {
        ScrubReading.at(t, in: tl, imperial: true, speedUnit: "kn", floodDeg: r.floodDirection, ebbDeg: r.ebbDirection)
    }

    /// Pollock Rip has no cross-flow constants, so the watch reads it exactly as before vectors: every third hour, each of the day's events, and half a minute after each slack.
    func testAOneAxisCurrentReadsAsItAlwaysHas() throws {
        let (pollock, tl) = try timeline("noaa/ACT1616")
        XCTAssertNil(pollock.minorConstituents, "the fixture is one-axis")
        let events = tl.currentEvents.filter { $0.time >= day && $0.time < day.addingTimeInterval(86_400) }
        let instants = (0..<8).map { day.addingTimeInterval(Double($0) * 3 * 3600 + 7) } + events.map(\.time)
            + events.filter { $0.kind == .slack }.map { $0.time.addingTimeInterval(30) }
        let readings = instants.map { t in
            let r = reading(t, pollock, tl)
            return [r.title, r.value ?? "nil", r.set ?? "nil"]
        }
        XCTAssertEqual(readings, [
            ["Ebbing", "0.1", "SW"], ["Ebbing", "1.4", "SW"], ["Flooding", "0.2", "NE"], ["Flooding", "1.6", "NE"],
            ["Flooding", "0.1", "NE"], ["Ebbing", "1.6", "SW"], ["Ebbing", "0.1", "SW"], ["Flooding", "2.0", "NE"],
            ["Ebbing", "1.4", "SW"], ["Slack", "0.0", "nil"], ["Flooding", "1.6", "NE"], ["Slack", "0.0", "nil"],
            ["Ebbing", "1.6", "SW"], ["Slack", "0.0", "nil"], ["Flooding", "2.1", "NE"],
            ["Flooding", "0.0", "NE"], ["Ebbing", "0.0", "SW"], ["Flooding", "0.0", "NE"],
        ])
    }

    /// Away from slack the watch prints Kodiak's full speed and points the water's own set, keeping its own word by the signed speed.
    func testARotaryCurrentReadsTheWatersSpeedAndSet() throws {
        let (kodiak, tl) = try timeline("noaa/KOD0901")
        XCTAssertNotNil(kodiak.minorConstituents, "the fixture is rotary")
        var departs = 0
        for hour in 0..<24 {
            let t = day.addingTimeInterval(Double(hour) * 3600 + 7)
            let v = try XCTUnwrap(tl.currentPoints.vector(at: t, flood: kodiak.floodDirection, ebb: kodiak.ebbDirection))
            let r = reading(t, kodiak, tl)
            XCTAssertEqual(r.title, tl.velocityAt(t) >= 0 ? "Flooding" : "Ebbing", "\(t)")
            XCTAssertEqual(r.value, formatSpeed(v.magnitude, unit: "kn"), "\(t)")
            XCTAssertEqual(r.set, v.direction.map(compassPoint), "\(t)")
            if r.value != formatSpeed(abs(tl.velocityAt(t)), unit: "kn") { departs += 1 }
        }
        XCTAssertGreaterThan(departs, 0, "the day's water leaves the major axis")
    }

    /// At a slack the watch still says Slack and prints the water's full speed; it names a set only while the crossing flow prints above zero.
    func testARotaryCurrentAtSlackKeepsItsWordAndShowsTheCrossingFlow() throws {
        let (kodiak, tl) = try timeline("noaa/KOD0901")
        let slacks = tl.currentEvents.filter { $0.kind == .slack && $0.time >= day && $0.time < day.addingTimeInterval(86_400) }
        XCTAssertFalse(slacks.isEmpty)
        var crossing = 0
        for slack in slacks {
            let v = try XCTUnwrap(tl.currentPoints.vector(at: slack.time, flood: kodiak.floodDirection, ebb: kodiak.ebbDirection))
            let speed = tl.velocityAt(slack.time)
            let r = reading(slack.time, kodiak, tl)
            XCTAssertEqual(r.title, "Slack", "\(slack.time)")
            XCTAssertEqual(r.value, formatSpeed(v.magnitude, unit: "kn"), "\(slack.time)")
            let across = max(0, v.magnitude * v.magnitude - speed * speed).squareRoot()
            if formatSpeed(across, unit: "kn") == "0.0" {
                XCTAssertNil(r.set, "\(slack.time)")
            } else {
                crossing += 1
                XCTAssertEqual(r.set, compassPoint(try XCTUnwrap(v.direction)), "\(slack.time)")
            }
        }
        XCTAssertGreaterThan(crossing, 0, "the water still crosses at one of the day's slacks")
    }
}
