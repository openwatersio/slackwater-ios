// Slackwater — GPL v3. Which stations publish a calendar: one for free, as many as you like with Premium (notifications spec §7.4).
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

    /// A calendar (and its events) about to go away before this toggle finishes — an outright
    /// turn-off, or the free tier's swap. `on` is nil for a plain turn-off and set to the
    /// station the swap is turning on next; one confirmation covers both (global constraint:
    /// nothing synced vanishes without the user reading the cost first).
    private struct PendingRemoval: Identifiable {
        let off: String
        let offName: String
        let events: Int
        let on: String?
        var id: String { off }
    }

    private func name(_ stationID: String) -> String { StationItem.byId[stationID]?.name ?? stationID }

    /// A station can publish only what this device can predict offline. An online-only CHS
    /// gate has no loader record, so it has nothing to write (spec §8).
    private func canPublish(_ stationID: String) -> Bool {
        WidgetStationLoader.loadRecord(id: stationID) != nil
    }

    var body: some View {
        ScrollView {
            // A plain VStack, not LazyVStack or List: a Toggle hosted in either of those never
            // delivers its tap to the Toggle's own Binding on this simulator's iOS build — a
            // person's tap would hit the same dead control, not just this test harness. The
            // favorites list a person stars is small; eager layout costs nothing here.
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
                    Text("One station's calendar is free. Slackwater Premium publishes as many as you like, each its own calendar you can switch on and off.")
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
        .confirmationDialog(pendingTitle, isPresented: pendingPrompt, presenting: pending) { removal in
            Button(removal.on == nil ? "Turn Off" : "Replace", role: .destructive) { Task { await apply(removal) } }
            if removal.on != nil { Button("Get Premium") { showPremium = true } }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text(removalMessage(removal))
        }
    }

    private var pendingTitle: String {
        guard let pending else { return "" }
        return pending.on == nil ? "Turn off \(pending.offName)?" : "Replace \(pending.offName)?"
    }

    private func removalMessage(_ removal: PendingRemoval) -> String {
        let events = removal.events == 0 ? "" :
            " and its \(removal.events) upcoming event\(removal.events == 1 ? "" : "s")"
        return "\(removal.offName)'s calendar\(events) will be removed."
            + (removal.on == nil ? "" : " One station's calendar is free.")
    }

    private var pendingPrompt: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func row(_ stationID: String) -> some View {
        let on = calendars.subscriptions.contains { $0.stationID == stationID }
        let publishable = canPublish(stationID)
        return Toggle(isOn: Binding(get: { on }, set: { _ in Task { await toggle(stationID) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name(stationID)).foregroundStyle(.white)
                Text(publishable
                     ? (on ? stationCalendarTitle(name: name(stationID),
                                                  kind: WidgetStationLoader.loadRecord(id: stationID)!.calendarKind)
                           : "Publish this station's events")
                     : "Needs a download before it can publish")
                    .font(.caption)
                    .foregroundStyle(SN.foam.opacity(0.62))
            }
        }
        .disabled(!publishable)
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
            pending = PendingRemoval(off: stationID, offName: name(stationID),
                                     events: AlertCalendar.futureEventCount(for: stationID, now: appNow()),
                                     on: nil)
        case .add:
            guard await grantedAccess() else { return }
            await subscribeAndVerify(stationID)
        case .replace(let off):
            guard await grantedAccess() else { return }
            pending = PendingRemoval(off: off, offName: name(off),
                                     events: AlertCalendar.futureEventCount(for: off, now: appNow()),
                                     on: stationID)
        }
    }

    private func apply(_ removal: PendingRemoval) async {
        AlertCalendar.removeCalendar(for: removal.off)
        calendars.unsubscribe(removal.off)
        pending = nil
        if let on = removal.on { await subscribeAndVerify(on) }
    }

    /// Subscribes, then runs the scheduler's own reschedule — the same pass `onChange` already
    /// fires in the background, awaited directly here so this toggle can see the outcome.
    /// `subscribe` first: `StationCalendarStore.setCalendarID` silently drops the id for a
    /// station not yet subscribed. EventKit's writes in `AlertCalendar` are all `try?` with no
    /// logging, so a source that refuses new calendars — Google, Exchange — would otherwise
    /// leave the toggle on with a calendar that never arrives and no explanation.
    /// ponytail: a station with zero occurrences in the 90-day horizon would read the same as a
    /// creation failure (`AlertCalendar.apply` skips making an empty calendar) — not reachable
    /// by any bundled tide or current station, which always has a next high/low or slack window
    /// inside that window.
    private func subscribeAndVerify(_ stationID: String) async {
        calendars.subscribe(stationID)
        await AlertScheduler.shared.reschedule()
        guard calendars.calendarID(for: stationID) == nil else { return }
        calendars.unsubscribe(stationID)
        failedName = name(stationID)
        failed = true
    }

    /// Checked before every add/replace — `AlertCalendar.calendarFor` itself has no permission
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
