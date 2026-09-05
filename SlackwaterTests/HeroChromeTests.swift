import XCTest
import SwiftUI
@testable import Slackwater

/// The hero-crop spec's material rule, executable: floating chrome is Liquid
/// Glass. A material-plus-tint imitation must not come back — repo-wide, like
/// the retired-font scan, because the survivor is always in the file nobody
/// thought to check.
final class HeroChromeTests: XCTestCase {

    func testNoMaterialImitationOfGlass() throws {
        let materials = [".ultraThinMaterial", ".thinMaterial", ".regularMaterial", ".thickMaterial", ".ultraThickMaterial"]
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where materials.contains(where: { line.contains($0) }) {
                offenders.append("\(name):\(n + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "chrome must use .glassEffect, not material imitation:\n"
                      + offenders.joined(separator: "\n"))
    }
}
