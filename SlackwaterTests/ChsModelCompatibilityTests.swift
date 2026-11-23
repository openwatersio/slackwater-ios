// Slackwater — GPL v3.
import XCTest
import SlackwaterKit
@testable import Slackwater

final class ChsModelCompatibilityTests: XCTestCase {
    private func gate(days: Double = 210, provisional: Int? = 35, recipe: String = ChsCurrentFit.stamp) -> ChsCurrentGateInfo {
        ChsCurrentGateInfo(id: "chs-test", name: "Test", region: "Test", aliases: [],
                          latitude: 49, longitude: -123, timezone: "America/Vancouver", tideReference: nil,
                          fitDays: days, provisionalSlackMinutes: provisional, recipe: recipe)
    }

    private func model(days: Double? = 210, recipe: String? = ChsCurrentFit.stamp) -> ChsModel {
        ChsModel(stationID: "chs-test", iwlsID: "test", iwlsName: "Test", fittedAt: .now,
                 fitStartMs: 0, fitEndMs: 1, fitDays: days, recipe: recipe,
                 floodDirection: 45, ebbDirection: 225, offset: 0, rms: 0,
                 constituents: [.init(name: "M2", amplitude: 1, phase: 0)])
    }

    func testTideModelPhaseConventionRoundTripsAcrossVersions() throws {
        let old = [Con(name: "M3", amplitude: 1, phase: 350), Con(name: "M2", amplitude: 2, phase: 12)]
        let translated = translatedLegacyTidePhases(old)
        XCTAssertEqual(translated.map(\.phase), [170, 12])
        XCTAssertEqual(translatedLegacyTidePhases(translated).map(\.phase), [350, 12])
        let info = try XCTUnwrap(ChsStationInfo.all.first)
        let model = ChsModel(stationID: info.id, iwlsID: "test", iwlsName: "Test", fittedAt: .now,
                             fitStartMs: 0, fitEndMs: 1, offset: 0, rms: 0, constituents: old)
        XCTAssertEqual(info.record(with: model).constituents.map(\.phase), [170, 12])
    }

    func testFittedTideRetainsPhaseThroughStoredModel() async throws {
        let start = Date(timeIntervalSince1970: 1_755_800_000)
        let end = start.addingTimeInterval(90 * 86_400)
        let source = Station(constituents: [HarmonicConstituent(name: "M3", amplitude: 1, phase: 37)], offset: 1)
        let samples = source.heights(from: start, to: end, step: 3600).map {
            ChsSample(t: $0.time.timeIntervalSince1970 * 1000, v: $0.height)
        }
        let fit = try await ChsFitter().fit(samples: samples, basis: ChsFitter.tideBasis)
        let info = try XCTUnwrap(ChsStationInfo.all.first)
        let model = ChsModel(stationID: info.id, iwlsID: "test", iwlsName: "Test", fittedAt: .now,
                             fitStartMs: 0, fitEndMs: 1, offset: fit.offset, rms: fit.rms,
                             constituents: translatedLegacyTidePhases(fit.constituents))
        let record = info.record(with: model)
        let restored = Station(constituents: record.constituents.map {
            HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
        }, offset: record.datumOffset)
        let heldStart = end.addingTimeInterval(3600)
        let heldEnd = heldStart.addingTimeInterval(24 * 3600)
        let expected = source.heights(from: heldStart, to: heldEnd, step: 3600)
        let actual = restored.heights(from: heldStart, to: heldEnd, step: 3600)
        XCTAssertEqual(actual.count, expected.count)
        for (a, e) in zip(actual, expected) { XCTAssertEqual(a.height, e.height, accuracy: 0.001) }
    }

    func testOnlyMeasuredWindowsAreUsable() {
        XCTAssertNotNil(gate().usableModel(model()))
        XCTAssertNotNil(gate().usableModel(model(days: 60)))
        XCTAssertTrue(gate().isProvisional(model(days: 60)))
        XCTAssertNil(gate(provisional: nil).usableModel(model(days: 60)))
        XCTAssertFalse(gate(provisional: nil).isProvisional(model(days: 60)))
        XCTAssertNil(gate().usableModel(model(days: 90)))
        XCTAssertNil(gate(days: 60).usableModel(model()))
    }

