// Slackwater — GPL v3. A current maximum against the maxima around it.
//
// The ranking itself is `PeakStanding`, shared with the tide's Range tile. What
// is this file's own is the one thing a current needs that a tide does not:
// floods rank against floods and ebbs against ebbs.
//
// Most gates are not symmetric — the ebb runs harder than the flood, or the
// other way about — so one combined ranking would mean the weaker direction
// never marks at all, however remarkable a given max is for that direction. A
// reader waiting on the flood is not helped by being told the ebbs are bigger.
//
// Harmonic stations only, and that is a data limit rather than a choice. An
// online gate's detail is bounded by `Timeline.window(anchor:)` — 228 elapsed
// hours, about nine and a half days — and a fortnight either side needs thirty,
// so there is no window to rank against. A derived gate has no speed at all.
import Foundation
import SlackwaterKit

enum CurrentStanding {
    /// One direction's maxima, as unsigned magnitudes.
    ///
    /// Unsigned because a ranking is about how hard the water runs, and the
    /// engine's sign carries direction, which `kind` has already selected. A
    /// signed ebb series would rank its hardest maximum last.
    static func peaks(_ events: [CurrentEvent], kind: CurrentEventKind) -> [Peak] {
        events.filter { $0.kind == kind }.map { Peak(time: $0.time, magnitude: abs($0.speed)) }
    }
}

/// What the maximum costs at slack.
///
/// The reason to open this sheet rather than read the number on the tile. A
/// slack window is a threshold crossing — the span either side of the turn
/// where the water is under the usable speed — so a harder maximum drives the
/// water through that band faster and the window closes sooner. The tile says
/// how hard; this says what it costs you.
///
/// Both figures come from the loaded timeline rather than the fortnight scan:
/// windows are measured against the reader's own slack threshold, and that is
/// a setting the scan does not carry.
func slackFact(windows: [(slack: Date, start: Date, end: Date)], around maximum: Date) -> StandingFact? {
    let minutes = { (w: (slack: Date, start: Date, end: Date)) in w.end.timeIntervalSince(w.start) / 60 }
    let durations = windows.map(minutes).filter { $0 > 0 }.sorted()
    guard durations.count >= 3,
          let nearest = windows.min(by: {
              abs($0.slack.timeIntervalSince(maximum)) < abs($1.slack.timeIntervalSince(maximum))
          }), minutes(nearest) > 0 else { return nil }
    let typical = durations[durations.count / 2]
    let here = minutes(nearest)
    // Within a tenth of usual is not worth a sentence; saying so anyway would
    // make the fact noise on the majority of maxima.
    guard abs(here - typical) / typical > 0.1 else { return nil }
    return StandingFact(text: here < typical
        ? String(localized: "Slack runs \(Int(here.rounded())) minutes around it, against about \(Int(typical.rounded())) here usually.",
                 comment: "Current sheet fact. Both integers are counts of minutes; vary by plural.")
        : String(localized: "Slack runs \(Int(here.rounded())) minutes around it, longer than the \(Int(typical.rounded())) usual here.",
                 comment: "Current sheet fact. Both integers are counts of minutes; vary by plural."))
}

/// The Next max tile's caption.
///
/// Unlike the Range tile's, this one cannot give its text up to the mark: the
/// time is the actionable half — a reader is deciding whether to go now — and
/// "beyond normal, some time" helps nobody. So the direction word carries the
/// standing and the time stays put, which costs about the same line length.
func maxCaption(standing: PeakStanding?, kind: CurrentEventKind, time: String) -> String {
    let flood = kind == .maxFlood
    guard let standing, standing.marks else {
        return flood
            ? String(localized: "Flood at \(time)", comment: "Current summary caption. The value is a localized time.")
            : String(localized: "Ebb at \(time)", comment: "Current summary caption. The value is a localized time.")
    }
    if standing.isWindowBiggest {
        return flood
            ? String(localized: "Hardest flood · \(time)", comment: "Current summary caption: no flood within fifteen days either side runs harder. The value is a localized time.")
            : String(localized: "Hardest ebb · \(time)", comment: "Current summary caption: no ebb within fifteen days either side runs harder. The value is a localized time.")
    }
    return flood
        ? String(localized: "Strong flood · \(time)", comment: "Current summary caption: this flood is far above this station's usual. The value is a localized time.")
        : String(localized: "Strong ebb · \(time)", comment: "Current summary caption: this ebb is far above this station's usual. The value is a localized time.")
}
