// Slackwater — GPL v3. Alert rules — what the user asked to be told about — and the store that keeps them.
import Foundation

/// The water event a rule watches (docs/alerts.md §3). Which stations each case
/// applies to is spec §8; a case that doesn't fit the station finds nothing.
enum AlertTrigger: Codable, Hashable {
    case slackWindowOpens
    /// A derived gate's slack: an instant, with no speed series to open a window from.
    case slack
    case currentPeak(flood: Bool)
    /// `ofDay` true: only the lowest low (or highest high) of each station-local day, the
    /// lower low of a mixed tide. Optional so rules stored before the field decode as every.
    case tideExtreme(high: Bool, ofDay: Bool? = nil)
    /// A height picked off the curve, in metres, in the direction the curve was moving.
    case tideCrossing(heightM: Double, rising: Bool)
    case eclipse
}

struct AlertRule: Codable, Identifiable, Equatable {
    var id = UUID()
    /// A `StationItem` id — `current:`-prefixed for NOAA currents.
    var stationID: String
    var trigger: AlertTrigger
    /// Set: the single occurrence on this minute, and the rule expires once it is past
    /// (spec §3). Unset: every occurrence of the trigger.
    var once: Date?
    /// Seconds before the event that the notification fires.
    var lead: TimeInterval = 0
    /// Keep only occurrences inside this band of the Sun's day; nil is any time.
    var sun: SunWindow?
    var enabled = true
    /// Set when the rule's station was replaced by a record whose chart datum
    /// could not be related to the old one (`StationSuccessor.datumShiftM`):
    /// a tide height is then a number on the wrong datum, so the rule is off
    /// until the user sets it again. Nil otherwise, never false.
    var heightNeedsReview: Bool?

    init(id: UUID = UUID(), stationID: String, trigger: AlertTrigger, once: Date? = nil,
         lead: TimeInterval = 0, sun: SunWindow? = nil, enabled: Bool = true, heightNeedsReview: Bool? = nil) {
        self.id = id; self.stationID = stationID; self.trigger = trigger
        self.once = once; self.lead = lead; self.sun = sun; self.enabled = enabled
        self.heightNeedsReview = heightNeedsReview
    }

    private enum CodingKeys: String, CodingKey { case id, stationID, trigger, once, lead, sun, daylightOnly, enabled, heightNeedsReview }

    // `daylightOnly` is the field builds before the sun window wrote and the only one they read.
    // It is still read as a fallback, and written for the two windows it can say; a golden- or
    // blue-hour rule leaves it out, so an older build cannot read the rule and keeps it as is
    // (`AlertRuleStore.unreadable`) instead of firing it at any hour and saving it that way.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        stationID = try c.decode(String.self, forKey: .stationID)
        trigger = try c.decode(AlertTrigger.self, forKey: .trigger)
        once = try c.decodeIfPresent(Date.self, forKey: .once)
        lead = try c.decode(TimeInterval.self, forKey: .lead)
        sun = try c.decodeIfPresent(SunWindow.self, forKey: .sun)
            ?? (try c.decodeIfPresent(Bool.self, forKey: .daylightOnly) == true ? .daylight : nil)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        heightNeedsReview = try c.decodeIfPresent(Bool.self, forKey: .heightNeedsReview)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(stationID, forKey: .stationID)
        try c.encode(trigger, forKey: .trigger)
        try c.encodeIfPresent(once, forKey: .once)
        try c.encode(lead, forKey: .lead)
        try c.encodeIfPresent(sun, forKey: .sun)
        switch sun {
        case nil, .daylight: try c.encode(sun == .daylight, forKey: .daylightOnly)
        case .goldenHour, .blueHour: break
        }
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(heightNeedsReview, forKey: .heightNeedsReview)
    }
}

@MainActor final class AlertRuleStore: ObservableObject {
    static let shared = AlertRuleStore(defaults: AppGroup.defaults)

