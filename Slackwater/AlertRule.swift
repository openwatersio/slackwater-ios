// Slackwater — GPL v3. Alert rules — what the user asked to be told about — and the store that keeps them.
import Foundation

/// The water event a rule watches (notifications spec §3). Which stations each case
/// applies to is spec §8; a case that doesn't fit the station finds nothing.
enum AlertTrigger: Codable, Equatable {
    case slackWindowOpens
    /// A derived gate's slack: an instant, with no speed series to open a window from.
    case slack
    case currentPeak(flood: Bool)
    case tideExtreme(high: Bool)
    /// A height picked off the curve, in metres, in the direction the curve was moving.
    case tideCrossing(heightM: Double, rising: Bool)
    case eclipse
}

enum AlertLevel: String, Codable {
    case none, notification
}

struct AlertRule: Codable, Identifiable, Equatable {
    var id = UUID()
    /// A `StationItem` id — `current:`-prefixed for NOAA currents.
    var stationID: String
    var trigger: AlertTrigger
    /// Seconds before the event that a notification fires and a Premium calendar alarm rings.
    var lead: TimeInterval = 0
    var daylightOnly = false
    /// Free: write occurrences into the Slackwater calendar.
    var calendar = true
    /// Premium: interrupt.
    var alert: AlertLevel = .none
    var enabled = true
}

@MainActor final class AlertRuleStore: ObservableObject {
    static let shared = AlertRuleStore(defaults: AppGroup.defaults)

    @Published private(set) var rules: [AlertRule]
    /// Assigned once at launch (SlackwaterApp.init) to the scheduler. A no-op until then,
    /// so a store built in a test never reaches the system.
    var onChange: () -> Void = {}
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        rules = defaults.data(forKey: AppGroup.alertRulesKey)
            .flatMap { try? JSONDecoder().decode([AlertRule].self, from: $0) } ?? []
    }

    func upsert(_ rule: AlertRule) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[i] = rule
        } else {
            rules.append(rule)
        }
        persist()
    }

    func remove(_ id: UUID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(rules), forKey: AppGroup.alertRulesKey)
        onChange()
    }
}

/// The event in as few words as a title allows — "Slack window", "Low tide", "Rising past 3.3 ft".
/// The place goes in front of it (`alertRuleSummary`, `alertCopy`).
func alertEventName(_ trigger: AlertTrigger, noWindow: Bool = false, imperial: Bool) -> String {
    switch trigger {
    case .slackWindowOpens: noWindow ? "Slack" : "Slack window"
    case .slack: "Slack"
    case .currentPeak(let flood): flood ? "Max flood" : "Max ebb"
    case .tideExtreme(let high): high ? "High tide" : "Low tide"
    case .tideCrossing(let heightM, let rising):
        "\(rising ? "Rising" : "Falling") past \(formatHeight(heightM, imperial: imperial)) \(heightUnit(imperial: imperial))"
    case .eclipse: "Lunar eclipse"
    }
}

/// "Race Passage - Slack window": the place, then the event — the same shape calendar events
/// and notifications are titled with.
func alertRuleSummary(_ trigger: AlertTrigger, stationName: String, imperial: Bool) -> String {
    "\(stationName) - \(alertEventName(trigger, imperial: imperial))"
}
