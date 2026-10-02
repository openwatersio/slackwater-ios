// Slackwater — GPL v3. The watch app's entry point: one list of places (#521).
import SwiftUI

@main
struct SlackwaterWatchApp: App {
    init() {
        // Reconcile with iCloud before the list's first frame, as the phone does.
        _ = UnitsCloud.shared
        _ = FavoritesStore.shared
        // The complications read the entitlement from the App Group; this
        // keeps it current, from StoreKit, which shares the phone's purchases.
        _ = PremiumStore.shared
    }

    var body: some Scene {
        WindowGroup {
            StationBrowser()
        }
    }
}
