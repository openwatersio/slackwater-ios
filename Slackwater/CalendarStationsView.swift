// Slackwater — GPL v3. Which stations publish a calendar, a Premium feature (docs/alerts.md §7.4).
import SwiftUI

struct CalendarStationsView: View {
    @ObservedObject private var calendars = StationCalendarStore.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    @State private var showPremium = false
    @State private var pending: PendingRemoval?
    @State private var denied = false
    @State private var failed = false
    @State private var failedName = ""
    @State private var revoked = false
    @State private var revokedName = ""

    /// A calendar (and its events) about to go away when the user confirms the turn-off
    /// (global constraint: nothing synced vanishes without the user reading the cost first).
    private struct PendingRemoval: Identifiable {
        let off: String
        let offName: String
        let events: Int
        var id: String { off }
    }

    private func name(_ stationID: String) -> String { StationItem.byId[stationID]?.name ?? stationID }

    var body: some View {
        ScrollView {
            // A plain VStack, not LazyVStack or List: a Toggle hosted in either of those never
            // delivers its tap to the Toggle's own Binding on this simulator's iOS build — a
            // person's tap would hit the same dead control, not just this test harness.
            // ponytail: eager layout, not lazy — unlike OfflineManagerList's queue (bounded by
            // construction), nothing in FavoritesStore caps how many stations a person can star.
            // Revisit (a capped list, or a lazy container once the Toggle-tap bug above is
            // understood) if a real favorites list ever gets long enough for this to measure.
            VStack(alignment: .leading, spacing: 10) {
                if favorites.ids.isEmpty {
                    Text("Save a station and it can publish its tides or slack windows to your calendar.")
                        .font(.footnote)
                        .foregroundStyle(SN.foam.opacity(0.62))
                        .accessibilityIdentifier("calendar-empty")
                }
                ForEach(favorites.ids, id: \.self) { stationID in
                    row(stationID)
                }
                if !premium.isPremium, !favorites.ids.isEmpty {
                    Text("Station calendars are part of Slackwater Premium: each station gets its own calendar you can switch on and off.")
                        .font(.caption)
                        .foregroundStyle(SN.foam.opacity(0.62))
                }
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(CanvasBackground())
        .sheet(isPresented: $showPremium) { PremiumView() }
        .alert("Calendar access is off", isPresented: $denied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Slackwater needs calendar access to publish a station's events. Turn it on in Settings → Slackwater.")
        }
        .alert("Couldn't publish \(failedName)", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Slackwater couldn't create a calendar for it. Some calendar accounts — Google, Exchange — don't allow new calendars.")
        }
        .alert("\(revokedName) is off", isPresented: $revoked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Slackwater will stop publishing to this calendar, but calendar access is off, so it can't remove the calendar itself. Delete it by hand in Calendar if you don't want it anymore.")
        }
        .confirmationDialog(pendingTitle, isPresented: pendingPrompt, presenting: pending) { removal in
            Button("Turn Off", role: .destructive) { Task { await apply(removal) } }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text(removalMessage(removal))
        }
    }

    private var pendingTitle: String {
        guard let pending else { return "" }
        return "Turn off \(pending.offName)?"
    }

    private func removalMessage(_ removal: PendingRemoval) -> String {
        let events = removal.events == 0 ? "" :
            " and its \(removal.events) upcoming event\(removal.events == 1 ? "" : "s")"
        return "\(removal.offName)'s calendar\(events) will be removed."
    }

    private var pendingPrompt: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func row(_ stationID: String) -> some View {
        let on = calendars.subscriptions.contains { $0.stationID == stationID }
        // A station can publish only what this device can predict offline. An online-only CHS
        // gate has no loader record, so it has nothing to write (spec §8). Resolved once — the
        // record is read again below for the calendar kind, and a second `loadRecord` call in
        // the same render pass would be a second catalog scan for a value already in hand.
        let record = WidgetStationLoader.loadRecord(id: stationID)
        let subtitle: String = if let record {
            on ? stationCalendarTitle(name: name(stationID), kind: record.calendarKind) : "Publish this station's events"
        } else {
            "Needs a download before it can publish"
        }
        return Toggle(isOn: Binding(get: { on }, set: { _ in Task { await toggle(stationID) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name(stationID)).foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SN.foam.opacity(0.62))
            }
        }
        .disabled(record == nil)
        .padding(16)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .accessibilityIdentifier("calendar-station-\(stationID)")
    }

    private func toggle(_ stationID: String) async {
        switch calendarSubscriptionChange(calendars.subscriptions, stationID: stationID,
                                          premium: premium.isPremium) {
        case .remove:
            // `futureEventCount`/`removeCalendar` both no-op without `authorized` (Task 5's own
            // guard) — a station subscribed while permission existed and revoked since would
            // otherwise get the normal destructive confirmation promising a deletion this device
            // cannot perform, agree to it, and keep the calendar syncing everywhere else while
            // this toggle reads off. Tell the truth instead: drop the subscription, which is all
            // this device can actually do, and say so.
            guard AlertCalendar.authorized else {
                calendars.unsubscribe(stationID)
                revokedName = name(stationID)
                revoked = true
                return
            }
            pending = PendingRemoval(off: stationID, offName: name(stationID),
                                     events: AlertCalendar.futureEventCount(for: stationID, now: appNow()))
        case .add:
            guard await grantedAccess() else { return }
            await subscribeAndVerify(stationID)
        case .upsell:
            // Station calendars are Premium. A lapsed Premium's calendars keep publishing and
            // can still be turned off; turning one on is what the tier buys.
            showPremium = true
        }
    }

    private func apply(_ removal: PendingRemoval) async {
        AlertCalendar.removeCalendar(for: removal.off)
        calendars.unsubscribe(removal.off)
        pending = nil
    }

    /// Subscribes — without notifying (`notify: false`): this call drives its own reschedule and
    /// awaits it directly below, so letting `subscribe` also fire `onChange` would start a
    /// second, unawaited pass over the same work — then runs that reschedule so this toggle can
    /// see the real outcome. `subscribe` first: `StationCalendarStore.setCalendarID` silently
    /// drops the id for a station not yet subscribed. EventKit's writes in `AlertCalendar` are
    /// all `try?` with no logging, so a source that refuses new calendars — Google, Exchange —
    /// would otherwise leave the toggle on with a calendar that never arrives and no explanation.
    /// ponytail: a station with zero occurrences in the 90-day horizon would read the same as a
    /// creation failure (`AlertCalendar.apply` skips making an empty calendar) — not reachable
    /// by any bundled tide or current station, which always has a next high/low or slack window
    /// inside that window.
    private func subscribeAndVerify(_ stationID: String) async {
        calendars.subscribe(stationID, notify: false)
        await AlertScheduler.shared.reschedule()
        guard calendars.calendarID(for: stationID) == nil else { return }
        calendars.unsubscribe(stationID)
        failedName = name(stationID)
        failed = true
    }

    /// Checked before every add — `AlertCalendar.calendarFor` itself has no permission
    /// guard, so this is what tells "no calendar permission" apart from "every source refused
    /// a new calendar" (the `failed` alert above).
    private func grantedAccess() async -> Bool {
        if AlertCalendar.authorized { return true }
        guard await AlertCalendar.requestAccess() else {
            denied = true
            return false
        }
        return true
    }
}
