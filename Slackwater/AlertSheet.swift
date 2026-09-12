// Slackwater — GPL v3. Edit one alert rule — lead, daylight, deliveries — from the Alerts screen (notifications spec §7.2).
import SwiftUI

struct AlertSheet: View {
    @State var rule: AlertRule
    let stationName: String
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var store = AlertRuleStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @Environment(\.dismiss) private var dismiss
    @State private var showPremium = false
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
                }
                Section {
                    Toggle("Add to Calendar", isOn: $rule.calendar)
                    Toggle(isOn: notify) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notify me")
                            if !premium.isPremium {
                                Text("Slackwater Premium").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("With Slackwater Premium, calendar events carry an alarm and alerts arrive as notifications.")
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
                        .disabled(saving || (!rule.calendar && rule.alert == .none))
                }
            }
            .sheet(isPresented: $showPremium) { PremiumView() }
        }
        .preferredColorScheme(.dark)
    }

    private var notify: Binding<Bool> {
        Binding(get: { rule.alert == .notification },
                set: { on in
                    if on && !premium.isPremium {
                        showPremium = true
                        return
                    }
                    rule.alert = on ? .notification : .none
                })
    }

    /// A denial still saves the rule; the Alerts screen says why it is quiet.
    private func save() async {
        saving = true
        if rule.calendar && !AlertCalendar.authorized { _ = await AlertCalendar.requestAccess() }
        if rule.alert == .notification { _ = await AlertNotifications.requestAccess() }
        store.upsert(rule)
        dismiss()
    }
}
