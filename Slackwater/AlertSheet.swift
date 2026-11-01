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

/// A once rule bound to a moment already past would be dropped by the reschedule its save
/// triggers (§6) — the strip shows 48 hours back, so a press can land there. Repeating rules
/// always save.
func alertSheetCanSave(_ rule: AlertRule, now: Date) -> Bool {
    rule.once.map { $0 >= now } ?? true
}

/// A moment still ahead whose reminder time is already behind: with a lead short enough for a
/// Live Activity the countdown starts on save; with a longer one there is nothing left to send.
func alertSheetStartsNow(_ rule: AlertRule, now: Date) -> Bool {
    alertSheetReminderPassed(rule, now: now) && rule.lead <= AlertHorizon.liveActivityLead
}

func alertSheetReminderPassed(_ rule: AlertRule, now: Date) -> Bool {
    guard let once = rule.once else { return false }
    return once >= now && once.addingTimeInterval(-rule.lead) <= now
}

enum AlertSheetNote: Equatable {
    case nothingAhead, nothingThatDay, notOffered, failed
}

/// What a parse does to the sheet: a rule replaces the draft wholesale — trigger, moment, lead,
/// daylight — under the draft's own id, so a sentence after a press edits the same rule; anything
/// else leaves the draft alone and says why.
func alertSheetApply(_ outcome: AlertSentenceOutcome, to rule: AlertRule,
                     boundMoment: Date?) -> (rule: AlertRule, boundMoment: Date?, note: AlertSheetNote?) {
    switch outcome {
    case .rule(var parsed, let bound):
        parsed.id = rule.id
        parsed.enabled = rule.enabled
        return (parsed, bound, nil)
    case .nothingAhead(let namedDay): return (rule, boundMoment, namedDay ? .nothingThatDay : .nothingAhead)
    case .notOffered: return (rule, boundMoment, .notOffered)
    case .failed: return (rule, boundMoment, .failed)
    }
}

struct AlertSheet: View {
    @State var rule: AlertRule
    let stationName: String
    /// The moment "Does not repeat" binds to: the pressed or centerline moment for a new rule, the
    /// rule's own `once` for an existing one, nil for one that already repeats. A sentence rebinds it.
    @State private var boundMoment: Date?
    let isNew: Bool
    /// The Rest tap opens on the field; a press and the Alerts screen open on the draft (§7.2).
    let focusSentence: Bool
    /// Read once at open (§7.3): the field must not vanish mid-sentence, and the check is not free.
    @State private var sentenceAvailable = alertSentenceAvailable
    @State private var sentence = ""
    @State private var parsing = false
    @State private var note: AlertSheetNote?
    @FocusState private var sentenceFocused: Bool
    @ObservedObject private var store = AlertRuleStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = heightUnits()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var saving = false
    @State private var showPremium = false

    init(rule: AlertRule, stationName: String, boundMoment: Date?, isNew: Bool = false,
         focusSentence: Bool = false) {
        _rule = State(initialValue: rule)
        self.stationName = stationName
        _boundMoment = State(initialValue: boundMoment)
        self.isNew = isNew
        self.focusSentence = focusSentence
    }

    private var imperial: Bool { units == "imperial" }
    private var canSave: Bool { alertSheetCanSave(rule, now: appNow()) }

