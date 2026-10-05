// Slackwater — GPL v3. Network availability shared by the phone and watch.
import Combine
import Foundation
import Network

/// Is there a network path right now. Its own tiny observable so the indicator
/// can say offline/online without any of it leaking into the fit service.
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    @Published private(set) var online = false
    @Published private(set) var constrained = true
    private let monitor = NWPathMonitor()

    private init() {
        // The kill switch is the UI tests' airplane mode: stay offline, and
        // don't start a monitor that would immediately contradict it.
        #if DEBUG
        let forcedOnline = CommandLine.arguments.contains("-connectivityOnline")
        #else
        let forcedOnline = false
        #endif
#if DEBUG
        if IwlsFetcher.usesFixture || forcedOnline {
            online = true
            constrained = false
            return
        }
#endif
        guard !networkKillSwitch else {
            constrained = false
            return
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            let constrained = path.isConstrained
            Task { @MainActor in
                self?.online = up
                self?.constrained = constrained
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}
