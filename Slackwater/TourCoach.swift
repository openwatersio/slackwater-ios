// Slackwater — GPL v3. The first-run tour: which coach mark is showing, which
// station it belongs to, and the token the strip watches to animate a glide.
//
// App-level state read directly by the views that need it, the way
// `LinkedInstant` is (GateView.swift) — deliberately NOT a parameter, because
// a parameter on `TimelineScrubStrip` fans out to four detail views.
import CoreLocation
import SwiftUI

let seenTourKey = "slackwater.seenTour"

@Observable final class TourCoach {
    /// In order. `stars` and `moon` are dropped when the window holds no night
    /// (see `skySteps`), so never advance by `rawValue` — use `next(after:)`.
    enum Step: Int, CaseIterable { case read, stars, moon, moonCard, star }

    static let shared = TourCoach()

    /// nil means no tour is running. Non-nil is the mark on screen.
    var step: Step?
    /// The station id the running tour belongs to. A detail for any other
    /// station must not draw its marks.
    var station: String?
    /// Bumped to ask the strip for an animated ride; see `glide(to:)`.
    var glideToken = 0

    /// First launch has armed the tour but no detail has claimed it yet.
    private(set) var armed = false
    private var skySteps = true

    /// Called once on launch. A tour that has already been seen does not arm.
    func arm() {
        armed = !UserDefaults.standard.bool(forKey: seenTourKey)
    }

    /// A detail with a real timeline claims the armed tour.
    func begin(on station: String, skySteps: Bool) {
        guard armed else { return }
        armed = false
        self.station = station
        self.skySteps = skySteps
        step = .read
    }

    /// Settings' "How to read a station" — the seen flag does not gate this.
    func replay(on station: String, skySteps: Bool) {
        armed = true
        begin(on: station, skySteps: skySteps)
    }

    func advance() {
        guard let step else { return }
        if let next = next(after: step) { self.step = next } else { finish() }
    }

    /// Skip, or leaving the detail. One way: the seen flag is written here and
    /// nowhere else, and there is no resume-later state by design. A guard
    /// ensures this runs only when a tour is actually showing (step != nil);
    /// a stray call when no tour is running would suppress it forever.
    func finish() {
        guard step != nil else { return }
        step = nil
        station = nil
        armed = false
        UserDefaults.standard.set(true, forKey: seenTourKey)
    }

    func requestGlide() { glideToken += 1 }

    private func next(after step: Step) -> Step? {
        Step.allCases
            .filter { skySteps || ($0 != .stars && $0 != .moon) }
            .first { $0.rawValue > step.rawValue }
    }
}

// MARK: - Where the demo scrubs to

/// An hour past the next sunset: late enough that the backdrop is actually
/// dark and the stars are worth pointing at.
private let darkMargin: TimeInterval = 3600

/// The moment the tour glides to for its stars beat, or nil above the Arctic
/// Circle in summer, where the window holds no sunset at all.
///
/// Read off `TimelineDay`, never searched for: `SkyState` documents why a rise
/// or set search does not belong on this page (Theme.swift), and the timeline
/// build has already paid for these.
func tourStarsTime(days: [TimelineDay], after now: Date) -> Date? {
    days.compactMap(\.sunset)
        .sorted()
        .first { $0.addingTimeInterval(darkMargin) > now }
        .map { $0.addingTimeInterval(darkMargin) }
}

/// The midpoint of the first span where the moon is up AND the sun is down —
/// the only kind of moment where "that is the real moon" is worth showing.
/// Nil when no such span falls in the window.
func tourMoonTime(days: [TimelineDay], after now: Date) -> Date? {
    let sunsets = days.compactMap(\.sunset).sorted()
    let sunrises = days.compactMap(\.sunrise).sorted()
    // A dark span runs from a sunset to the next sunrise after it.
    let dark: [(Date, Date)] = sunsets.compactMap { set in
        sunrises.first { $0 > set }.map { (set, $0) }
    }
    let moonUp: [(Date, Date)] = days.compactMap { d in
        guard let rise = d.moonrise else { return nil }
        // ponytail: a moonset without an in-window moonrise is dropped here. This is safe:
        // such a span already up when the window opened has a midpoint at least three days
        // before `now` (window spans offsets −3…8), and the `midpoint > now` filter discards it
        // anyway. Revisit only if the tour is run on a detail whose anchor is not today.
        guard let set = days.compactMap(\.moonset).sorted().first(where: { $0 > rise })
        else { return nil }
        return (rise, set)
    }
    return dark.flatMap { d in
        moonUp.compactMap { m -> Date? in
            let lo = max(d.0, m.0), hi = min(d.1, m.1)
            guard lo < hi else { return nil }
            return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
        }
    }
    .sorted()
    .first { $0 > now }
}

// MARK: - Which station the tour teaches on

/// Friday Harbor — the station the gate already showed as its example
/// (GateView.swift), so the card someone just looked at is the one they now
/// learn to read.
let tourFallbackStationID = "noaa/9449880"

/// Past this there is no "local water" claim worth making, and the fallback
/// is more honest than a station on another coast.
private let tourStationRangeKm = 150.0

/// The nearest bundled tide station to the fix, else Friday Harbor.
///
/// Reads `StationIndex.bundled`, the identity-only index — never
/// `StationItem.all`, whose decode is the launch cost #317 is about. Bundled
/// stations need no download, which is what lets the tour run with no network
/// and no location at all.
func tourStationID(near fix: CLLocationCoordinate2D?) -> String {
    guard let fix else { return tourFallbackStationID }
    let here = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
    let nearest = StationIndex.bundled.tides
        .map { ($0.id, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
        .min { $0.1 < $1.1 }
    guard let nearest, nearest.1 <= tourStationRangeKm * 1000 else { return tourFallbackStationID }
    return nearest.0
}
