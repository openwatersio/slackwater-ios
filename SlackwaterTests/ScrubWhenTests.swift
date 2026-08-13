import XCTest
import SwiftUI
@testable import Slackwater

/// Spec'd in the 2026-08-05 hero-crop plan, never committed (issue #51) — the
/// first test that renders `ScrubWhen` at accessibility Dynamic Type sizes.
/// Same harness as `HeroChromeTests`: `UIHostingController.sizeThatFits`.
///
/// Two probes, because neither alone pins the defect. A height probe cannot
/// see the phase name truncate: at AX sizes the date `MonoLabel` wraps and
/// grows the row on its own, masking a clipped phase beside it (measured —
/// the pre-fix row passed a taller-when-constrained check). So the render
/// tests assert the reflow geometry, and a scoped source scan bans the
/// truncation vector itself — the `testOnlyTheWordmarkShrinks` idiom.
final class ScrubWhenTests: XCTestCase {

    /// Wrap, never truncate (the StationCard rule): no `.lineLimit` inside
    /// `ScrubWhen` — a `Text` short of room must reflow, not clip to "…".
    func testScrubWhenNeverTruncates() throws {
        let theme = try repoSource("Slackwater/Theme.swift")
        guard let start = theme.range(of: "struct ScrubWhen"),
              let end = theme.range(of: "struct ReturnToNowSlot") else {
            return XCTFail("ScrubWhen / ReturnToNowSlot moved — update this scan")
        }
        let body = theme[start.lowerBound..<end.lowerBound]
        XCTAssertFalse(body.contains(".lineLimit"),
                       "ScrubWhen must not truncate — drop content is the defect class issue #51 fixed")
    }

    private static let vancouver = TimeZone(identifier: "America/Vancouver")!

    @MainActor
    private func height(at size: DynamicTypeSize, width: CGFloat) -> CGFloat {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.vancouver
        let t = cal.date(from: DateComponents(year: 2026, month: 8, day: 1,
                                              hour: 10, minute: 30))!
        let host = UIHostingController(rootView:
            ScrubWhen(scrubTime: t, live: t, tz: Self.vancouver, onReturn: {})
                .environment(\.dynamicTypeSize, size))
        return host.sizeThatFits(in: CGSize(width: width,
                                            height: CGFloat.greatestFiniteMagnitude)).height
    }

    /// At default type the one-line row fits an iPhone width — the fallback
    /// tier must NOT engage (the StationCard lesson: an over-eager fallback
    /// is its own regression).
    @MainActor
    func testDefaultTypeKeepsTheSingleRow() {
        XCTAssertEqual(height(at: .large, width: 393),
                       height(at: .large, width: 2000), accuracy: 0.5,
                       "at .large the row fits one line — no stacking")
    }

    /// At AX3 and AX5 the `.title` time, the fixed 44pt slot and the phase
    /// name cannot share 393pt one line — the row must reflow taller, never
    /// hold the one-row height by shedding content. (Which ViewThatFits tier
    /// wins is not directly askable — StationCard's note — so this asserts
    /// the geometry the fallback produces.)
    @MainActor
    func testAccessibilitySizesReflowInsteadOfTruncating() {
        for size in [DynamicTypeSize.accessibility3, .accessibility5] {
            let oneRow = height(at: size, width: 2000)
            let constrained = height(at: size, width: 393)
            XCTAssertGreaterThan(constrained, oneRow + 1,
                "at \(size) the fallback tier must engage (reflow), not truncate to one row")
        }
    }
}
