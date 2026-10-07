// Slackwater — GPL v3. Press and hold a moment on the strip: alert me then, or every time (docs/alerts.md §7.2).
import SwiftUI

/// Two rows and a header naming what the press landed on. No lead picker: half an hour, and
/// the Alerts screen changes it. Without Premium both rows lead to Settings at Premium and no rule
/// is made — this is the third and last upsell surface (widgets-premium §5).
struct AlertPopup: View {
    let stationID: String
    let offer: AlertTrigger
    let moment: Date
    let tz: TimeZone
    let stationName: String

    @ObservedObject private var store = AlertRuleStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = heightUnits()
    @Environment(\.dismiss) private var dismiss
    @State private var showPremium = false
    /// True while a tap's permission prompt and store write are in flight: a second tap in
    /// that gap must be ignored, not read the rules as they stood before the first landed.
    @State private var applying = false

    private var imperial: Bool { units == "imperial" }

    var body: some View {
        let state = alertPopupState(store.rules, stationID: stationID, offer: offer,
                                    at: moment, premium: premium.isPremium)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stationName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SN.foam.opacity(0.62))
                    Text("\(moment.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: tz))) · \(alertEventName(offer, imperial: imperial))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                close
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider().overlay(Color.white.opacity(0.08))
            row("Alert me", on: state.once, id: "alert-popup-once") { tap(.once) }
            Divider().overlay(Color.white.opacity(0.08))
            row(alertEveryLabel(offer, imperial: imperial), on: state.every,
                id: "alert-popup-every") { tap(.every) }
        }
        .frame(width: 280)
        .background(SN.cardFill)
        .sheet(isPresented: $showPremium) { PremiumView() }
    }

    /// A way out that isn't a row: a press landed by accident must not have to set an alert to
    /// get rid of this. Dismissing by tapping outside a popover is iPad's own affordance and
    /// stays, but it is a hard target over a split layout — the UI test that relies on it takes
    /// minutes of retries to land one.
    private var close: some View {
        Image(systemName: "xmark")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SN.foam.opacity(0.62))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            // A tap gesture, not a Button, for the same reason the rows below use one.
            .onTapGesture { dismiss() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("alert-popup-close")
    }

    private func row(_ title: String, on: Bool, id: String,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: on ? "bell.fill" : "bell")
                .font(.footnote)
                .foregroundStyle(on ? SN.leaf : SN.foam.opacity(0.62))
            Text(title)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(on ? SN.leaf : .white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        // A tap gesture, not a Button: Button press tracking goes dead in the iPad split
        // layout's detail column (ReadoutTile, MultiDaySchedule).
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    private func tap(_ row: AlertPopupRow) {
        guard !applying else { return }
        guard premium.isPremium else {
            showPremium = true
            return
        }
        applying = true
        Task {
            defer { applying = false }
            // Notification permission is asked the first time a rule is made, never at launch.
            if case .upsert = alertPopupToggle(store.rules, stationID: stationID, offer: offer,
                                               at: moment, row: row) {
                _ = await AlertNotifications.requestAccess()
            }
            // Decide against the rules as they stand after the prompt, so nothing that changed
            // while it was up can turn this tap into a duplicate.
            switch alertPopupToggle(store.rules, stationID: stationID, offer: offer,
                                    at: moment, row: row) {
            case .upsert(let rule): store.upsert(rule)
            case .remove(let id): store.remove(id)
            }
            dismiss()
        }
    }
}
