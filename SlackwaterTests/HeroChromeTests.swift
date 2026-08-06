import XCTest
import SwiftUI
@testable import Slackwater

/// The hero-crop spec's material rule, executable: floating chrome is Liquid
/// Glass. A material-plus-tint imitation must not come back — repo-wide, like
/// the retired-font scan, because the survivor is always in the file nobody
/// thought to check.
final class HeroChromeTests: XCTestCase {

    private func appSources() throws -> [(name: String, source: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SlackwaterTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Slackwater")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not walk \(root.path)")
        var out: [(String, String)] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            out.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        XCTAssertGreaterThan(out.count, 10, "expected to scan the app's sources")
        return out
    }

    func testNoMaterialImitationOfGlass() throws {
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains(".ultraThinMaterial") {
                offenders.append("\(name):\(n + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "chrome must use .glassEffect, not material imitation:\n"
                      + offenders.joined(separator: "\n"))
    }

    /// The "a third, not a half" claim, executable: at default type the hero is
    /// title-pill + clearances, well under 200pt. At AX3 it must GROW — a fixed
    /// crop that clips the region line is the defect class the Dynamic Type pass
    /// just cleared (2026-08-02 note).
    @MainActor
    func testHeroIsAThirdAtDefaultTypeAndGrowsAtAX3() {
        func height(at size: DynamicTypeSize) -> CGFloat {
            let host = UIHostingController(rootView:
                MapHeader(name: "Sesuit Harbor", region: "EAST DENNIS",
                          latitude: 41.75, longitude: -70.15, favoriteId: "test")
                    .environment(\.dynamicTypeSize, size))
            return host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude)).height
        }
        let base = height(at: .large)
        XCTAssertLessThan(base, 200, "hero must be a third of the screen, not half")
        XCTAssertGreaterThan(base, 100, "hero must still clear the status bar + pill")
        XCTAssertGreaterThan(height(at: .accessibility5), base,
                             "the hero grows with type — it never crops the pill")
    }
}
