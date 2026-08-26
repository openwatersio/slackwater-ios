// Slackwater — GPL v3. Pure Dodd station-local map-flow tests.
import CoreLocation
import XCTest
@testable import Slackwater

final class CurrentStreakTests: XCTestCase {
    private let fixtureDate = Date(timeIntervalSince1970: 1_787_000_000)
    private let fixtureGate = CurrentStationRecord(
        id: "chs-dodd-narrows", name: "Dodd Narrows", region: "Nanaimo", aliases: [],
        latitude: 49.1344, longitude: -123.8171, timezone: "America/Vancouver",
        floodDirection: 21, ebbDirection: 201, meanFlow: 0, tideReference: nil, constituents: [])

    func testProviderUsesAbsoluteEbbSpeedAndReciprocalBearing() throws {
        var evaluations = 0
        let provider = DoddMapFlowProvider(gate: fixtureGate, signedSpeed: { _ in
            evaluations += 1
            return -6
        })

        let flow = try XCTUnwrap(provider.flow(at: fixtureDate))
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(flow.center.latitude, fixtureGate.latitude, accuracy: 1e-12)
        XCTAssertEqual(flow.center.longitude, fixtureGate.longitude, accuracy: 1e-12)
        XCTAssertEqual(flow.speedKn, 6, accuracy: 1e-12)
        XCTAssertEqual(flow.bearingDeg, fixtureGate.ebbDirection, accuracy: 1e-12)
    }

    func testProviderOmitsMissingSignedSpeed() {
        XCTAssertNil(DoddMapFlowProvider(gate: fixtureGate, signedSpeed: { _ in nil })
            .flow(at: fixtureDate))
    }

    func testAdvanceFollowsEastwardVector() {
        let origin = CLLocationCoordinate2D(latitude: 49.1344, longitude: -123.8171)
        let next = advanceCurrentCoordinate(
            origin, vector: CurrentVector(speedKn: 2, bearingDeg: 90), dt: 1, speedScale: 40)
        XCTAssertEqual(next.latitude, origin.latitude, accuracy: 1e-7)
        XCTAssertGreaterThan(next.longitude, origin.longitude)
    }

    func testDoddEnvelopeRejectsBeyondAxis() {
        let center = CLLocationCoordinate2D(latitude: 49.1344, longitude: -123.8171)
        XCTAssertTrue(doddEnvelopeContains(center, center: center))
        XCTAssertFalse(doddEnvelopeContains(
            particleCoordinate(center, bearingDeg: 0, alongM: DODD_AXIS_M, acrossM: 0),
            center: center))
    }

    func testDoddSeedsAndRecycleCoordinatesAreDeterministic() {
        let center = CLLocationCoordinate2D(latitude: 49.1344, longitude: -123.8171)
        XCTAssertEqual(doddSeed(index: 3), doddSeed(index: 3))
        let first = doddRecycleCoordinate(index: 3, center: center, bearingDeg: 21)
        let second = doddRecycleCoordinate(index: 3, center: center, bearingDeg: 21)
        XCTAssertEqual(first.latitude, second.latitude, accuracy: 1e-12)
        XCTAssertEqual(first.longitude, second.longitude, accuracy: 1e-12)
    }
}
