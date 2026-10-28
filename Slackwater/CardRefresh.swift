import SwiftUI

extension EnvironmentValues {
    @Entry var cardRefreshTime: Date? = nil
}

struct CardRefreshModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var time = appNow()
    var interval: Duration = .seconds(PIN_REFRESH_S)
    var now: () -> Date = appNow

    func body(content: Content) -> some View {
        content.environment(\.cardRefreshTime, time)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                // The launch task and first frame share one fresh calculation.
                let resumed = now()
                if abs(resumed.timeIntervalSince(time)) >= 1 { time = resumed }
                while !Task.isCancelled {
                    guard (try? await Task.sleep(for: interval)) != nil else { return }
                    time = now()
                }
            }
    }
}

// An eager preview can be newer than the scene's last tick.
func cardCalculationIsCurrent(_ calculatedAt: Date?, refreshTime: Date?) -> Bool {
    guard let calculatedAt else { return false }
    guard let refreshTime else { return true }
    return (0..<PIN_REFRESH_S).contains(calculatedAt.timeIntervalSince(refreshTime))
}

// Newly mounted cards start at the actual time, between scene ticks too.
func cardCalculationTime(_ refreshTime: Date?) -> Date {
    max(refreshTime ?? .distantPast, appNow())
}

struct CardRefreshInput<Record: Equatable>: Equatable {
    let time: Date?
    let record: Record
    var settings = ""
}

// A foreground tick can refresh many harmonic models together.
func cardPrediction<Value: Sendable>(_ build: @escaping @Sendable () -> Value) async -> Value? {
    guard !Task.isCancelled else { return nil }
    let value = await Task.detached(priority: .utility, operation: build).value
    return Task.isCancelled ? nil : value
}
