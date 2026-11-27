// Slackwater — GPL v3. Schedules Premium alert notifications and routes a tap to the station at the event (docs/alerts.md §5.2).
import UserNotifications

/// An overdue reminder may fire while its event is still ahead.
func notificationWait(for entry: AlertEntry, from now: Date) -> TimeInterval? {
    let wait = entry.occurrence.fire.timeIntervalSince(now)
    if wait > 0 { return wait }
    return entry.occurrence.event > now ? 1 : nil
}

/// Only an explicit edit inside the lead authorizes an immediate reminder.
func immediateAlertKey(_ occurrence: AlertOccurrence, rule: AlertRule, editTimes: [String: Double],
                       previous: AlertRule? = nil, history: [AlertRuleRevision] = []) -> String? {
    guard let edited = editTimes[rule.id.uuidString],
          edited > occurrence.event.timeIntervalSince1970 - rule.lead,
          edited < occurrence.event.timeIntervalSince1970 else { return nil }
    let prior = history + (previous.map { [AlertRuleRevision(rule: $0, ended: Date(timeIntervalSince1970: edited))] } ?? [])
    if prior.contains(where: { revision in
        let old = revision.rule
        let fire = occurrence.event.addingTimeInterval(-old.lead)
        return old.enabled && old.stationID == rule.stationID && old.trigger == rule.trigger
            && old.once == rule.once && old.sun == rule.sun && revision.ended >= fire
            && edited >= fire.timeIntervalSince1970
    }) { return nil }
    return occurrence.key + "." + String(edited)
}

func selectImmediateReminders(_ occurrences: [AlertOccurrence], immediate: [String: String],
                              editTimes: [String: Double], selected: inout [String: String]) -> [String: String] {
    let valid = Set(editTimes.map { $0.key + ":" + String($0.value) })
    selected = selected.filter { valid.contains($0.key) }
    var result: [String: String] = [:]
    for occurrence in occurrences.sorted(by: { $0.event < $1.event }) {
        guard let key = immediate[occurrence.key], let edited = editTimes[occurrence.ruleID.uuidString] else { continue }
        let edit = occurrence.ruleID.uuidString + ":" + String(edited)
        if selected[edit] == nil { selected[edit] = occurrence.key }
        if selected[edit] == occurrence.key { result[occurrence.key] = key }
    }
    return result
}

enum ImmediateReminderAction { case send, keep, skip }

func immediateReminderAction(hasEdit: Bool, handled: Bool, pending: Bool) -> ImmediateReminderAction {
    guard hasEdit else { return .skip }
    if handled { return pending ? .keep : .skip }
    return .send
}

func pendingSlackReviewNotices(_ rules: [AlertRule], notified: Set<String>) -> [AlertRule] {
    rules.filter { $0.slackNeedsReview == true && !notified.contains($0.id.uuidString) }
}

@MainActor enum AlertNotifications {
    /// Limit replacement to scheduled alert requests.
    static let prefix = "alert."
    private static let ledgerKey = "slackwater.immediateAlertOccurrences"
    private static let selectedKey = "slackwater.immediateAlertSelections"

    static func selectImmediate(_ occurrences: [AlertOccurrence], immediate: [String: String],
                                editTimes: [String: Double]) -> [String: String] {
        let defaults = AppGroup.defaults
        var selected = defaults.dictionary(forKey: selectedKey) as? [String: String] ?? [:]
        let result = selectImmediateReminders(occurrences, immediate: immediate, editTimes: editTimes, selected: &selected)
        defaults.set(selected, forKey: selectedKey)
        return result
    }

    static func handledImmediateKeys(now: Date) -> Set<String> {
        let handled = AppGroup.defaults.dictionary(forKey: ledgerKey) as? [String: Double] ?? [:]
        return Set(handled.filter { $0.value > now.timeIntervalSince1970 }.keys)
    }

    static func recordActivities(_ occurrences: [AlertOccurrence], placed: Set<String>, immediate: [String: String]) {
        let defaults = AppGroup.defaults
        var handled = defaults.dictionary(forKey: ledgerKey) as? [String: Double] ?? [:]
        for occurrence in occurrences where placed.contains(occurrence.key) {
            if let key = immediate[occurrence.key] { handled[key] = occurrence.event.timeIntervalSince1970 }
        }
        defaults.set(handled, forKey: ledgerKey)
    }

