// Slackwater — GPL v3. Validated CHS current gates (M47): bundled identity,
// the flood-axis projection, and the fit→events math — a fitted model's
// record drives TideEngine's CurrentStation exactly like a bundled NOAA
// station (slacks at velocity zeros, maxima signed flood/ebb).
import XCTest
@testable import Slackwater
import TideEngine

final class ChsCurrentGateTests: XCTestCase {

    // MARK: - Bundled identity (chs-current-gates.json, generated from the registry)

    func testBundledGatesAreRegistryKeysWithBundledPairings() {
        for gate in ChsCurrentGateInfo.all {
            XCTAssert(gate.id.hasPrefix("chs-"), "\(gate.id) is not a registry key")
            XCTAssertEqual(gate.timezone, "America/Vancouver")
            if let ref = gate.tideReference {
                // Dual-track needs the port on this device: it must be a
                // bundled CHS tide port the app fits.
                XCTAssert(ChsStationInfo.all.contains { $0.id == ref },
                          "\(gate.id) pairs \(ref), not in chs-stations.json")
            }
        }
    }

    func testDoddNarrowsShipsAndIsSearchable() throws {
        let dodd = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == "chs-dodd-narrows" },
                                 "Dodd Narrows missing from chs-current-gates.json")
        XCTAssertEqual(dodd.name, "Dodd Narrows")
        for query in ["dodd", "nanaimo"] {
            XCTAssert(StationItem.search(query).contains { $0.id == dodd.id },
                      "search '\(query)' did not find Dodd Narrows")
        }
    }

    // MARK: - Flood-axis projection (speed · cos(dir − floodDirection))

    func testProjectionSignsAlongTheFloodAxis() {
        let speeds = [ChsSample(t: 0, v: 3), ChsSample(t: 1, v: 2), ChsSample(t: 2, v: 1)]
        let dirs = [ChsSample(t: 0, v: 45), ChsSample(t: 1, v: 225)]  // t:2 has no direction
        let out = ChsFitService.project(speeds: speeds, dirs: dirs, floodDirection: 45)
        XCTAssertEqual(out.count, 2, "sample without a direction stamp must drop")
        XCTAssertEqual(out[0].v, 3, accuracy: 1e-12)   // dir == flood → +speed
        XCTAssertEqual(out[1].v, -2, accuracy: 1e-12)  // dir == ebb (flood+180) → −speed
    }

    // MARK: - Fit → events: the record's engine finds slacks and signed maxima

    func testFittedModelRecordPredictsSlackAndSignedMaxima() throws {
        let gate = ChsCurrentGateInfo(
            id: "chs-test-gate", name: "Test Gate", region: "Test", aliases: [],
            latitude: 49, longitude: -123, timezone: "America/Vancouver", tideReference: nil)
        // A pure M2 current, 2 kn peak: slack every ~6.21 h, alternating maxima.
        let model = ChsCurrentModel(
            stationID: gate.id, iwlsID: "x", iwlsName: "x", fittedAt: .now,
            fitStartMs: 0, fitEndMs: 0, floodDirection: 45, ebbDirection: 225,
            offset: 0, rms: 0.01,
            constituents: [.init(name: "M2", amplitude: 2, phase: 0)])
        let record = gate.record(with: model)
        XCTAssertEqual(record.floodDirection, 45)
        XCTAssert(record.isChs)

        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let events = record.engineStation.events(from: start, to: start.addingTimeInterval(25 * 3600))
        let slacks = events.filter { $0.kind == .slack }
        let floods = events.filter { $0.kind == .maxFlood }
        let ebbs = events.filter { $0.kind == .maxEbb }
        // ~2 M2 cycles in 25 h: ~4 slacks (two zero crossings per 12.42 h
        // cycle), ~2 of each maximum (±1 at the window edges).
        XCTAssert(slacks.count >= 3, "expected ~4 slacks, got \(slacks.count)")
        XCTAssert(floods.count >= 1 && ebbs.count >= 1)
        // The slack finder bisects to 1 s, so |v| is ~2.5e-5 kn, not exactly 0.
        for s in slacks { XCTAssertEqual(s.speed, 0, accuracy: 1e-3) }
        for f in floods { XCTAssertEqual(f.speed, 2, accuracy: 0.1) }
        for e in ebbs { XCTAssertEqual(e.speed, -2, accuracy: 0.1) }
        // Events alternate slack / maximum — a maximum sits between slacks.
        for (a, b) in zip(events, events.dropFirst()) {
            XCTAssert((a.kind == .slack) != (b.kind == .slack),
                      "events must alternate slack and maxima")
        }
    }

    // MARK: - Store round-trip (the model that survives relaunch, offline)

    func testCurrentModelStoreRoundTrip() throws {
        let model = ChsCurrentModel(
            stationID: "chs-test-store", iwlsID: "abc", iwlsName: "Test", fittedAt: .now,
            fitStartMs: 1, fitEndMs: 2, floodDirection: 355, ebbDirection: 155,
            offset: 0.1, rms: 0.37,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 123)])
        try ChsModelStore.saveCurrent(model)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.currentUrl(model.stationID)) }
        let loaded = try XCTUnwrap(ChsModelStore.loadCurrent("chs-test-store"))
        XCTAssertEqual(loaded.floodDirection, 355)
        XCTAssertEqual(loaded.constituents.first?.phase, 123)
        // The gate store must never shadow a port model of the same key.
        XCTAssertNil(ChsModelStore.load("chs-test-store"))
    }
}
