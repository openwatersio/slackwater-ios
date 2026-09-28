// Slackwater — GPL v3. One calendar per subscribed station, and only the calendars this app made (notifications spec §5.1).
import EventKit

/// Which calendars this run rewrites, and with what. A subscribed station that resolved gets
/// its plan even when that plan is empty — it genuinely has nothing coming, and last month's
/// events have to go. A station that could NOT be loaded is absent instead: an empty plan from
/// a CHS station still waiting on its fit would read as "delete the next 90 days".
func calendarWriteGroups(_ entries: [AlertEntry], subscribed: [String],
                         skipping: Set<String>) -> [String: [AlertEntry]] {
    var groups: [String: [AlertEntry]] = [:]
    for stationID in subscribed where !skipping.contains(stationID) { groups[stationID] = [] }
    for entry in entries where groups[entry.stationID] != nil {
        groups[entry.stationID]?.append(entry)
    }
    return groups
}

@MainActor enum AlertCalendar {
    private static let store = EKEventStore()

    /// Full access only. Write-only access can save new events but never read back or
    /// remove them, so a comfort-speed change would strand the old windows in someone's calendar.
    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Where a new calendar can go. Google and Exchange accounts refuse new calendars, so the
    /// default for new events falls back to iCloud and then to the device.
    private static var sources: [EKSource] {
        [store.defaultCalendarForNewEvents?.source].compactMap { $0 }
            + store.sources.filter { $0.sourceType == .calDAV && $0.title == "iCloud" }
            + store.sources.filter { $0.sourceType == .local }
    }

    /// Whether a calendar event's own `url` — built by `shareURL(forStationID:at:tz:) ??
    /// deepLink(forStationID:)` when this app wrote the event — names `wanted`. A shareURL
    /// carries the occurrence's own instant as a trailing path segment
    /// (`https://slackwater.xyz/<kind>/<slug>[/<instant>]`); two devices under different comfort
    /// speeds compute different instants for the same slack window, so this resolves the URL
    /// back to a station id rather than comparing URLs whole — the instant never enters the
    /// comparison. A deep link (`slackwater://station/<id>`) carries no instant at all. Any URL
    /// this app didn't mint — a hand-made event's own link — resolves to no station and never
    /// matches.
    private static func urlNames(_ wanted: String, url: URL) -> Bool {
        if let link = stationLink(from: url) { return stationItem(for: link)?.id == wanted }
        if url.scheme == "slackwater" { return stationID(from: url) == wanted }
        return false
    }

