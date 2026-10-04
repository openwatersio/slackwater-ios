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
        if CommandLine.arguments.contains("-connectivityUnsatisfied") {
            update(status: .unsatisfied, constrained: true)
            return
        }
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
        #if os(watchOS)
        update(status: .unsatisfied, constrained: true)
        #else
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            let constrained = path.isConstrained
            Task { @MainActor in
                self?.update(status: status, constrained: constrained)
            }
        }
        monitor.start(queue: .global(qos: .utility))
        #endif
    }

    private func update(status: NWPath.Status, constrained: Bool) {
        #if os(watchOS)
        // NWPathMonitor stays unsatisfied on a normal watch app even when
        // URLSession can use Wi-Fi, cellular, or the paired phone's network.
        online = true
        self.constrained = true
        #else
        online = status == .satisfied
        self.constrained = constrained
        #endif
    }
}
