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

    func testReleasedDoddPeakPinsCentreColourDirectionAndMotion() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == "chs-dodd-narrows" })
        XCTAssertEqual(gate.latitude, 49.13546639419797, accuracy: 1e-12)
        XCTAssertEqual(gate.longitude, -123.81735084108287, accuracy: 1e-12)

        let fittedGate = CurrentStationRecord(
            id: gate.id, name: gate.name, region: gate.region, aliases: gate.aliases,
            latitude: gate.latitude, longitude: gate.longitude, timezone: gate.timezone,
            floodDirection: 21, ebbDirection: 201, meanFlow: 0, tideReference: gate.tideReference,
            constituents: [])
        for (signedKn, expectedBearing, northward, eastward) in [
            (9.43, 21.0, true, true),
            (-9.43, 201.0, false, false),
        ] {
            let flow = try XCTUnwrap(DoddMapFlowProvider(
                gate: fittedGate, signedSpeed: { _ in signedKn }).flow(at: fixtureDate))
            XCTAssertEqual(flow.center.latitude, gate.latitude, accuracy: 1e-12)
            XCTAssertEqual(flow.center.longitude, gate.longitude, accuracy: 1e-12)
            XCTAssertEqual(flow.speedKn, 9.43, accuracy: 1e-12)
            XCTAssertEqual(flow.bearingDeg, expectedBearing, accuracy: 1e-12)
            XCTAssertEqual(fillColourHex(forSpeedKn: flow.speedKn), "#dd6138")

            let next = advanceCurrentCoordinate(
                flow.center, vector: .init(speedKn: flow.speedKn, bearingDeg: flow.bearingDeg),
                dt: 1, speedScale: STREAK_SPEED_SCALE)
            XCTAssertGreaterThan(
                CLLocation(latitude: flow.center.latitude, longitude: flow.center.longitude)
                    .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude)),
                1)
            XCTAssertEqual(next.latitude > flow.center.latitude, northward)
            XCTAssertEqual(next.longitude > flow.center.longitude, eastward)
        }
    }

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

    func testAnimatorSamplesPatchBeforeFill() {
        let origin = CLLocationCoordinate2D(latitude: 49.1344, longitude: -123.8171)
        let animator = CurrentStreakAnimator(
            certifiedSeeds: [origin],
            patchSample: { _, _ in CurrentVector(speedKn: 2, bearingDeg: 90) },
            fillSample: { _, _ in CurrentVector(speedKn: 2, bearingDeg: 0) },
            doddFlow: { _ in nil })

        _ = animator.advance(at: fixtureDate, elapsed: 1, reduceMotion: false)

        XCTAssertGreaterThan(animator.certifiedParticles[0].head.longitude, origin.longitude)
        XCTAssertEqual(animator.certifiedParticles[0].head.latitude, origin.latitude, accuracy: 1e-7)
    }

    func testAnimatorKeepsCurvedHistoryBounded() {
        let origin = CLLocationCoordinate2D(latitude: 49.1344, longitude: -123.8171)
        var call = 0
        let animator = CurrentStreakAnimator(
            certifiedSeeds: [origin],
            patchSample: { _, _ in nil },
            fillSample: { _, _ in
                defer { call += 1 }
                return CurrentVector(speedKn: 1, bearingDeg: call == 0 ? 90 : 0)
            },
            doddFlow: { _ in nil })

        for _ in 0..<(STREAK_HISTORY_LIMIT + 3) {
            _ = animator.advance(at: fixtureDate, elapsed: 1, reduceMotion: false)
        }

        let particle = animator.certifiedParticles[0]
        XCTAssertEqual(particle.history.count, STREAK_HISTORY_LIMIT)
        XCTAssertGreaterThan(particle.head.latitude, origin.latitude)
        XCTAssertGreaterThan(particle.head.longitude, origin.longitude)
    }

    func testAnimatorRecyclesMissingCertifiedCoverage() {
        let origin = CLLocationCoordinate2D(latitude: 49.1344, longitude: -123.8171)
        let animator = CurrentStreakAnimator(
            certifiedSeeds: [origin], patchSample: { _, _ in nil }, fillSample: { _, _ in nil },
            doddFlow: { _ in nil })

        _ = animator.advance(at: fixtureDate, elapsed: 1, reduceMotion: false)

        let particle = animator.certifiedParticles[0]
        XCTAssertEqual(particle.head.latitude, origin.latitude, accuracy: 1e-12)
        XCTAssertEqual(particle.head.longitude, origin.longitude, accuracy: 1e-12)
        XCTAssertEqual(particle.history.count, 1)
    }

    func testAnimatorRecyclesDoddParticlesAtEnvelope() {
        let flow = StationMapFlow(
            center: CLLocationCoordinate2D(latitude: fixtureGate.latitude, longitude: fixtureGate.longitude),
            speedKn: 1_000, bearingDeg: 21)
        let animator = CurrentStreakAnimator(
            certifiedSeeds: [], patchSample: { _, _ in nil }, fillSample: { _, _ in nil },
            doddFlow: { _ in flow })

        _ = animator.advance(at: fixtureDate, elapsed: 1, reduceMotion: false)

        XCTAssertEqual(animator.doddParticles.count, DODD_STREAK_COUNT)
        XCTAssertTrue(animator.doddParticles.allSatisfy {
            doddEnvelopeContains($0.head, center: flow.center, bearingDeg: flow.bearingDeg)
        })
    }

    func testAnimatorReduceMotionKeepsHeadsAndFeatures() {
        let origin = CLLocationCoordinate2D(latitude: 49.1344, longitude: -123.8171)
        let animator = CurrentStreakAnimator(
            certifiedSeeds: [origin],
            patchSample: { _, _ in CurrentVector(speedKn: 2, bearingDeg: 90) },
            fillSample: { _, _ in nil }, doddFlow: { _ in nil })
        _ = animator.advance(at: fixtureDate, elapsed: 1, reduceMotion: false)
        let before = animator.certifiedParticles[0].head

        let features = animator.advance(at: fixtureDate, elapsed: 10, reduceMotion: true)

        XCTAssertEqual(animator.certifiedParticles[0].head.latitude, before.latitude, accuracy: 1e-12)
        XCTAssertEqual(animator.certifiedParticles[0].head.longitude, before.longitude, accuracy: 1e-12)
        XCTAssertFalse(features.isEmpty)
    }
}
