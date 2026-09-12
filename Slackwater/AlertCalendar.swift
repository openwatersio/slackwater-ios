// Slackwater — GPL v3. Writes alert occurrences into the app's own "Slackwater" calendar, and only that one (notifications spec §5.1).
import EventKit

@MainActor enum AlertCalendar {
    private static let store = EKEventStore()

    /// Full access only. Write-only access can save new events but never read back or
    /// remove them, so a moved window would strand the old one in someone's calendar.
    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// The Slackwater calendar, created on first use in the account new events already go to,
    /// so it syncs wherever the user's calendars do. Recreated if the user deleted it.
    /// ponytail: found by saved identifier only — a reinstall, or an identifier change after a
    /// full sync, leaves the old Slackwater calendar behind. Match by title if that shows up.
    private static func slackwaterCalendar(create: Bool) -> EKCalendar? {
        if let id = AppGroup.defaults.string(forKey: AppGroup.alertCalendarKey),
           let existing = store.calendar(withIdentifier: id) { return existing }
        guard create else { return nil }
        // Google and Exchange accounts refuse new calendars: fall back to iCloud, then the device.
        let sources = [store.defaultCalendarForNewEvents?.source].compactMap { $0 }
            + store.sources.filter { $0.sourceType == .calDAV && $0.title == "iCloud" }
            + store.sources.filter { $0.sourceType == .local }
        for source in sources {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = "Slackwater"
            calendar.source = source
            guard (try? store.saveCalendar(calendar, commit: true)) != nil else { continue }
            AppGroup.defaults.set(calendar.calendarIdentifier, forKey: AppGroup.alertCalendarKey)
            return calendar
        }
        return nil
    }

    /// Makes the calendar's future match `entries`: removes events that haven't started and are
    /// no longer planned, and adds the missing ones. An event already under way is left alone.
    /// ponytail: an event the user edited by hand (moved, a second alarm) stops matching and is
    /// replaced. Runs on the main actor — a few hundred EventKit saves; move off it if it measures.
    static func apply(_ entries: [AlertEntry], now: Date) {
        guard authorized, let calendar = slackwaterCalendar(create: !entries.isEmpty) else { return }
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(AlertHorizon.calendar + 86_400),
                                                 calendars: [calendar])
        let existing = store.events(matching: predicate)
        let wanted = Dictionary(entries.map { entry -> (String, AlertEntry) in
            let end = entry.occurrence.end ?? entry.occurrence.event
            return (calendarEventKey(title: entry.copy.title, start: entry.occurrence.event, end: end,
                                     alarmOffset: entry.alarmOffset), entry)
        }, uniquingKeysWith: { first, _ in first })

        let keyed = existing.map { event in
            (key: calendarEventKey(title: event.title ?? "", start: event.startDate, end: event.endDate,
                                   alarmOffset: event.alarms?.first?.relativeOffset),
             start: event.startDate as Date)
        }
        for i in calendarEventsToRemove(keyed, wanted: Set(wanted.keys), now: now) {
            try? store.remove(existing[i], span: .thisEvent, commit: false)
        }
        let have = Set(keyed.map(\.key))
        for (key, entry) in wanted where !have.contains(key) {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = entry.copy.title
            event.notes = entry.copy.body
            event.startDate = entry.occurrence.event
            event.endDate = entry.occurrence.end ?? entry.occurrence.event
            event.timeZone = entry.place.tz
            event.url = entry.url
            if let offset = entry.alarmOffset { event.addAlarm(EKAlarm(relativeOffset: offset)) }
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
}
