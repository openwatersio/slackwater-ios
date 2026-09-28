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

    /// This station's calendar: the stored identifier, else one already carrying the title,
    /// else a new one.
    ///
    /// The title match is what keeps a second device from making a duplicate. These calendars
    /// sync, so device B turning the same station on sees device A's calendar already there —
    /// without adopting it, the user ends up with two calendars of one name and every event
    /// twice. Adopting is safe here because a station calendar's contents are a function of the
    /// station, not of anything device-local: both devices plan the same events. The exception
    /// is a current station under two different comfort speeds, which rewrite each other's
    /// windows; that setting describes one boat (spec §5.1).
    static func calendarFor(stationID: String, title: String, create: Bool) -> EKCalendar? {
        if let id = StationCalendarStore.shared.calendarID(for: stationID),
           let existing = store.calendar(withIdentifier: id) { return existing }
        let allowed = Set(sources.map(\.sourceIdentifier))
        if let adopted = store.calendars(for: .event).first(where: {
            $0.title == title && allowed.contains($0.source.sourceIdentifier)
        }) {
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

    /// Makes each subscribed station's calendar match its plan: removes events that haven't
    /// started and are no longer planned, and adds the missing ones. An event already under way
    /// is left alone. It matches within a tolerance rather than by exact content, since the
    /// engine's event search can land an instant a second apart from one reschedule to the next.
    /// ponytail: an event the user edited by hand (moved, retitled) stops matching and is
    /// replaced. Runs on the main actor — a few hundred EventKit saves; move off it if it measures.
    static func apply(_ entries: [AlertEntry], skipping: Set<String> = [], now: Date) {
        guard authorized else { return }
        let subscribed = StationCalendarStore.shared.subscriptions.map(\.stationID)
        for (stationID, planned) in calendarWriteGroups(entries, subscribed: subscribed, skipping: skipping) {
            guard let record = WidgetStationLoader.loadRecord(id: stationID) else { continue }
            let title = stationCalendarTitle(name: record.alertPlace.name, kind: record.calendarKind)
            // Nothing planned and no calendar yet: don't make an empty one.
            guard let calendar = calendarFor(stationID: stationID, title: title,
                                             create: !planned.isEmpty) else { continue }
            sync(calendar, to: planned, now: now)
        }
    }

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
