// Slackwater — GPL v3. Issue #12: CHS pins take colour from what the offline
// sync has ALREADY stored. These exercise the cache→tone resolver
// (`chsPinTones`), which by construction cannot fetch: it takes the stored
// records as plain dictionaries, and a station the sync has not reached is
// absent from the result — the map draws it neutral, honestly.
import XCTest
@testable import Slackwater

final class ChsPinToneTests: XCTestCase {

    /// A fitted-model-shaped record around a synthetic M2-only tide, keyed to
    /// whatever CHS identity the test hands it.
    private func port(_ id: String) -> TideStationRecord {
        TideStationRecord(
            id: id, name: "Test Port", region: "Test", aliases: [],
            latitude: 49.337, longitude: -123.254, timezone: "America/Vancouver",
            chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
    }

    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    /// Nothing synced → nothing resolved. Every CHS pin stays neutral, and no
    /// path exists that could reach the network for the missing ones.
    func testUnsyncedStationsStayNeutral() {
        XCTAssertTrue(chsPinTones(at: now, tideRecords: [:], currentRecords: [:]).isEmpty)
    }

    /// A fitted CHS tide port resolves rising/falling exactly like a bundled
    /// NOAA one — same hybrid, same tone words — and ONLY the synced station
    /// takes a tone.
    func testFittedPortResolvesDirectionAndUnsyncedNeighboursStayOut() throws {
        // Not a derived gate's reference, so exactly one tone can come back.
        let references = Set(ChsGateInfo.all.map(\.reference))
        let info = try XCTUnwrap(ChsStationInfo.all.first { !references.contains($0.id) })
        let record = port(info.id)
        let tones = chsPinTones(at: now, tideRecords: [info.id: record], currentRecords: [:])
        let expected = try XCTUnwrap(tidePinRisingHybrid(record, at: now)) ? "rising" : "falling"
        XCTAssertEqual(tones[info.id], expected)
        XCTAssertEqual(tones.count, 1, "a station the sync has not reached must stay neutral")
    }

    /// A fitted CHS current gate resolves flood/ebb/slack through the same
    /// record path a bundled NOAA current station uses.
    func testFittedGateResolvesPhase() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { !$0.isOnline })
        let record = CurrentStationRecord(
            id: gate.id, name: gate.name, region: gate.region, aliases: [],
            latitude: gate.latitude, longitude: gate.longitude, timezone: gate.timezone,
            floodDirection: 90, ebbDirection: 270, meanFlow: 0, tideReference: nil,
            constituents: [.init(name: "M2", amplitude: 2.0, phase: 0)])
        let tones = chsPinTones(at: now, tideRecords: [:], currentRecords: [gate.id: record])
        XCTAssertEqual(tones[gate.id], currentPinColour(record, at: now))
        XCTAssertTrue((tones[gate.id] ?? "").hasPrefix("#"),
                      "a fitted gate is speed-bearing: its tone is a colour literal (#13)")
    }

    /// A derived gate has no model (and no `cardState(at:)`) of its own: it
    /// takes a tone exactly when its reference port — itself a CHS port — is
    /// fitted, and stays neutral otherwise.
    func testDerivedGateFollowsItsReferencePort() throws {
        let gate = try XCTUnwrap(ChsGateInfo.all.first)
        XCTAssertNil(chsPinTones(at: now, tideRecords: [:], currentRecords: [:])[gate.id],
                     "no fitted reference → neutral")
        let reference = port(gate.reference)
        let tones = chsPinTones(at: now, tideRecords: [gate.reference: reference], currentRecords: [:])
        let phase = DerivedGateRecord(gate: gate, port: reference).cardState(at: now).phase
        XCTAssertEqual(tones[gate.id], phase == .flood ? "flood" : phase == .ebb ? "ebb" : "slack")
    }
}
