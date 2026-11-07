import CoreLocation
import MapLibre
import SlackwaterKit
import XCTest
import Synchronization
@testable import Slackwater

final class CurrentDirectionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_787_000_000)
    private let gate = CurrentStationRecord(
        id: "chs-dodd-narrows", name: "Dodd Narrows", region: "Nanaimo", aliases: [],
        latitude: 49.1344, longitude: -123.8171, timezone: "America/Vancouver",
        // Dodd's published bearings, which are not reciprocal: 355's reciprocal would be 175.
        floodDirection: 355, ebbDirection: 155, meanFlow: 0, tideReference: nil, constituents: [])

    private func cell(_ bearing: Double = 73) -> FillCell {
        FillCell(polygon: [
            .init(latitude: 48.0, longitude: -123.0),
            .init(latitude: 48.0, longitude: -122.7),
            .init(latitude: 48.3, longitude: -123.0),
        ], speedKn: 2.5, bearingDeg: bearing)
    }

    func testCellProducesPolygonAndCentroidDirection() throws {
        let features = currentCellFeatures([cell()])
        XCTAssertEqual(features.count, 2)
        XCTAssertTrue(features[0] is MLNPolygonFeature)
        let point = try XCTUnwrap(features[1] as? MLNPointFeature)
        XCTAssertEqual(point.coordinate.latitude, 48.1, accuracy: 1e-12)
        XCTAssertEqual(point.coordinate.longitude, -122.9, accuracy: 1e-12)
        let bearing = try XCTUnwrap(point.attribute(forKey: "bearing") as? NSNumber)
        XCTAssertEqual(bearing.doubleValue, 73)
    }

    func testPatchCoverageSuppressesBackdropDirectionButNotPolygon() {
        let features = currentCellFeatures([cell()], excludingDirectionsIn: [cell(201)])
        XCTAssertEqual(features.count, 1)
        XCTAssertTrue(features[0] is MLNPolygonFeature)
    }

    func testDoddUsesAbsoluteSpeedAndPublishedEbbBearing() throws {
        let evaluations = Mutex(0)
        let provider = DoddMapFlowProvider(gate: gate, signedSpeed: { _ in
            evaluations.withLock { $0 += 1 }
            return -6
        })
        let flow = try XCTUnwrap(provider.flow(at: date))
        XCTAssertEqual(evaluations.withLock { $0 }, 1)
        XCTAssertEqual(flow.speedKn, 6)
        XCTAssertEqual(flow.bearingDeg, 155)
        XCTAssertEqual(flow.center.latitude, gate.latitude, accuracy: 1e-12)
        XCTAssertEqual(flow.center.longitude, gate.longitude, accuracy: 1e-12)
    }

    func testDoddUsesFloodBearingForPositiveFlow() throws {
        let flow = try XCTUnwrap(DoddMapFlowProvider(
            gate: gate, signedSpeed: { _ in 6 }).flow(at: date))
        XCTAssertEqual(flow.speedKn, 6)
        XCTAssertEqual(flow.bearingDeg, 355)
    }

    func testFittedGateReadingCarriesBothPublishedBearings() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { !$0.isOnline && $0.recipe == ChsCurrentFit.stamp })
        let model = ChsCurrentModel(
            stationID: gate.id, iwlsID: "abc", iwlsName: gate.name, fittedAt: .now,
            fitStartMs: 1, fitEndMs: 2, fitDays: gate.fitDays, recipe: ChsCurrentFit.stamp,
            floodDirection: 355, ebbDirection: 155, offset: 0, rms: 0.1,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        try ChsModelStore.saveCurrent(model)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.currentUrl(gate.id)) }
        let reading = try XCTUnwrap(gate.cachedReading(at: date))
        XCTAssertEqual(reading.floodDirection, 355)
        XCTAssertEqual(reading.ebbDirection, 155)
        XCTAssertTrue(reading.signedKn.isFinite)
    }

    func testDoddProductionUsesOnlineCacheAndNeverExtrapolates() throws {
        let id = "chs-dodd-narrows"
        let url = ChsModelStore.onlineUrl(id)
        let saved = try? Data(contentsOf: url)
        defer {
            if let saved { try? saved.write(to: url) }
            else { try? FileManager.default.removeItem(at: url) }
        }
        let now = appNow(), t = now.timeIntervalSince1970
        let window = ChsOnlineWindow(stationID: id, iwlsName: "Dodd", timezone: "America/Vancouver",
                                     fetchedAt: now, start: now, end: now.addingTimeInterval(900),
                                     // Dodd's IWLS metadata: the ebb is 20° off the flood's reciprocal.
                                     floodDirection: 355, ebbDirection: 155,
                                     times: [t, t + 900], speeds: [2, -6])
        try ChsModelStore.saveOnline(window)
        let flow = try XCTUnwrap(DoddMapFlowProvider().flow(at: now.addingTimeInterval(450)))
        XCTAssertEqual(flow.speedKn, 2, accuracy: 1e-9)
        XCTAssertEqual(flow.bearingDeg, 155)
        XCTAssertNil(DoddMapFlowProvider().flow(at: now.addingTimeInterval(901)))
        XCTAssertNil(DoddMapFlowProvider().flow(at: now.addingTimeInterval(-1)))
    }

    func testOnlineMapReadingDoesNotBridgeAMissingSample() {
        let now = appNow(), t = now.timeIntervalSince1970
        let window = ChsOnlineWindow(stationID: "test", iwlsName: "Test", timezone: "UTC",
                                     fetchedAt: now, start: now, end: now.addingTimeInterval(1800),
                                     floodDirection: 0, ebbDirection: 180,
                                     times: [t, t + 1800], speeds: [2, -2])
        XCTAssertNil(window.signedSpeed(at: now.addingTimeInterval(900)))
        XCTAssertEqual(window.signedSpeed(at: now), 2)
    }

    func testDoddDrawsNoArrowAtZeroSpeed() {
        XCTAssertNil(DoddMapFlowProvider(gate: gate, signedSpeed: { _ in 0 }).flow(at: date))
    }

    func testDoddOmitsMissingModel() {
        XCTAssertNil(DoddMapFlowProvider(gate: gate, signedSpeed: { _ in nil }).flow(at: date))
    }

    // MARK: - Minor axis

    /// The water at one instant, as the kit reads it.
    private func point(_ record: CurrentStationRecord, at t: Date) -> CurrentPoint {
        record.engineStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first!
    }

    /// Kodiak's cross-flow is the strongest NOAA publishes (minor about 0.8 of
    /// major): at a major-axis slack the water still runs, and it has a set.
    func testARotaryStationStillRunsAtItsMajorAxisSlack() throws {
        let kodiak = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/KOD0901"))
        let slacks = kodiak.engineStation.events(from: date, to: date.addingTimeInterval(86_400))
            .filter { $0.kind == .slack }
        XCTAssertFalse(slacks.isEmpty)
        for slack in slacks {
            let p = point(kodiak, at: slack.time)
            XCTAssertEqual(p.speed, 0, accuracy: 0.01, "\(slack.time)")
            XCTAssertGreaterThan(p.magnitude, 0.05, "\(slack.time)")
            XCTAssertNotNil(p.direction, "\(slack.time)")
        }
    }

    /// Pollock Rip publishes no cross-flow, so its reading is the signed major-axis speed and a published bearing.
    func testAOneAxisStationReadsAlongItsPublishedBearings() throws {
        let pollock = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/ACT1616"))
        XCTAssertNil(pollock.minorConstituents)
        for hour in stride(from: 0, to: 12, by: 2) {
            let p = point(pollock, at: date.addingTimeInterval(Double(hour) * 3600))
            XCTAssertNotEqual(p.speed, 0)
            XCTAssertEqual(p.magnitude, abs(p.speed), "hour \(hour)")
            XCTAssertEqual(p.direction, p.speed > 0 ? pollock.floodDirection : pollock.ebbDirection, "hour \(hour)")
        }
    }
}
