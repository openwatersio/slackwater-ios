// Slackwater — GPL v3. What the strip offers for the moment on the centerline, and the draft a new rule starts from (docs/alerts.md §7.1).
import Foundation

/// A height as the strip shows it — 0.1 ft, or 0.01 m — so a crossing rule is the reading the user
/// saw, and nearby scrub positions share one rule instead of each minting its own.
func displayedHeightM(_ metres: Double, imperial: Bool) -> Double {
    imperial ? (toFeet(metres) * 10).rounded() / 10 / toFeet(1) : (metres * 100).rounded() / 100
}

/// A tide detail: the extreme the strip parked on; an eclipse contact; otherwise, once scrubbed
/// away from now, the height under the line in the direction the curve moves, rounded to the
/// precision the strip displays so nearby scrub positions share one rule. Tapping the timeline
/// lands on an arbitrary instant, and on a tide curve that instant is a height. Unscrubbed, the
/// everyday ask: the next low.
func tideAlertOffer(scrubbedAway: Bool, turnIsHigh: Bool?, onEclipseContact: Bool,
                    heightM: Double, rising: Bool, imperial: Bool) -> AlertTrigger {
    if let high = turnIsHigh { return .tideExtreme(high: high) }
    if onEclipseContact { return .eclipse }
    return scrubbedAway
        ? .tideCrossing(heightM: displayedHeightM(heightM, imperial: imperial), rising: rising)
        : .tideExtreme(high: false)
}

/// A current detail: the max the strip parked on, an eclipse contact, or else the slack window.
func currentAlertOffer(maxIsFlood: Bool?, onEclipseContact: Bool) -> AlertTrigger {
    if let flood = maxIsFlood { return .currentPeak(flood: flood) }
    return onEclipseContact ? .eclipse : .slackWindowOpens
}

/// A derived gate knows only its slacks.
func derivedAlertOffer(onEclipseContact: Bool) -> AlertTrigger {
    onEclipseContact ? .eclipse : .slack
}

/// The magnet parks `scrubTime` on a snap target's own second; ±1 s is `atTurn`'s tolerance too.
func isOnEclipseContact(_ time: Date, _ eclipses: [WindowEclipse]) -> Bool {
    eclipses.contains { $0.contacts.contains { abs($0.timeIntervalSince(time)) < 1 } }
}

/// A rule made from the line reminds half an hour ahead; the sheet changes it.
let alertNewRuleLead: TimeInterval = 1_800

/// The sheet's starting draft for a moment: bound to its minute, so a second save finds the first.
func alertNewRule(stationID: String, offer: AlertTrigger, at moment: Date) -> AlertRule {
    AlertRule(stationID: stationID, trigger: offer, once: alertMinute(moment), lead: alertNewRuleLead)
}

/// The repeat menu's words (§7.2), and the line's Set reading for a repeating rule. A crossing
/// needs a clause — "Every rising past 3.3 ft" is not English — and everything else is its event
/// name with a small letter.
func alertEveryLabel(_ trigger: AlertTrigger, imperial: Bool) -> String {
    switch trigger {
    case .tideCrossing(let heightM, let rising):
        let height = formatHeight(heightM, imperial: imperial), unit = heightUnit(imperial: imperial)
        return rising ? String(localized: "Every time it rises past \(height) \(unit)")
                      : String(localized: "Every time it falls past \(height) \(unit)")
    default:
        let name = alertEventName(trigger, imperial: imperial)
        return String(localized: "Every \(name.prefix(1).lowercased() + name.dropFirst())")
    }
}
