// Slackwater — GPL v3. The moment a shared station link carried, on its way
// from the list to the detail it opens.
import SwiftUI

/// The moment a shared station link carried, waiting for the detail of the
/// station it named (#187). The link opens its station by pushing it, and
/// the pushed detail is what owns the scrub time — so the instant waits here,
/// tagged with the station, and only that station's detail may take it: a
/// list row pushes through a bare `NavigationLink`, so nothing else resets
/// this, and an untagged value would land on whatever opened next. Observable
/// so a detail already on screen sees a second link arrive.
@MainActor @Observable final class LinkedInstant {
    struct Link: Equatable {
        let station: String   // a StationItem id
        let at: Date
    }
    static let shared = LinkedInstant()
    var pending: Link?

    /// The instant for `station`, if one is waiting — and it stops waiting.
    func take(for station: String) -> Date? {
        guard let pending, pending.station == station else { return nil }
        self.pending = nil
        return pending.at
    }
}