    @Published private(set) var rules: [AlertRule]
    /// Assigned once at launch (SlackwaterApp.init) to the scheduler. A no-op until then,
    /// so a store built in a test never reaches the system.
    var onChange: () -> Void = {}
    private let defaults: UserDefaults
    /// Rules this build can't read — written by a newer one — kept exactly as stored and
    /// written back, so moving between builds never loses them.
    private var unreadable: [Any] = []

    /// `successors` moves rules on a station that left the bundle to the
    /// station that replaced it (`StationSuccessors`), so they keep scheduling.
    /// A tide-height rule moves its height by the datum shift between the two
    /// records; when there is none to apply, it is switched off and marked
    /// `heightNeedsReview` rather than kept on the wrong datum. A rule this
    /// build can't read keeps its station as stored.
    init(defaults: UserDefaults, successors: [String: StationSuccessor] = StationSuccessors.entries) {
        self.defaults = defaults
        let stored = defaults.data(forKey: AppGroup.alertRulesKey)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Any] } ?? []
        var readable: [AlertRule] = []
        var kept: [Any] = []
        for item in stored {
            if let data = try? JSONSerialization.data(withJSONObject: item, options: .fragmentsAllowed),
               let rule = try? JSONDecoder().decode(AlertRule.self, from: data) {
                readable.append(rule)
            } else {
                kept.append(item)
            }
        }
        rules = readable.map { rule in
            guard let successor = successors[rule.stationID] else { return rule }
            var moved = rule
            moved.stationID = successor.id
            if case .tideCrossing(let heightM, let rising) = rule.trigger {
                if let shift = successor.datumShiftM {
                    moved.trigger = .tideCrossing(heightM: heightM + shift, rising: rising)
                } else {
                    moved.enabled = false
                    moved.heightNeedsReview = true
                }
            }
            return moved
        }
        unreadable = kept
        if rules != readable { persist() }
    }

    /// Saving a rule is the user setting it, which settles a pending height review.
    func upsert(_ rule: AlertRule) {
        var rule = rule
        rule.heightNeedsReview = nil
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
        defer { onChange() }
        // An encoding failure keeps what's stored rather than overwriting it with nothing.
        guard let encoded = try? JSONEncoder().encode(rules),
              let readable = try? JSONSerialization.jsonObject(with: encoded) as? [Any],
              let data = try? JSONSerialization.data(withJSONObject: readable + unreadable)
        else { return }
        defaults.set(data, forKey: AppGroup.alertRulesKey)
    }
}

/// The event in as few words as a title allows — "Slack window", "Low tide", "Rising past 3.3 ft".
/// The place goes in front of it (`alertRuleSummary`, `alertCopy`).
func alertEventName(_ trigger: AlertTrigger, noWindow: Bool = false, imperial: Bool) -> String {
    switch trigger {
    case .slackWindowOpens: return noWindow ? String(localized: "Slack") : String(localized: "Slack window")
    case .slack: return String(localized: "Slack")
    case .currentPeak(let flood): return flood ? String(localized: "Max flood") : String(localized: "Max ebb")
    case .tideExtreme(let high, let ofDay):
        if ofDay == true { return high ? String(localized: "Higher high tide") : String(localized: "Lower low tide") }
        return high ? String(localized: "High tide") : String(localized: "Low tide")
    case .tideCrossing(let heightM, let rising):
        let height = formatHeight(heightM, imperial: imperial), unit = heightUnit(imperial: imperial)
        return rising ? String(localized: "Rising past \(height) \(unit)")
                      : String(localized: "Falling past \(height) \(unit)")
    case .eclipse: return String(localized: "Lunar eclipse")
    }
}

/// "Race Passage - Slack window": the place, then the event — the same shape calendar events
/// and notifications are titled with.
func alertRuleSummary(_ trigger: AlertTrigger, stationName: String, imperial: Bool) -> String {
    "\(stationName) - \(alertEventName(trigger, imperial: imperial))"
}