    func testRecipeMustMatchEvidenceAndEngine() {
        XCTAssertNil(gate().usableModel(model(recipe: "other")))
        XCTAssertNil(gate(recipe: "other").usableModel(model(recipe: "other")))
        XCTAssertNil(gate().usableModel(model(recipe: nil)))
        XCTAssertNil(gate(recipe: "other").usableModel(model(recipe: nil)))
    }

    func testLegacyCurrentModelRemainsUsableOfflineWithCorrectedM3Phase() throws {
        let constituents = ChsCurrentFit.basis.map { Con(name: $0, amplitude: $0 == "M3" ? 1 : 0, phase: 10) }
        let legacy = ChsModel(stationID: "chs-test", iwlsID: "test", iwlsName: "Test", fittedAt: .now,
                              fitStartMs: 0, fitEndMs: 1, fitDays: 210, recipe: "8f85912ce223",
                              floodDirection: 45, ebbDirection: 225, offset: 0, rms: 0,
                              constituents: constituents)
        let converted = try XCTUnwrap(gate().usableModel(legacy))
        XCTAssertEqual(converted.recipe, ChsCurrentFit.stamp)
        XCTAssertEqual(converted.constituents.first { $0.name == "M3" }?.phase, 190)
        XCTAssertEqual(gate().usableRecord(with: legacy)?.constituents.first { $0.name == "M3" }?.phase, 190)
        XCTAssertEqual(converted.constituents.first { $0.name == "M2" }?.phase, 10)
        XCTAssertEqual(legacy.constituents.first { $0.name == "M3" }?.phase, 10)
        let station = CurrentStation(constituents: converted.constituents.map {
            HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
        }, floodDirection: 45, ebbDirection: 225, offset: 0)
        let time = Date(timeIntervalSince1970: 1_767_225_600)
        XCTAssertEqual(try XCTUnwrap(station.speeds(from: time, to: time.addingTimeInterval(1), step: 1).first).speed,
                       -0.015125836587024157, accuracy: 1e-7)
        var incomplete = legacy
        incomplete.constituents.removeLast()
        XCTAssertNil(gate().usableModel(incomplete))
    }

    @MainActor func testLegacyCurrentFileRemainsAvailableWithoutCalendarInvalidation() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { !$0.isOnline })
        let model = ChsModel(stationID: gate.id, iwlsID: "test", iwlsName: "Test", fittedAt: .now,
                             fitStartMs: 0, fitEndMs: 1, fitDays: gate.fitDays, recipe: "8f85912ce223",
                             floodDirection: 45, ebbDirection: 225, offset: 0, rms: 0,
                             constituents: ChsCurrentFit.basis.map { Con(name: $0, amplitude: 1, phase: 10) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let name = gate.id + "-current.json"
        let bytes = try JSONEncoder().encode(model)
        try bytes.write(to: directory.appendingPathComponent(name))
        ChsFitService.invalidateCurrentCalendars(in: [name], directory: directory, defaults: defaults)
        XCTAssertTrue(CurrentCalendarInvalidations.pending(in: defaults).isEmpty)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), bytes)
        XCTAssertNotNil(gate.usableModel(try JSONDecoder().decode(ChsModel.self, from: bytes)))
    }

    func testUnstampedOrUnknownWindowRefitsOnce() {
        XCTAssertNil(gate().usableModel(model(days: nil, recipe: nil)))
        XCTAssertNil(gate(days: 60).usableModel(model(days: nil, recipe: nil)))
        XCTAssertNil(gate().usableModel(model(days: nil)))
    }

    func testOnlineGateCannotUseAFittedModel() {
        var online = gate()
        online.online = true
        XCTAssertNil(online.usableModel(model()))
    }

    func testTierTransitionPurgesOppositeModel() {
        let files: Set<String> = ["chs-fit-current.json", "chs-fit-online.json", "chs-online-current.json", "chs-online-online.json"]
        XCTAssertEqual(ChsFitService.orphanFiles(in: files, ports: [], gates: ["chs-fit", "chs-online"], onlineGates: ["chs-online"]),
                       ["chs-fit-online.json", "chs-online-current.json"])
    }

    func testPinnedRecipeMatchesMeasuredFixture() throws {
        let data = Data(try repoSource("tools/chs-current-recipe.json").utf8)
        struct Recipe: Decodable { let stamp: String }
        let fixture = try JSONDecoder().decode(Recipe.self, from: data)
        XCTAssertEqual(ChsCurrentFit.stamp, fixture.stamp)
    }
}
