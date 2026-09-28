// Slackwater — GPL v3. Which stations publish a calendar of their own, and what goes in one (notifications spec §5.1).
import Foundation

/// One station's calendar. `calendarID` is empty until EventKit has made or adopted it.
struct StationCalendar: Codable, Equatable, Identifiable {
    var stationID: String
    var calendarID: String = ""
    var id: String { stationID }
}

/// Which series a station reads in — the half of its calendar's title that keeps a tide
/// station and a current station of the same name apart.
enum StationCalendarKind {
    case tide, current, derived
}

extension WidgetRecord {
    var calendarKind: StationCalendarKind {
        switch self {
        case .tide: .tide
        case .current: .current
        case .derived: .derived
        }
    }
}

/// What a station's calendar publishes (spec §5.1): the planning events, not everything the
/// station knows. A current station's maxima and bare slacks would put ~8 events a day in
/// someone's calendar and make it unreadable. Eclipses come twice a year and ride along
/// everywhere.
func calendarTriggers(for kind: StationCalendarKind) -> [AlertTrigger] {
    switch kind {
    case .tide: [.tideExtreme(high: true), .tideExtreme(high: false), .eclipse]
    case .current: [.slackWindowOpens, .eclipse]
    case .derived: [.slack, .eclipse]
    }
}

/// The calendar's name, as it reads in someone's calendar list. The series is part of it
/// because a place can have both: Friday Harbor is a tide station AND a current station, and
/// one title between the two would have each run adopt the other's calendar and rewrite its
/// events.
func stationCalendarTitle(name: String, kind: StationCalendarKind) -> String {
    switch kind {
    case .tide: "\(name) Tides"
    case .current, .derived: "\(name) Currents"
    }
}

/// What turning a station's toggle does, given what is already on.
enum CalendarSubscriptionChange: Equatable {
    case add
    /// Free holds one calendar: this station goes on and the named one comes off, once the
    /// user has read what that removes (spec §5.1).
    case replace(stationID: String)
    case remove
}

func calendarSubscriptionChange(_ subscriptions: [StationCalendar], stationID: String,
                                premium: Bool) -> CalendarSubscriptionChange {
    if subscriptions.contains(where: { $0.stationID == stationID }) { return .remove }
    if !premium, let only = subscriptions.first { return .replace(stationID: only.stationID) }
    return .add
}

@MainActor final class StationCalendarStore: ObservableObject {
    static let shared = StationCalendarStore(defaults: AppGroup.defaults)

    @Published private(set) var subscriptions: [StationCalendar]
    /// Assigned once at launch (SlackwaterApp.init) to the scheduler, like AlertRuleStore's.
    var onChange: () -> Void = {}
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        subscriptions = defaults.data(forKey: AppGroup.stationCalendarsKey)
            .flatMap { try? JSONDecoder().decode([StationCalendar].self, from: $0) } ?? []
    }

    func calendarID(for stationID: String) -> String? {
        subscriptions.first { $0.stationID == stationID }
            .map(\.calendarID).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Idempotent: subscribing to a station already on keeps the calendar it already has.
    func subscribe(_ stationID: String) {
        guard !subscriptions.contains(where: { $0.stationID == stationID }) else { return }
        subscriptions.append(StationCalendar(stationID: stationID))
        persist()
    }

    func unsubscribe(_ stationID: String) {
        subscriptions.removeAll { $0.stationID == stationID }
        persist()
    }

    func setCalendarID(_ id: String, for stationID: String) {
        guard let i = subscriptions.firstIndex(where: { $0.stationID == stationID }) else { return }
        subscriptions[i].calendarID = id
        persist()
    }

    private func persist() {
        defer { onChange() }
        // An encoding failure keeps what's stored rather than overwriting it with nothing.
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        defaults.set(data, forKey: AppGroup.stationCalendarsKey)
    }
}
