// Slackwater — GPL v3. Schedules Premium alert notifications and routes a tap to the station at the event (docs/alerts.md §5.2).
import UserNotifications

/// How long from `now` until `entry` fires, or nil once its fire time is behind.
/// A reminder already behind is dropped, not sent at once: nothing records what
/// iOS has delivered, and the plan moves a reminder inside its lead to now on
/// every pass, so requesting it would buzz again on each one.
func notificationWait(for entry: AlertEntry, from now: Date) -> TimeInterval? {
    let wait = entry.occurrence.fire.timeIntervalSince(now)
    return wait > 0 ? wait : nil
}

func pendingSlackReviewNotices(_ rules: [AlertRule], notified: Set<String>) -> [AlertRule] {
    rules.filter { $0.slackNeedsReview == true && !notified.contains($0.id.uuidString) }
}

@MainActor enum AlertNotifications {
    /// Limit replacement to scheduled alert requests.
    static let prefix = "alert."

    static func authorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Never provisional: provisional delivery never reaches the Lock Screen.
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Tell people when an older one-time selection needs their attention after migration.
    static func notifySlackReview(_ rules: [AlertRule], places: [String: AlertPlace],
                                  defaults: UserDefaults = AppGroup.defaults) async {
        let key = "slackwater.sentSlackReviewNotices"
        let reviewIDs = Set(rules.filter { $0.slackNeedsReview == true }.map { $0.id.uuidString })
        var notified = Set(defaults.stringArray(forKey: key) ?? []).intersection(reviewIDs)
        defaults.set(Array(notified).sorted(), forKey: key)
        let pending = pendingSlackReviewNotices(rules, notified: notified)
        guard !pending.isEmpty, await authorized() else { return }
        let center = UNUserNotificationCenter.current()
        for rule in pending {
            let content = UNMutableNotificationContent()
            content.title = places[rule.stationID]?.name ?? "Slackwater"
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

    /// Replaces every pending alert request with `entries`.
    static func apply(_ entries: [AlertEntry]) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard await authorized() else { return }
        for entry in entries {
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
            try? await center.add(request)
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
