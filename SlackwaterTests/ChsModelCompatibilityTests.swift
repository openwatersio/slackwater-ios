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
