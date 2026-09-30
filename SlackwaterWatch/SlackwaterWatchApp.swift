// Slackwater — GPL v3. The watch app's entry point: one list of places (#521).
import SwiftUI

@main
struct SlackwaterWatchApp: App {
    init() {
        // Reconcile with iCloud before the list's first frame, as the phone does.
        _ = UnitsCloud.shared
        _ = FavoritesStore.shared
    }

    var body: some Scene {
        WindowGroup {
            Text(verbatim: "Slackwater")
                .foregroundStyle(SN.foam)
        }
    }
}
