// Slackwater — GPL v3. Settings copy follows the platform where the app is running.
import Foundation

enum SettingsPlatform: String {
    case mobile, mac, tv

    static var current: Self {
        #if DEBUG
            if let index = CommandLine.arguments.firstIndex(of: "-settingsPlatform"),
                CommandLine.arguments.indices.contains(index + 1),
                let platform = Self(rawValue: CommandLine.arguments[index + 1])
            {
                return platform
            }
        #endif
        #if os(macOS) || targetEnvironment(macCatalyst)
            return .mac
        #elseif os(tvOS)
            return .tv
        #elseif os(iOS)
            return ProcessInfo.processInfo.isiOSAppOnMac ? .mac : .mobile
        #else
            return .mobile
        #endif
    }
}
