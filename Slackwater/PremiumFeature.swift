// Slackwater — GPL v3. The Premium features the sheet pages through, in carousel order.
import SwiftUI

enum PremiumFeature: String, CaseIterable, Identifiable {
    case alerts, calendars, lockScreen, watch, sky

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .alerts: "Alerts"
        case .calendars: "Calendars"
        case .lockScreen: "Lock screen"
        case .watch: "Watch complications"
        case .sky: "Sky controls"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .alerts: "A reminder before the slack or tide you're waiting for, right on your lock screen."
        case .calendars: "Tides and slack windows in your calendar, next to your plans."
        case .lockScreen: "The next tide without unlocking your phone."
        case .watch: "The tide on your watch face."
        case .sky: "A quieter chart, without the sun, moon and stars."
        }
    }

    var symbol: String {
        switch self {
        case .alerts: "bell"
        case .calendars: "calendar"
        case .lockScreen: "lock.iphone"
        case .watch: "applewatch"
        case .sky: "moon.stars"
        }
    }

    /// The comparison table's row label.
    var tableLabel: LocalizedStringKey {
        switch self {
        case .alerts: "Alerts"
        case .calendars: "Calendars"
        case .lockScreen: "Lock screen widgets"
        case .watch: "Watch complications"
        case .sky: "Sky controls"
        }
    }

    /// Lock screen widgets are a phone feature.
    static func carousel(for platform: SettingsPlatform) -> [PremiumFeature] {
        allCases.filter { $0 != .lockScreen || platform == .mobile }
    }
}
