// Slackwater — GPL v3. M4 FTUE location: the CoreLocation wrapper
// (tide-app spec §5f).
import Foundation
import CoreLocation
import WidgetKit

let seenGateKey = "slackwater.seenGate"  // mirrors the web's SEEN_GATE flag

/// Victoria Harbour — the last-resort ranking anchor, used only on a first run
/// with no fix and nothing opened yet. Everywhere else the anchor follows the
/// user: a real fix first, then the station they last opened (prototype
/// NearMe.dc.html FALLBACK: denied/undetermined still gets a Near Me list).
/// Before world coverage this was `fallbackFix` and it was the ONLY fallback,
/// which is why the app opened in the Solent and ranked from Vancouver Island.
let firstRunFix = (lat: 48.4235, lon: -123.3705)

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published var status: CLAuthorizationStatus
    @Published var location: CLLocation?
    /// True from the moment the ask starts until a fix or a denial lands.
    @Published var locating = false

    private let manager = CLLocationManager()

    // UI-test hooks, deterministic in any simulator: `-fixLat x -fixLon y`
    // renders the located list; the other two cover the no-fix slot states.
    private static let testFix: CLLocation? = {
        guard let i = CommandLine.arguments.firstIndex(of: "-fixLat"),
              let j = CommandLine.arguments.firstIndex(of: "-fixLon"),
              i + 1 < CommandLine.arguments.count, j + 1 < CommandLine.arguments.count,
              let lat = Double(CommandLine.arguments[i + 1]),
              let lon = Double(CommandLine.arguments[j + 1]) else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }()
    private static let testDenied = CommandLine.arguments.contains("-locDenied")
    private static let testAuthorizedNoFix = CommandLine.arguments.contains("-locAuthorizedNoFix")

    override private init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let fix = Self.testFix {
            location = fix
        } else if authorized {
            location = Self.recentLocation(manager.location)
        }
    }

    var authorized: Bool {
        Self.testFix != nil || Self.testAuthorizedNoFix
            || status == .authorizedWhenInUse || status == .authorizedAlways
    }
    var denied: Bool {
        Self.testDenied || (!Self.testAuthorizedNoFix && Self.testFix == nil
            && (status == .denied || status == .restricted))
    }

    /// The gate's "Use My Location": ask, or refresh if already authorized.
    func request() {
        guard Self.testFix == nil && !Self.testDenied && !Self.testAuthorizedNoFix else { return }
        locating = true
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorized {
            manager.requestLocation()
        } else {
            locating = false
        }
    }

    /// Silent refresh on later launches — never prompts.
    func refreshIfAuthorized() {
        guard Self.testFix == nil && !Self.testAuthorizedNoFix && authorized else { return }
        location = Self.recentLocation(manager.location) ?? location
        locating = location == nil
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !Self.testAuthorizedNoFix else { return }
        status = manager.authorizationStatus
        if authorized {
            manager.requestLocation()
        } else if status != .notDetermined {
            locating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        if let coordinate = location?.coordinate,
           Self.cacheNearestWidgetStation(lat: coordinate.latitude, lon: coordinate.longitude) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        locating = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locating = false
    }
}

extension LocationService {
    static func recentLocation(_ location: CLLocation?, now: Date = .now) -> CLLocation? {
        guard let location, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSince(now)) <= 600 else { return nil }
        return location
    }

    static func cacheNearestWidgetStation(
        lat: Double, lon: Double, defaults: UserDefaults = AppGroup.defaults
    ) -> Bool {
        guard let id = StationItem.all.min(by: {
            $0.km(fromLat: lat, lon: lon) < $1.km(fromLat: lat, lon: lon)
        })?.id,
        defaults.string(forKey: AppGroup.currentLocationStationKey) != id else { return false }
        defaults.set(id, forKey: AppGroup.currentLocationStationKey)
        return true
    }

    /// What Near Me ranks distances from: a real fix first, then the station
    /// the user last opened, and only a fixed coordinate on a genuine first
    /// run with neither. Not Optional: the last branch always returns, so an
    /// Optional made every caller write a `?? firstRunFix` that could never
    /// run and read as load-bearing anyway.
    @MainActor var rankingAnchor: (lat: Double, lon: Double) {
        // Gated like `SlackwaterApp`'s `fix`: `location` is never cleared on
        // revocation (only `status`/`locating` change in
        // `locationManagerDidChangeAuthorization`), so an unguarded read here
        // would keep ranking off a stale fix forever after the user revokes
        // permission in Settings.
        if authorized, let fix = location { return (fix.coordinate.latitude, fix.coordinate.longitude) }
        if let last = RecentsStore.shared.lastOpened { return (last.latitude, last.longitude) }
        return firstRunFix
    }
}

// MARK: - Distance + coordinate formatting (prototype NearMe.dc.html semantics)

/// "1.2 nm" / "14 nm" — the prototype's fmtDist.
func formatNm(_ km: Double) -> String {
    let nm = km / 1.852
    return (nm < 10 ? String(format: "%.1f", nm) : "\(Int(nm.rounded()))") + " nm"
}

/// "48.423°N, 123.371°W" — the prototype's fmtCoord.
func formatCoord(lat: Double, lon: Double) -> String {
    String(format: "%.3f°%@, %.3f°%@", abs(lat), lat >= 0 ? "N" : "S",
           abs(lon), lon >= 0 ? "E" : "W")
}
