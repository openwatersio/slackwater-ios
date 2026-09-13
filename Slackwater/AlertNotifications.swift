// Slackwater — GPL v3. Schedules Premium alert notifications and routes a tap to the station at the event (notifications spec §5.2).
import UserNotifications

@MainActor enum AlertNotifications {
    /// Every request this writer owns. Nothing else in the app schedules notifications, but
    /// the prefix keeps a replace from ever touching one that isn't ours.
    static let prefix = "alert."

    static func authorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Never provisional: provisional delivery never reaches the Lock Screen.
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces every pending alert request with `entries`.
    static func apply(_ entries: [AlertEntry]) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard await authorized() else { return }
        for entry in entries {
            // An interval, not calendar components: the occurrence is an absolute instant,
            // and this stays right when the phone changes time zone.
            let wait = entry.occurrence.fire.timeIntervalSinceNow
            guard wait > 0 else { continue }
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
    static let shared = AlertNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo[AlertTap.urlKey] as? String,
              let url = URL(string: text) else { return }
        await MainActor.run { AlertTap.shared.url = url }
    }
}
