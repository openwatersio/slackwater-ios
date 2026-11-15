// Slackwater — GPL v3. Device-local review request history.
import Foundation
import StoreKit

@MainActor
struct ReviewRequestPolicy {
    static let shared = ReviewRequestPolicy(defaults: .standard)
    private let requiredDays = 3
    let defaults: UserDefaults

    func recordForecastUse(at date: Date, calendar: Calendar = .current) {
        var days = defaults.stringArray(forKey: "review.forecastDays") ?? []
        guard days.count < requiredDays else { return }
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = calendar.timeZone
        let parts = localCalendar.dateComponents([.era, .year, .month, .day], from: date)
        let day = "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        guard !days.contains(day) else { return }
        days.append(day)
        defaults.set(days, forKey: "review.forecastDays")
    }

    // Store attempts, since StoreKit doesn't report whether it displayed a prompt.
    func consumeRequest(version: String, at date: Date, environment: AppStore.Environment = .production) -> Bool {
        guard environment == .production, !version.isEmpty,
              (defaults.stringArray(forKey: "review.forecastDays") ?? []).count >= requiredDays else { return false }
        var versions = defaults.stringArray(forKey: "review.requestedVersions") ?? []
        guard !versions.contains(version) else { return false }
        if let last = defaults.object(forKey: "review.lastRequest") as? Date,
           date.timeIntervalSince(last) < 120 * 86_400 { return false }
        versions.append(version)
        defaults.set(versions, forKey: "review.requestedVersions")
        defaults.set(date, forKey: "review.lastRequest")
        return true
    }
}

var reviewRequestsDisabled: Bool {
    CommandLine.arguments.contains("-noCloudSync") ||
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
    NSClassFromString("XCTestCase") != nil
}

struct ReviewRequestVisit {
    private(set) var id = UUID()
    private(set) var forecastLoaded = false
    var pending = false

    @discardableResult
    mutating func forecastDidLoad(visitID: UUID, isNavigating: Bool, isActive: Bool) -> Bool {
        guard visitID == id, isNavigating, isActive else { return false }
        forecastLoaded = true
        return true
    }

    mutating func beginVisit() {
        id = UUID()
        forecastLoaded = false
        pending = false
    }

    mutating func navigationChanged(from old: Int, to new: Int, available: Bool) {
        if new == 0 {
            pending = old > 0 && forecastLoaded && available
            forecastLoaded = false
            id = UUID()
        } else {
            pending = false
        }
    }

    mutating func availabilityChanged(_ available: Bool) {
        if !available { pending = false }
    }
}
