// Slackwater — GPL v3. The watch's own fix, one at a time (#521).
import CoreLocation

/// No continuous updates: the list re-ranks when it appears and each time
/// the app returns to the foreground, which is when a wearer looks.
final class WatchLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Fix: Hashable {
        let lat: Double
        let lon: Double
    }

    @Published private(set) var fix: Fix?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: fix = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: fix = nil
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        fix = Fix(lat: c.latitude, lon: c.longitude)
    }

    // A failed refresh keeps the last fix: stale by minutes beats no list.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