    static func authorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Never provisional: provisional delivery never reaches the Lock Screen.
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Tell people when an older one-time selection needs their attention after migration.
    static func notifySlackReview(_ rules: [AlertRule], places: [String: AlertPlace], premium: Bool,
                                  defaults: UserDefaults = AppGroup.defaults) async {
        let key = "slackwater.sentSlackReviewNotices"
        let reviewIDs = Set(rules.filter { $0.slackNeedsReview == true }.map { $0.id.uuidString })
        let previous = Set(defaults.stringArray(forKey: key) ?? [])
        var notified = previous.intersection(reviewIDs)
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: previous.subtracting(reviewIDs).map { "review." + $0 })
        defaults.set(Array(notified).sorted(), forKey: key)
        let pending = pendingSlackReviewNotices(rules, notified: notified)
        guard premium, !pending.isEmpty, await authorized() else { return }
        for rule in pending {
            let content = UNMutableNotificationContent()
            content.title = places[rule.stationID]?.name
                ?? WidgetStationLoader.loadRecord(id: rule.stationID)?.alertPlace.name ?? "Slackwater"
            content.body = String(localized: "Review or delete this alert.")
            content.sound = .default
            if let url = deepLink(forStationID: rule.stationID) {
                content.userInfo = [AlertTap.urlKey: url.absoluteString]
            }
            do {
                try await center.add(UNNotificationRequest(identifier: "review." + rule.id.uuidString,
                                                           content: content, trigger: nil))
                notified.insert(rule.id.uuidString)
                defaults.set(Array(notified).sorted(), forKey: key)
            } catch {
                continue
            }
        }
    }

    /// Replaces pending requests, keeping an immediate request already handed to iOS.
    static func apply(_ entries: [AlertEntry], immediate: [String: String]) async {
        let center = UNUserNotificationCenter.current()
        let defaults = AppGroup.defaults
        let now = appNow()
        var handled = (defaults.dictionary(forKey: ledgerKey) as? [String: Double] ?? [:])
            .filter { $0.value > now.timeIntervalSince1970 }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        let kept = Set(immediate.compactMap { occurrence, key -> String? in
            let id = prefix + occurrence
            return immediateReminderAction(hasEdit: true, handled: handled[key] != nil,
                                           pending: pending.contains(id)) == .keep ? id : nil
        })
        let removed = pending.filter { !kept.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: removed)
        for id in removed {
            let occurrenceKey = String(id.dropFirst(prefix.count)) + "."
            handled = handled.filter { !$0.key.hasPrefix(occurrenceKey) }
        }
        defaults.set(handled, forKey: ledgerKey)
        guard await authorized() else { return }
        var available = max(0, AlertHorizon.notificationLimit - kept.count)
        for entry in entries {
            guard available > 0 else { break }
            let occurrence = entry.occurrence
            guard !kept.contains(prefix + occurrence.key) else { continue }
            let immediateKey = immediate[occurrence.key]
            if occurrence.fire <= appNow() {
                let wasHandled = immediateKey.map { handled[$0] != nil } ?? false
                guard immediateReminderAction(hasEdit: immediateKey != nil, handled: wasHandled,
                                              pending: false) == .send else { continue }
            }
            // Measured as each request is added, since an interval trigger counts from `add`,
            // and on the app clock, which a Debug launch can pin. An interval, not calendar
            // components: the occurrence is an absolute instant, and this stays right when the
            // phone changes time zone.
            guard let wait = notificationWait(for: entry, from: appNow()) else { continue }
            let content = UNMutableNotificationContent()
            content.title = entry.copy.title
            content.body = entry.copy.body
            content.sound = .default
            if let url = entry.url { content.userInfo = [AlertTap.urlKey: url.absoluteString] }
            let request = UNNotificationRequest(
                identifier: prefix + entry.occurrence.key, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
            do {
                try await center.add(request)
                available -= 1
                if occurrence.fire <= appNow(), let immediateKey {
                    handled[immediateKey] = occurrence.event.timeIntervalSince1970
                    defaults.set(handled, forKey: ledgerKey)
                }
            } catch {
                continue
            }
        }
    }
}

/// Where a tapped alert's link waits for the station list to open it. Published, so a list
/// that appears after a cold launch from the notification still receives it.
@MainActor final class AlertTap: ObservableObject {
    static let shared = AlertTap()
    nonisolated static let urlKey = "url"
    @Published var url: URL?
}

final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor static let shared = AlertNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// The completion-handler form, not `async`: Swift calls an async delegate's handler from the
    /// cooperative pool, and UIKit aborts when a tap from the background is completed off the main thread.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let text = response.notification.request.content.userInfo[AlertTap.urlKey] as? String
        // UIKit delivers the tap on the main thread.
        MainActor.assumeIsolated {
            if let text, let url = URL(string: text) { AlertTap.shared.url = url }
        }
        completionHandler()
    }
}
