// Slackwater — GPL v3. Every alert rule, grouped by station, with why each one is or isn't delivering (notifications spec §7.3).
import SwiftUI

/// The first thing that explains a quiet rule, or when its deliveries run out.
func alertStatusText(_ rule: AlertRule, _ status: AlertStatusSnapshot, premium: Bool,
                     tz: TimeZone = .current, locale: Locale = .autoupdatingCurrent) -> String {
    if !rule.enabled { return "Off" }
    if status.unresolved.contains(rule.id) { return "Waiting for station data" }
    if rule.calendar && !status.calendarAuthorized { return "Calendar access is off in Settings" }
    if rule.alert == .notification && !premium {
        return rule.calendar ? "Calendar only — notifications are Premium" : "Notifications are Premium"
    }
    if rule.alert == .notification && !status.notificationsAuthorized { return "Notifications are off in Settings" }
    guard let date = status.scheduledThrough[rule.id] else { return "Nothing coming up" }
    return "Scheduled through \(date.formatted(Date.FormatStyle(timeZone: tz).day().month(.abbreviated).locale(locale)))"
}

/// Rules grouped by the station they watch — by id, since a tide and a current station can share
/// a name (Friday Harbor has both) — in name order.
struct AlertStationGroup: Identifiable, Equatable {
    let stationID: String
    let name: String
    let rules: [AlertRule]
    var id: String { stationID }
}

func alertStationGroups(_ rules: [AlertRule], name: (String) -> String) -> [AlertStationGroup] {
    Dictionary(grouping: rules, by: \.stationID)
        .map { AlertStationGroup(stationID: $0.key, name: name($0.key), rules: $0.value) }
        .sorted { ($0.name, $0.stationID) < ($1.name, $1.stationID) }
}

struct AlertsView: View {
    @ObservedObject private var store = AlertRuleStore.shared
    @ObservedObject private var scheduler = AlertScheduler.shared
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @State private var editing: AlertRule?

    private func name(_ stationID: String) -> String { StationItem.byId[stationID]?.name ?? stationID }

    var body: some View {
        List {
            if store.rules.isEmpty {
                Text("No alerts yet. Tap Calendar or Live under any station's timeline to set one.")
                    .foregroundStyle(SN.foam.opacity(0.62))
            }
            ForEach(alertStationGroups(store.rules, name: { name($0) })) { group in
                Section(group.name) {
                    ForEach(group.rules) { rule in
                        Button { editing = rule } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alertRuleSummary(rule.trigger, stationName: group.name,
                                                      imperial: units == "imperial"))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                Text(alertStatusText(rule, scheduler.status, premium: premium.isPremium))
                                    .font(.caption)
                                    .foregroundStyle(SN.foam.opacity(0.62))
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { group.rules[$0].id }.forEach { store.remove($0) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CanvasBackground())
        .sheet(item: $editing) { rule in AlertSheet(rule: rule, stationName: name(rule.stationID)) }
    }
}