    /// Whether any of `calendar`'s future events proves this app made it for `stationID` — the
    /// only evidence available that a same-titled calendar is this station's own and not a
    /// same-named station's (340 current-station and 143 tide-station name collisions ship in the
    /// bundled catalogs) or one a person made by hand under the same title.
    private static func owns(_ calendar: EKCalendar, stationID: String, now: Date) -> Bool {
        let predicate = store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(AlertHorizon.calendar + 86_400),
            calendars: [calendar])
        return store.events(matching: predicate).contains { event in
            guard let url = event.url else { return false }
            return urlNames(stationID, url: url)
        }
    }

    /// This station's calendar: the stored identifier, else a same-titled calendar this app can
    /// prove it made for this station, else a new one.
    ///
    /// A title match alone is not enough to adopt: titles collide (two different stations can
    /// share a place name), so adopting on title alone would let one station's sync empty and
    /// overwrite another's, or capture — and later delete — a calendar a person made by hand
    /// under the same name. Ownership is proved by content instead, via `owns`: a candidate is
    /// adopted only when one of its own future events names this station, which only this app's
    /// own past sync could have written. Two same-titled, unowned calendars are both left alone
    /// — ambiguous in Calendar.app, never destructive.
    static func calendarFor(stationID: String, title: String, create: Bool, now: Date) -> EKCalendar? {
        if let id = StationCalendarStore.shared.calendarID(for: stationID),
           let existing = store.calendar(withIdentifier: id) { return existing }
        let allowed = Set(sources.map(\.sourceIdentifier))
        let candidates = store.calendars(for: .event).filter {
            $0.title == title && allowed.contains($0.source.sourceIdentifier)
        }
        if let adopted = candidates.first(where: { owns($0, stationID: stationID, now: now) }) {
            StationCalendarStore.shared.setCalendarID(adopted.calendarIdentifier, for: stationID)
            return adopted
        }
        guard create else { return nil }
        for source in sources {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.source = source
            guard (try? store.saveCalendar(calendar, commit: true)) != nil else { continue }
            StationCalendarStore.shared.setCalendarID(calendar.calendarIdentifier, for: stationID)
            return calendar
        }
        return nil
    }

    /// Turning a station off takes its events with it — that is what the confirmation the user
    /// read said would happen.
    static func removeCalendar(for stationID: String) {
        guard authorized, let id = StationCalendarStore.shared.calendarID(for: stationID),
              let calendar = store.calendar(withIdentifier: id) else { return }
        try? store.removeCalendar(calendar, commit: true)
    }

    /// How many of this station's events are still to come — the number the swap and the
    /// turn-off confirmations name.
    static func futureEventCount(for stationID: String, now: Date) -> Int {
        guard authorized, let id = StationCalendarStore.shared.calendarID(for: stationID),
              let calendar = store.calendar(withIdentifier: id) else { return 0 }
        return store.events(matching: store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(AlertHorizon.calendar + 86_400),
            calendars: [calendar])).count
    }

    /// Makes each subscribed station's calendar match its plan. `subscribed` is the caller's own
    /// snapshot, not re-read from the store here: the toggle that changes a subscription is what
    /// triggers a reschedule, so a run with a subscription change in flight is the normal case.
    /// Re-reading the store here would see a station the resolve behind `entries` neither planned
    /// for nor skipped, hand it an empty plan, and wipe a calendar that may already hold another
    /// device's events.
    static func apply(_ entries: [AlertEntry], subscribed: [String], skipping: Set<String> = [], now: Date) {
        guard authorized else { return }
        // The store is long-lived and caches what it has already seen. Without a reset, a
        // calendar another device created and synced since this process last asked stays
        // invisible here, and `calendarFor`'s ownership check creates the duplicate it exists to
        // prevent.
        store.reset()
        for (stationID, planned) in calendarWriteGroups(entries, subscribed: subscribed, skipping: skipping) {
            guard let record = WidgetStationLoader.loadRecord(id: stationID) else { continue }
            let title = stationCalendarTitle(name: record.alertPlace.name, kind: record.calendarKind)
            // Nothing planned and no calendar yet: don't make an empty one.
            guard let calendar = calendarFor(stationID: stationID, title: title,
                                             create: !planned.isEmpty, now: now) else { continue }
            sync(calendar, to: planned, now: now)
        }
    }

    /// Makes `calendar`'s future match `entries`: removes events that haven't started and are no
    /// longer planned, and adds the missing ones. An event already under way is left alone. It
    /// matches within a tolerance rather than by exact content, since the engine's event search
    /// can land an instant a second apart from one reschedule to the next.
    /// ponytail: an event the user edited by hand (moved, retitled) stops matching and is
    /// replaced. Runs on the main actor — a few hundred EventKit saves; move off it if it measures.
    private static func sync(_ calendar: EKCalendar, to entries: [AlertEntry], now: Date) {
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(AlertHorizon.calendar + 86_400),
                                                 calendars: [calendar])
        let existing = store.events(matching: predicate)
        let stored = existing.map { event in
            CalendarEventShape(title: event.title ?? "", start: event.startDate, end: event.endDate,
                               alarmOffset: event.alarms?.first?.relativeOffset)
        }
        let planned = entries.map { entry in
            CalendarEventShape(title: entry.copy.title, start: entry.occurrence.event,
                               end: entry.occurrence.end ?? entry.occurrence.event, alarmOffset: nil)
        }
        let changes = calendarChanges(existing: stored, wanted: planned, now: now)
        for i in changes.remove {
            try? store.remove(existing[i], span: .thisEvent, commit: false)
        }
        for i in changes.add {
            let entry = entries[i]
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = entry.copy.title
            event.notes = entry.copy.body
            event.startDate = entry.occurrence.event
            event.endDate = entry.occurrence.end ?? entry.occurrence.event
            event.timeZone = entry.place.tz
            event.url = entry.url
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
}
