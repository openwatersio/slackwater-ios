// Slackwater — GPL v3. M4 FTUE location: CoreLocation wrapper + the station
// match-quality grading (tide-app spec §5f, ported from slackwater-web
// src/tides.ts matchQuality / m2SpreadMinutes — same thresholds, same M2
// gradient signal, so both apps hedge a location snap identically).
import Foundation
import CoreLocation

let seenGateKey = "slackwater.seenGate"  // mirrors the web's SEEN_GATE flag

/// Victoria Harbour — the ranking anchor when there is no fix (prototype
/// NearMe.dc.html FALLBACK: denied/undetermined still gets a Near Me list).
let fallbackFix = (lat: 48.4235, lon: -123.3705)

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published var status: CLAuthorizationStatus
    @Published var location: CLLocation?
    /// True from the moment the ask starts until a fix or a denial lands.
    @Published var locating = false

    private let manager = CLLocationManager()

    // UI-test hooks, deterministic in any simulator: `-fixLat x -fixLon y`
    // renders the located list; `-locDenied` renders the denied amber card.
    private static let testFix: CLLocation? = {
        guard let i = CommandLine.arguments.firstIndex(of: "-fixLat"),
              let j = CommandLine.arguments.firstIndex(of: "-fixLon"),
              i + 1 < CommandLine.arguments.count, j + 1 < CommandLine.arguments.count,
              let lat = Double(CommandLine.arguments[i + 1]),
              let lon = Double(CommandLine.arguments[j + 1]) else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }()
    private static let testDenied = CommandLine.arguments.contains("-locDenied")

    override private init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let fix = Self.testFix { location = fix }
    }

    var authorized: Bool {
        Self.testFix != nil
            || status == .authorizedWhenInUse || status == .authorizedAlways
    }
    var denied: Bool {
        Self.testDenied || (Self.testFix == nil && (status == .denied || status == .restricted))
    }

    /// The gate's "Use My Location": ask, or refresh if already authorized.
    func request() {
        guard Self.testFix == nil && !Self.testDenied else { return }
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
        guard Self.testFix == nil else { return }
        if authorized { manager.requestLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if authorized {
            manager.requestLocation()
        } else if status != .notDetermined {
            locating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        locating = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locating = false
    }
}

// MARK: - Distance + coordinate formatting (prototype NearMe.dc.html semantics)

/// Great-circle distance in kilometres.
func distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let r = 6371.0
    let toR = { (x: Double) in x * .pi / 180 }
    let dLa = toR(lat2 - lat1), dLo = toR(lon2 - lon1)
    let h = pow(sin(dLa / 2), 2) + cos(toR(lat1)) * cos(toR(lat2)) * pow(sin(dLo / 2), 2)
    return 2 * r * asin(sqrt(h))
}

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

// MARK: - Match quality (spec §5f; web tides.ts thresholds verbatim)

enum MatchQuality: String { case good = "good match", approximate = "approximate", nearest = "nearest station" }

/// M2 phase spread across candidate tide stations, in minutes — the tidal
/// gradient signal that keeps a same-distance snap across a pass from grading
/// like one along open shore. M2 advances 28.98°/hr.
func m2SpreadMinutes(_ phases: [Double]) -> Double {
    guard phases.count >= 2 else { return 0 }
    let spread = phases.max()! - phases.min()!
    let wrapped = min(spread, 360 - spread)
    return wrapped / 28.9841042 * 60
}

func matchQuality(distanceKm d: Double, spreadMinutes: Double) -> MatchQuality {
    if d < 2 { return .good }  // standing at the station: no snap to hedge
    if d > 40 { return .nearest }
    if spreadMinutes > 20 || d > 10 { return .approximate }
    return .good
}

/// Grade the auto-located nearest station against the fix: distance plus the
/// M2 spread of the 3 nearest bundled tide stations (web heroMatchFor).
func gradeMatch(km: Double, lat: Double, lon: Double) -> MatchQuality {
    let nearest = TideStationRecord.all
        .sorted {
            distanceKm(lat1: lat, lon1: lon, lat2: $0.latitude, lon2: $0.longitude) <
            distanceKm(lat1: lat, lon1: lon, lat2: $1.latitude, lon2: $1.longitude)
        }
        .prefix(3)
    let phases = nearest.compactMap { s in s.constituents.first { $0.name == "M2" }?.phase }
    return matchQuality(distanceKm: km, spreadMinutes: m2SpreadMinutes(phases))
}
