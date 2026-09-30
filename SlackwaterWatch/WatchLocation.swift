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
        guard let c = locations.last?.coordinate else { return }
        fix = Fix(lat: c.latitude, lon: c.longitude)
        unavailable = false
    }

    // A failed refresh keeps the last fix: stale by minutes beats no list.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if fix == nil { unavailable = true }
    }
}
