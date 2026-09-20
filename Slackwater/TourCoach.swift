// Slackwater — GPL v3. The first-run tour: which coach mark is showing, which
// station it belongs to, and the token the strip watches to animate a glide.
//
// App-level state read directly by the views that need it, the way
// `LinkedInstant` is (GateView.swift) — deliberately NOT a parameter, because
// a parameter on `TimelineScrubStrip` fans out to four detail views.
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
    /// nowhere else, and there is no resume-later state by design.
    func finish() {
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
