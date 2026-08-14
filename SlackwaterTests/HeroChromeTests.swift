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

    /// The "a third, not a half" claim, executable: at default type the hero is
    /// title-pill + clearances, well under 200pt. At AX3 it must GROW — a fixed
    /// crop that clips the region line is the defect class the Dynamic Type pass
    /// just cleared (2026-08-02 note).
    @MainActor
    func testHeroIsAThirdAtDefaultTypeAndGrowsAtAX3() {
        func height(at size: DynamicTypeSize) -> CGFloat {
            let host = UIHostingController(rootView:
                MapHeader(name: "Sesuit Harbor", region: "EAST DENNIS",
                          latitude: 41.75, longitude: -70.15, favoriteId: "test",
                          topSafeInset: 62)
                    .environment(\.dynamicTypeSize, size))
            return host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude)).height
        }
        let base = height(at: .large)
        XCTAssertLessThan(base, 200, "hero must be a third of the screen, not half")
        XCTAssertGreaterThan(base, 100, "hero must still clear the status bar + pill")
        XCTAssertGreaterThan(height(at: .accessibility5), base,
                             "the hero grows with type — it never crops the pill")
    }

    /// Issue #50: the status-bar clearance was a Dynamic Island literal (62),
    /// wrong on SE-class phones and iPad split-view panes. Derived-not-literal,
    /// executable: render at two safe-area insets and the height must track
    /// their difference exactly — a constant can't.
    @MainActor
    func testHeaderClearanceTracksSafeAreaInset() {
        func height(inset: CGFloat) -> CGFloat {
            let host = UIHostingController(rootView:
                MapHeader(name: "Sesuit Harbor", region: "EAST DENNIS",
                          latitude: 41.75, longitude: -70.15, favoriteId: "test",
                          topSafeInset: inset))
            return host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude)).height
        }
        XCTAssertEqual(height(inset: 62) - height(inset: 20), 42, accuracy: 0.5,
                       "clearance derives from the real safe-area inset, not a Dynamic Island literal")
    }
}
