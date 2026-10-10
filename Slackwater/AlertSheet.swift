// Slackwater — GPL v3. The one sheet that makes and edits an alert rule (docs/alerts.md §7.2).
import SwiftUI

/// The repeat menu's choices: both when there is a moment to bind "Does not repeat" to, only
/// "Every …" when there is not — a rule opened from the Alerts screen that already repeats has no
/// strip to pick a moment from.
func alertRepeatChoices(boundMoment: Date?) -> [Bool] {
    boundMoment == nil ? [true] : [false, true]
}

/// Choosing "Every …" clears `once`; choosing "Does not repeat" binds the rule back to the moment
/// the sheet opened on. Everything else on the rule stays.
func alertRuleRepeating(_ rule: AlertRule, _ repeats: Bool, boundMoment: Date?) -> AlertRule {
    var out = rule
    out.once = repeats ? nil : boundMoment
    return out
}

struct AlertSheet: View {
    @State var rule: AlertRule
    let stationName: String
    /// The moment "Does not repeat" binds to: the pressed or centerline moment for a new rule, the
    /// rule's own `once` for an existing one, nil for one that already repeats.
    let boundMoment: Date?
    let isNew: Bool
    @ObservedObject private var store = AlertRuleStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = heightUnits()
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var showPremium = false

    init(rule: AlertRule, stationName: String, boundMoment: Date?, isNew: Bool = false) {
        _rule = State(initialValue: rule)
        self.stationName = stationName
        self.boundMoment = boundMoment
        self.isNew = isNew
    }

    private var imperial: Bool { units == "imperial" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(alertRuleSummary(rule.trigger, stationName: stationName, imperial: imperial))
                        .monospacedDigit()
                        .accessibilityIdentifier("alert-summary")
                    // In the station's zone, wherever the phone is reading it.
                    if let when = alertRuleWhen(rule, tz: alertStationZone(rule.stationID)) {
                        LabeledContent("This one", value: when)
                            .monospacedDigit()
                    }
                }
                Section("When") {
                    Picker("Repeat", selection: Binding(
                        get: { rule.once == nil },
                        set: { rule = alertRuleRepeating(rule, $0, boundMoment: boundMoment) })) {
                        ForEach(alertRepeatChoices(boundMoment: boundMoment), id: \.self) { repeats in
                            Text(repeats ? alertEveryLabel(rule.trigger, imperial: imperial)
                                         : String(localized: "Does not repeat",
                                                  comment: "Repeat menu choice for a one-time alert, as a calendar event would say it."))
                                .monospacedDigit()
                                .tag(repeats)
                        }
                    }
                    .accessibilityIdentifier("alert-sheet-repeat")
                    Picker("Remind me", selection: $rule.lead) {
                        ForEach(alertLeads, id: \.self) { Text(alertLeadLabel($0)).tag($0) }
                    }
                    Toggle("Daylight only", isOn: $rule.daylightOnly)
                }
                if !isNew {
                    Section {
                        Toggle("On", isOn: $rule.enabled)
                        Button("Delete Alert", role: .destructive) {
                            store.remove(rule.id)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CanvasBackground())
            .navigationTitle(isNew ? "New Alert" : "Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("alert-sheet-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                        .accessibilityIdentifier("alert-sheet-save")
                }
            }
            .accessibilityIdentifier("alert-sheet")
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPremium) { PremiumView() }
    }

    /// Being told is Premium (§2): a free user's Save opens the Support sheet and writes nothing.
    /// Notification permission is asked on the first save, never at launch; a denial still
    /// saves the rule, and the Alerts screen says why it is quiet.
    private func save() async {
        guard premium.isPremium else { showPremium = true; return }
        saving = true
        defer { saving = false }
        _ = await AlertNotifications.requestAccess()
        store.upsert(rule)
        dismiss()
    }
}
