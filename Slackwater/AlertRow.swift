// Slackwater — GPL v3. Calendar and Live under the strip: set an alert for the moment on screen (notifications spec §7.1).
import SwiftUI

/// Always on screen and never disabled, so it never flickers while someone scrubs. A tap only
/// counts once the strip has rested (`Timeline.rest`), because until then the centerline isn't
/// a moment anyone chose. The buttons show the resting moment's rule, not every frame's.
struct AlertRow: View {
    let stationID: String
    let offer: AlertTrigger
    let scrubTime: Date

    @ObservedObject private var store = AlertRuleStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    /// True once the strip has rested on the current `scrubTime`.
    @State private var settled = false
    /// The offer at the last rest — what the buttons show, so they don't change every frame.
    @State private var shown: AlertTrigger?
    @State private var showPremium = false

    var body: some View {
        let state = alertRowState(store.rules, stationID: stationID, offer: shown ?? offer)
        HStack(spacing: 10) {
            button("Calendar", image: state.calendar ? "calendar.badge.checkmark" : "calendar.badge.plus",
                   on: state.calendar, id: "alert-calendar-button") { tap(.calendar) }
            button("Live", image: state.live ? "bell.fill" : "bell",
                   on: state.live, id: "alert-live-button") { tap(.live) }
        }
        .task(id: scrubTime) {
            // A cancelled sleep is a scrub still in motion, not a rest.
            settled = false
            guard (try? await Task.sleep(for: Timeline.rest)) != nil else { return }
            shown = offer
            settled = true
        }
        // The third upsell surface (widgets-premium §5): only Live leads here.
        .sheet(isPresented: $showPremium) { PremiumView() }
    }

    private func tap(_ delivery: AlertDelivery) {
        guard settled, let offer = shown else { return }
        if delivery == .live && !premium.isPremium {
            showPremium = true
            return
        }
        let change = alertRowToggle(store.rules, stationID: stationID, offer: offer, delivery: delivery)
        Task {
            // Each permission is asked the first time its mechanism is turned on, never at launch.
            if case .upsert(let rule) = change {
                if delivery == .calendar, rule.calendar, !AlertCalendar.authorized {
                    _ = await AlertCalendar.requestAccess()
                }
                if delivery == .live, rule.alert == .notification {
                    _ = await AlertNotifications.requestAccess()
                }
            }
            switch change {
            case .upsert(let rule): store.upsert(rule)
            case .remove(let id): store.remove(id)
            }
        }
    }

    private func button(_ title: String, image: String, on: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Label(title, systemImage: image)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? SN.leaf : .white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(SN.cardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? SN.leaf.opacity(0.6) : SN.cardStroke, lineWidth: on ? 1 : 0.5))
            .contentShape(Capsule())
            // A tap gesture, not a Button: Button press tracking goes dead in the iPad split
            // layout's detail column (ReadoutTile, MultiDaySchedule).
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier(id)
    }
}
