// Slackwater — GPL v3. The first-run tour's anchors: which step a view is the
// target of, published as a preference. SwiftUI only, no UIKit, because the
// detail pieces that carry anchors (`DetailPieces.swift`) also compile into
// the watch, where nothing reads them.
import SwiftUI

/// In order. `stars` and `moon` each drop independently when their own
/// target time is unavailable (see `TourCoach`), so never advance by
/// `rawValue` — use `TourCoach.next(after:)`.
enum TourStep: Int, CaseIterable { case read, stars, moon, moonCard, star }

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourStep: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [TourStep: Anchor<CGRect>],
                       nextValue: () -> [TourStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's bounds as the anchor for one tour step.
    func tourAnchor(_ step: TourStep) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [step: $0] }
    }
}
