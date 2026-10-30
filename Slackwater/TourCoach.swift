// Slackwater — GPL v3. The first-run tour: which coach mark is showing, which
// station it belongs to.
//
// App-level state read directly by the views that need it, the way
// `LinkedInstant` is — deliberately NOT a parameter, because
// a parameter on `TimelineScrubStrip` fans out to four detail views.
import CoreLocation
import SwiftUI
import UIKit

let seenTourKey = "slackwater.seenTour"

@MainActor @Observable final class TourCoach {
    /// `TourStep` lives in TourAnchor.swift so the anchors compile without
    /// this UIKit-using class; the name here is what the rest of the app says.
    typealias Step = TourStep

    static let shared = TourCoach()

    /// nil means no tour is running. Non-nil is the mark on screen.
    var step: Step?
    /// The station id the running tour belongs to. A detail for any other
    /// station must not draw its marks.
    var station: String?

    /// First launch has armed the tour but no detail has claimed it yet.
    private(set) var armed = false
    /// `.stars` and `.moon` are independent: `tourStarsTime` and
    /// `tourMoonTime` can each resolve to nil on their own (a moon only ever
    /// up in daylight, say), so one flag per step — never a single
    /// `skySteps` — or the surviving step can assert something false.
    private var starsAvailable = true
    private var moonAvailable = true

    /// Sky steps drop under VoiceOver too: the strip is an adjustable
    /// element there, and "swipe the curve" is the wrong advice.
    private var skipsStars: Bool { !starsAvailable || UIAccessibility.isVoiceOverRunning }
    /// With Settings' sun, moon and stars switched off there is no moon to
    /// point at, so that step drops. The stars step stays: it carries the
    /// tour's only swipe lesson, and the scaffold keeps it on that wording
    /// instead of gliding to an empty sky. Read at each advance, not captured
    /// by `begin`, because the switch can sync from another device mid-tour.
    private var skipsMoon: Bool {
        !moonAvailable || UIAccessibility.isVoiceOverRunning || !showsSkyBodies()
    }

    /// Called once on launch. A tour that has already been seen does not arm.
    func arm() {
        armed = !UserDefaults.standard.bool(forKey: seenTourKey)
    }

    /// Set by `handOff(to:)`: the only station that may claim the armed tour.
    private var reservedFor: String?

    /// A detail with a real timeline claims the armed tour.
    func begin(on station: String, starsAvailable: Bool, moonAvailable: Bool) {
        guard armed, reservedFor.map({ $0 == station }) ?? true else { return }
        armed = false
        reservedFor = nil
        self.station = station
        self.starsAvailable = starsAvailable
        self.moonAvailable = moonAvailable
        step = .read
    }

    /// Settings' "How to read a station" — the seen flag does not gate this.
    /// Only arms: this sheet is presented from the station LIST, not the
    /// detail, so there is no timeline here to derive `starsAvailable` /
    /// `moonAvailable` from. Leaving any in-progress step/station behind
    /// (rather than calling `begin` here) means a half-finished tour cannot
    /// linger once the caller opens the real station and `begin` fires there
    /// with the real, freshly-derived flags.
    func replay() {
        step = nil
        station = nil
        armed = true
        reservedFor = nil
    }

    /// A link replaced the first-run tour's station: re-arm the tour for the
    /// linked station alone. Reserved, because the detail being replaced is
    /// still mounted, and a timeline revision landing there would otherwise
    /// claim the tour back and then finish it on its way out.
    func handOff(to station: String) {
        guard armed || step != nil, self.station != station else { return }
        step = nil
        self.station = nil
        armed = true
        reservedFor = station
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

    private func next(after step: Step) -> Step? {
        Step.allCases
            .filter { !($0 == .stars && skipsStars) && !($0 == .moon && skipsMoon) }
            .first { $0.rawValue > step.rawValue }
    }
}

// MARK: - Where the demo scrubs to

/// An hour past the next sunset: late enough that the backdrop is actually
/// dark and the stars are worth pointing at.
private let darkMargin: TimeInterval = 3600

/// An upcoming dark instant inside coverage, or nil when none is reachable.
///
/// Read off `TimelineDay`, never searched for: `SkyState` documents why a rise
/// or set search does not belong on this page (Theme.swift), and the timeline
/// build has already paid for these.
func tourStarsTime(days: [TimelineDay], after now: Date, within coverage: ClosedRange<Date>? = nil) -> Date? {
    days.compactMap(\.sunset)
        .map { $0.addingTimeInterval(darkMargin) }
        .sorted()
        .first { $0 > now && (coverage?.contains($0) ?? true) }
}

/// The midpoint of the first span where the moon is up AND the sun is down —
/// the only kind of moment where "that is the real moon" is worth showing.
/// Nil when no such midpoint falls inside coverage.
func tourMoonTime(days: [TimelineDay], after now: Date, within coverage: ClosedRange<Date>? = nil) -> Date? {
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
    .first { $0 > now && (coverage?.contains($0) ?? true) }
}

// MARK: - Which station the tour teaches on

/// Friday Harbor: a first launch opens it before the location prompt has
/// been answered, so with no fix this is where everyone first learns to read
/// a station.
let tourFallbackStationID = "noaa/9449880"

/// Past this there is no "local water" claim worth making, and the fallback
/// is more honest than a station on another coast.
private let tourStationRangeKm = 150.0

/// The nearest bundled or Canadian tide place within range, else Friday Harbor.
/// Only identities are needed here; a Canadian detail waits for its first usable predictions.
func tourStationID(near fix: CLLocationCoordinate2D?) -> String {
    guard let fix else { return tourFallbackStationID }
    let here = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
    let stations = StationIndex.bundled.tides
        + ChsStationInfo.all.map { StationIndexInfo($0, timezone: $0.timezone) }
    let nearest = stations
        .map { ($0.id, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
        .min { $0.1 < $1.1 }
    guard let nearest, nearest.1 <= tourStationRangeKm * 1000 else { return tourFallbackStationID }
    return nearest.0
}