    var body: some View {
        NavigationStack {
            Form {
                // The field, when the on-device model is ready (§7.3). The keyboard's own
                // dictation key is the voice input.
                if sentenceAvailable {
                    Section {
                        HStack(spacing: 8) {
                            TextField(String(localized: "Tell me when…", comment: "Placeholder of the alert sheet's sentence field."),
                                      text: $sentence)
                                .focused($sentenceFocused)
                                .submitLabel(.go)
                                .onSubmit { Task { await parse() } }
                                .disabled(parsing)
                                .accessibilityIdentifier("alert-sentence")
                            if parsing { ProgressView() }
                        }
                        if let note {
                            Text(noteText(note))
                                .font(.footnote)
                                .foregroundStyle(SN.foam.opacity(0.62))
                                .accessibilityIdentifier("alert-sentence-note")
                        }
                    }
                }
                Section {
                    Text(alertRuleSummary(rule.trigger, stationName: stationName, noWindow: slackWindowIsOff(slackThresholdKn), imperial: imperial))
                        .monospacedDigit()
                        .accessibilityIdentifier("alert-summary")
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
                    Picker("Sun", selection: $rule.sun) {
                        Text("Any time", comment: "Sun menu choice: no filter on the time of day.").tag(SunWindow?.none)
                        Text("In daylight", comment: "Sun menu choice in the alert sheet: sunrise to sunset.").tag(SunWindow?.some(.daylight))
                        Text("Golden hour").tag(SunWindow?.some(.goldenHour))
                        Text("Blue hour").tag(SunWindow?.some(.blueHour))
                    }
                    .accessibilityIdentifier("alert-sheet-sun")
                    if !canSave {
                        Text("This moment has passed", comment: "Under the alert sheet's When section, when the chosen moment is already behind us.")
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.62))
                    } else if alertSheetStartsNow(rule, now: appNow()) {
                        Text("The reminder time has passed; the countdown starts now", comment: "Under the alert sheet's When section, when the moment is ahead but less than the lead away.")
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.62))
                    } else if alertSheetReminderPassed(rule, now: appNow()) {
                        Text("The reminder time has passed", comment: "Under the alert sheet's When section, when the moment is ahead but less than the lead away and the lead is too long for a countdown.")
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.62))
                    }
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
            // After the presentation settles: focus set in onAppear is dropped by the sheet's
            // own animation on first presentation.
            .task {
                guard focusSentence, sentenceAvailable else { return }
                try? await Task.sleep(for: .milliseconds(350))
                sentenceFocused = true
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
                        .disabled(saving || !canSave || parsing)
                        .accessibilityIdentifier("alert-sheet-save")
                }
            }
            .accessibilityIdentifier("alert-sheet")
        }
        // A medium form sheet on iPad cuts the Form off above its last section, and a List
        // only materializes rows near the screen, so On and Delete are out of reach there.
        .presentationDetents(hSize == .regular ? [.large] : [.medium, .large])
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPremium) { PremiumView() }
    }

    private func noteText(_ note: AlertSheetNote) -> String {
        switch note {
        case .nothingAhead:
            return String(localized: "Nothing in the next 14 days", comment: "Under the sentence field when the ask has no occurrence coming.")
        case .nothingThatDay:
            return String(localized: "Nothing that day", comment: "Under the sentence field when the ask named a day that holds no such event.")
        case .notOffered:
            return String(localized: "Slackwater can't alert on that here yet", comment: "Under the sentence field when the words ask for something this station cannot alert on.")
        case .failed:
            return String(localized: "Couldn't read that. Try other words.", comment: "Under the sentence field when the on-device model could not answer.")
        }
    }

    /// One parse: the words → a draft → the first occurrence → the same controls the user reads
    /// and corrects before Save. The words stay in the field so what the app made of them can be
    /// read against them.
    private func parse() async {
        let words = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let record = WidgetStationLoader.loadRecord(id: rule.stationID) else { return }
        if alertSentenceOutOfScope(words, kind: record.calendarKind) {
            apply(.notOffered); return
        }
        parsing = true
        defer { parsing = false }
        guard let draft = await alertSentenceParse(words, kind: record.calendarKind, imperial: imperial) else {
            apply(.failed); return
        }
        let station = WidgetStationLoader.station(from: record)
        let threshold = slackThresholdKn
        let outcome = alertSentenceOutcome(draft, stationID: rule.stationID, now: appNow(), tz: station.tz) {
            trigger, sun, from, to in
            alertOccurrences(AlertRule(stationID: rule.stationID, trigger: trigger, sun: sun),
                             station: station, position: record.alertPosition,
                             from: from, to: to, threshold: threshold).map(\.event).first { $0 > from }
        }
        apply(outcome)
    }

    private func apply(_ outcome: AlertSentenceOutcome) {
        let r = alertSheetApply(outcome, to: rule, boundMoment: boundMoment)
        rule = r.rule
        boundMoment = r.boundMoment
        note = r.note
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
