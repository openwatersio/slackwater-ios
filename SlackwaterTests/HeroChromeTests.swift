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

    /// The "a third of the screen" claim, executable: callers pass screen/3 as
    /// the hero's minHeight floor, so at default type the hero fills exactly
    /// that. It is a floor, not a crop: larger type must still be able to grow
    /// past it — a fixed crop that clips the region line is the defect class
    /// the Dynamic Type pass cleared (2026-08-02 note).
    @MainActor
    func testHeroFillsAThirdAndGrowsWithType() {
        let screenThird: CGFloat = 852.0 / 3 // iPhone 17 portrait
        func height(at size: DynamicTypeSize) -> CGFloat {
            let host = UIHostingController(rootView:
                MapHeader(name: "Sesuit Harbor", region: "EAST DENNIS",
                          latitude: 41.75, longitude: -70.15, favoriteId: "test",
                          topSafeInset: 62, minHeight: screenThird)
                    .environment(\.dynamicTypeSize, size))
            return host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude)).height
        }
        XCTAssertEqual(height(at: .large), screenThird, accuracy: 0.5,
                       "hero fills the third-of-screen floor at default type")
        XCTAssertGreaterThanOrEqual(height(at: .accessibility5), screenThird,
                                    "minHeight is a floor — large type never crops the pill")
    }

    /// Issue #50: the status-bar clearance was a Dynamic Island literal (62),
    /// wrong on SE-class phones and iPad split-view panes. Derived-not-literal,
    /// executable: render at two safe-area insets and the height must track
    /// their difference exactly — a constant can't.
    @MainActor
    func testHeaderClearanceTracksSafeAreaInset() {
        func height(inset: CGFloat) -> CGFloat {
            let host = UIHostingController(rootView:
                // minHeight 0: this test measures the intrinsic clearance
                // derivation, not the screen-third floor.
                MapHeader(name: "Sesuit Harbor", region: "EAST DENNIS",
                          latitude: 41.75, longitude: -70.15, favoriteId: "test",
                          topSafeInset: inset, minHeight: 0))
            return host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude)).height
        }
        XCTAssertEqual(height(inset: 62) - height(inset: 20), 42, accuracy: 0.5,
                       "clearance derives from the real safe-area inset, not a Dynamic Island literal")
    }
}
