// Slackwater — GPL v3. The watch app's entry point. It launches to a
// placeholder; browsing and station detail arrive in later changes (#482).
import SwiftUI

@main
struct SlackwaterWatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbatim: "Slackwater")
                .foregroundStyle(SN.foam)
        }
    }
}
