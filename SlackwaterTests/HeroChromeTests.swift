import XCTest
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
}
