// Slackwater — GPL v3. The watch's own fix, one at a time (#521).
import CoreLocation

/// No continuous updates: the list re-ranks when it appears and each time
/// the app returns to the foreground, which is when a wearer looks.
final class WatchLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Fix: Hashable {
        let lat: Double
        let lon: Double
    }

    /// UI-test hook, as on the phone (LocationService): denied without asking,
    /// so no system prompt can land on top of the list and take a tap.
    private static let testDenied = CommandLine.arguments.contains("-locDenied")

    @Published private(set) var fix: Fix?
    private var fixedAt = Date.distantPast
    /// The phone's cutoff (`LocationService.recentLocation`): older than this,
    /// a fix says where the wearer was, not where they are.
    private static let maxAge: TimeInterval = 600
    /// No fix is coming: denied, restricted, or the request failed with
    /// nothing to fall back on. Until then, no fix means still locating.
    @Published private(set) var unavailable = testDenied
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func refresh() {
        guard !Self.testDenied else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: fix = nil; unavailable = true
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !Self.testDenied else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: unavailable = false; manager.requestLocation()
        case .denied, .restricted: fix = nil; unavailable = true
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, abs(l.timestamp.timeIntervalSinceNow) <= Self.maxAge else { return }
        fix = Fix(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
        fixedAt = l.timestamp
        unavailable = false
    }

    // A failed refresh keeps a fix minutes old, which beats no list; one from
    // before a long suspension could be another harbour, so it goes.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if -fixedAt.timeIntervalSinceNow > Self.maxAge { fix = nil }
        if fix == nil { unavailable = true }
    }
}
