// Slackwater — GPL v3. Issue #12: CHS pins take colour from what the offline
// sync has ALREADY stored. These exercise the cache→state resolver
// (`chsPinStates`), which by construction cannot fetch: it takes the stored
// records as plain dictionaries, and a station the sync has not reached is
// absent from the result — the map draws it neutral, honestly.
import XCTest
@testable import Slackwater

final class ChsPinToneTests: XCTestCase {
    func testCachedReadingKeepsItsUnitWhenPreferencesChangeBeforeFeatureBuilding() throws {
        let defaults = AppGroup.defaults
        let saved = defaults.object(forKey: unitsKey)
        defer {
            if let saved { defaults.set(saved, forKey: unitsKey) }
            else { defaults.removeObject(forKey: unitsKey) }
        }
        let info = try XCTUnwrap(ChsStationInfo.all.first)
        let preview = ChsTidePreview(stationID: info.id, fetchedAt: now, samples: [
            .init(time: now.addingTimeInterval(-900), height: 2),
            .init(time: now, height: 1),
            .init(time: now.addingTimeInterval(900), height: 0),
        ])
        defaults.set("imperial", forKey: unitsKey)
        let states = chsPinStates(at: now, items: [.chs(info)], detailed: true,
                                 tideRecords: [:], currentRecords: [:], tidePreviews: [info.id: preview])
        defaults.set("metric", forKey: unitsKey)
        let geojson = pinFeatures(for: [.chs(info)], zoom: 11, chsStates: states)
        let features = try XCTUnwrap(geojson["features"] as? [[String: Any]])
        let reading = (features.first?["properties"] as? [String: Any])?["reading"] as? String
        XCTAssertEqual(reading, "\(3.3.formatted(.number.precision(.fractionLength(1)))) ft")
    }

    func testNearbyMapReadingsKeepUnitsWithoutALegend() throws {
        let tide = try XCTUnwrap(StationItem.all.first { $0.pinKind == "chs" })
        let current = try XCTUnwrap(StationItem.all.first { if case .chsCurrent = $0 { true } else { false } })
        let states = [tide.id: PinState(state: "falling", reading: "1.0", unit: "ft"),
                      current.id: PinState(state: "#ffffff", reading: "2.0", unit: "kn")]
        let geojson = pinFeatures(for: [tide, current], zoom: 11, chsStates: states)
        let features = try XCTUnwrap(geojson["features"] as? [[String: Any]])
        let readings = features.compactMap { ($0["properties"] as? [String: Any])?["reading"] as? String }
        XCTAssertEqual(readings, ["1.0 ft", "2.0 kn"])
        let fullMap = pinFeatures(for: [tide, current], zoom: 11, chsStates: states, showsUnits: false)
        let fullFeatures = try XCTUnwrap(fullMap["features"] as? [[String: Any]])
        XCTAssertEqual(fullFeatures.compactMap { ($0["properties"] as? [String: Any])?["reading"] as? String },
                       ["1.0", "2.0"])
    }

    func testTidePinReadingsConvertUnitsWithoutRepeatingTheLegend() {
        let record = port("test")
        let preview = ChsTidePreview(stationID: record.id, fetchedAt: now, samples: [
            .init(time: now.addingTimeInterval(-900), height: 2),
            .init(time: now, height: 1),
            .init(time: now.addingTimeInterval(900), height: 0),
        ])
        let metric = tidePinState(record, at: now, imperial: false, detailed: true, station: preview)
        let imperial = tidePinState(record, at: now, imperial: true, detailed: true, station: preview)
        XCTAssertEqual(metric.reading, 1.0.formatted(.number.precision(.fractionLength(2))))
        XCTAssertEqual(imperial.reading, 3.3.formatted(.number.precision(.fractionLength(1))))
        XCTAssertEqual(metric.state, imperial.state)
        XCTAssertEqual(metric.gauge, imperial.gauge)
    }

