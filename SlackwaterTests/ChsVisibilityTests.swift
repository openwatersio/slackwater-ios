// Slackwater — GPL v3. The watch shows only what it can open (#521): a
// Canadian station needs the model file WidgetStationLoader would read.
import XCTest
@testable import Slackwater

final class ChsVisibilityTests: XCTestCase {

    private func first(_ match: (StationItem) -> Bool) throws -> StationItem {
        try XCTUnwrap(StationItem.all.first(where: match))
    }

    func testNoaaStationsAreAlwaysResolvable() throws {
        let tide = try first { if case .tide = $0 { true } else { false } }
        let current = try first { if case .current = $0 { true } else { false } }
        XCTAssertTrue(tide.isResolvable(fitted: []))
        XCTAssertTrue(current.isResolvable(fitted: []))
    }

    func testCanadianTideNeedsItsOwnModel() throws {
        let item = try first { if case .chs = $0 { true } else { false } }
        XCTAssertFalse(item.isResolvable(fitted: []))
        XCTAssertTrue(item.isResolvable(fitted: [item.id]))
    }

    func testDerivedGateNeedsItsReferencePortsModel() throws {
        let item = try first { if case .chsGate = $0 { true } else { false } }
        guard case .chsGate(let gate) = item else { return XCTFail("not a gate") }
        XCTAssertFalse(item.isResolvable(fitted: [item.id]))
        XCTAssertTrue(item.isResolvable(fitted: [gate.reference]))
    }

    func testHarmonicCanadianCurrentNeedsItsCurrentModel() throws {
        let item = try first { if case .chsCurrent(let c) = $0 { !c.isOnline } else { false } }
        XCTAssertFalse(item.isResolvable(fitted: [item.id, item.id + "-online"]))
        XCTAssertTrue(item.isResolvable(fitted: [item.id + "-current"]))
    }

    func testOnlineCanadianCurrentNeedsItsSavedWindow() throws {
        let item = try first { if case .chsCurrent(let c) = $0 { c.isOnline } else { false } }
        XCTAssertFalse(item.isResolvable(fitted: [item.id, item.id + "-current"]))
        XCTAssertTrue(item.isResolvable(fitted: [item.id + "-online"]))
    }

    func testFittedIDsAreTheModelFileStems() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["chs-07120.json", "chs-x-current.json", "chs-y-online.json", ".DS_Store"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }
        XCTAssertEqual(ChsModelStore.fittedIDs(in: dir),
                       ["chs-07120", "chs-x-current", "chs-y-online"])
    }

    /// A fresh watch has never fitted anything, so the folder does not exist.
    func testAMissingFolderMeansNothingIsFitted() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        XCTAssertEqual(ChsModelStore.fittedIDs(in: missing), [])
    }
}
