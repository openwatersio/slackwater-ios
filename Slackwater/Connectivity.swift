// Slackwater — GPL v3. Network availability shared by the phone and watch.
import Combine
import Foundation
import Network

/// Whether downloads may attempt HTTP requests. The phone observes its path;
/// watchOS leaves connection handling to URLSession (Apple TN3135).
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    @Published private(set) var online = false
    @Published private(set) var constrained = true
    #if !os(watchOS)
    private let monitor = NWPathMonitor()
    #endif

    private init() {
        #if os(watchOS)
        // Low-level paths stay unsatisfied on ordinary watch apps (TN3135).
        // URLSession decides whether a request can connect; keep the budget small.
        online = !networkKillSwitch
        constrained = true
        #else
        #if DEBUG
        if CommandLine.arguments.contains("-connectivityUnsatisfied") { return }
        if IwlsFetcher.usesFixture || CommandLine.arguments.contains("-connectivityOnline") {
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
            let status = path.status
            let constrained = path.isConstrained
            Task { @MainActor in
                self?.online = status == .satisfied
                self?.constrained = constrained
            }
        }
        monitor.start(queue: .global(qos: .utility))
        #endif
    }
}