    func testLastPreviewSegmentKeepsItsReadingAndDirectionWithoutFeedingDerivedGates() throws {
        let gate = try XCTUnwrap(ChsGateInfo.all.first)
        let info = try XCTUnwrap(ChsStationInfo.all.first { $0.id == gate.reference })
        let preview = ChsTidePreview(stationID: info.id, fetchedAt: now, samples: [
            .init(time: now.addingTimeInterval(-900), height: 2),
            .init(time: now, height: 1),
            .init(time: now.addingTimeInterval(900), height: 0),
        ])
        let card = info.previewIdentity.cardState(at: now, station: preview)
        XCTAssertEqual(card.height, 1)
        XCTAssertFalse(card.rising)
        XCTAssertNil(card.next)
        let states = chsPinStates(at: now, items: StationItem.all, detailed: true,
                                 tideRecords: [:], currentRecords: [:], tidePreviews: [info.id: preview])
        XCTAssertEqual(states[info.id]?.state, "falling")
        XCTAssertNotNil(states[info.id]?.reading)
        XCTAssertNil(states[gate.id])
        XCTAssertTrue(chsPinStates(at: now.addingTimeInterval(901), items: StationItem.all, detailed: true,
                                  tideRecords: [:], currentRecords: [:], tidePreviews: [info.id: preview]).isEmpty)
    }

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
        XCTAssertTrue(chsPinStates(at: now, items: StationItem.all, detailed: true,
                                 tideRecords: [:], currentRecords: [:]).isEmpty)
    }

    /// A fitted CHS tide port resolves rising/falling exactly like a bundled
    /// NOAA one — same hybrid, same tone words — and ONLY the synced station
    /// takes a tone.
    func testFittedPortResolvesDirectionAndUnsyncedNeighboursStayOut() throws {
        // Not a derived gate's reference, so exactly one tone can come back.
        let references = Set(ChsGateInfo.all.map(\.reference))
        let info = try XCTUnwrap(ChsStationInfo.all.first { !references.contains($0.id) })
        let record = port(info.id)
        let states = chsPinStates(at: now, items: StationItem.all, detailed: true,
                                    tideRecords: [info.id: record], currentRecords: [:])
        let expected = try XCTUnwrap(tidePinRisingHybrid(record, at: now)) ? "rising" : "falling"
        XCTAssertEqual(states[info.id]?.state, expected)
        XCTAssertEqual(states.count, 1, "a station the sync has not reached must stay neutral")
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
        let states = chsPinStates(at: now, items: StationItem.all, detailed: true,
                                    tideRecords: [:], currentRecords: [gate.id: record])
        XCTAssertEqual(states[gate.id]?.state, currentPinState(record, at: now, speedUnit: "kn").state)
        XCTAssertTrue((states[gate.id]?.state ?? "").hasPrefix("#"),
                      "a fitted gate is speed-bearing: its tone is a colour literal (#13)")
    }

    /// A derived gate has no model (and no `cardState(at:)`) of its own: it
    /// takes a tone exactly when its reference port — itself a CHS port — is
    /// fitted, and stays neutral otherwise.
    func testDerivedGateFollowsItsReferencePort() throws {
        let gate = try XCTUnwrap(ChsGateInfo.all.first)
        XCTAssertNil(chsPinStates(at: now, items: StationItem.all, detailed: true,
                                  tideRecords: [:], currentRecords: [:])[gate.id],
                     "no fitted reference → neutral")
        let reference = port(gate.reference)
        let states = chsPinStates(at: now, items: StationItem.all, detailed: true,
                                    tideRecords: [gate.reference: reference], currentRecords: [:])
        let phase = DerivedGateRecord(gate: gate, port: reference).cardState(at: now).phase
        XCTAssertEqual(states[gate.id]?.state, phase == .flood ? "flood" : phase == .ebb ? "ebb" : "slack")
    }
}
