// Slackwater — GPL v3. Edit one alert rule — lead and daylight — from the Alerts screen (notifications spec §7.2).
import SwiftUI

struct AlertSheet: View {
    @State var rule: AlertRule
    let stationName: String
    @ObservedObject private var store = AlertRuleStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(alertRuleSummary(rule.trigger, stationName: stationName, imperial: units == "imperial"))
                        .monospacedDigit()
                        .accessibilityIdentifier("alert-summary")
                }
                Section("When") {
                    Picker("Remind me", selection: $rule.lead) {
                        ForEach(alertLeads, id: \.self) { Text(alertLeadLabel($0)).tag($0) }
                    }
                    Toggle("Daylight only", isOn: $rule.daylightOnly)
                    // ponytail: tz: .current reads the device's zone, not the station's — a
                    // Pacific rule read from an eastbound phone shows the wrong hour. The
                    // station's zone is AlertPlace.tz, but today it only exists as a local
                    // inside AlertScheduler.reschedule() (via resolveAlerts); AlertScheduler
                    // publishes just `status`. Fix needs it to also publish the resolved
                    // place table so a view can read a station's zone at all.
                    if let when = alertRuleWhen(rule, tz: .current) {
                        LabeledContent("This one", value: when)
                            .monospacedDigit()
                    }
                    // Off and disabled once the rule already repeats: there's no moment left to
                    // bind back to, and offering to pick one here would need a date picker — the
                    // long-press popover that created this rule already is one.
                    Toggle("Every time", isOn: Binding(get: { rule.once == nil },
                                                       set: { rule.once = $0 ? nil : rule.once }))
                        .disabled(rule.once == nil)
                        .accessibilityHint(rule.once == nil
                            ? "This alert repeats. There's no single moment to switch back to." : "")
                }
                Section {
                    Toggle("On", isOn: $rule.enabled)
                    Button("Delete Alert", role: .destructive) {
                        store.remove(rule.id)
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CanvasBackground())
            .navigationTitle("Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// A denial still saves the rule; the Alerts screen says why it is quiet.
    private func save() async {
        saving = true
        _ = await AlertNotifications.requestAccess()
        store.upsert(rule)
        dismiss()
    }
}
