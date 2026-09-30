// Slackwater — GPL v3. What the strip offers for the moment on the centerline (docs/alerts.md §7.1).
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

enum AlertRuleChange: Equatable {
    case upsert(AlertRule)
    case remove(UUID)
}

/// The popup's two rows (spec §7.2): this moment, or every one like it.
enum AlertPopupRow: Equatable {
    case once, every
}

/// A rule made from the popup reminds half an hour ahead; the Alerts screen changes it.
let alertPopupLead: TimeInterval = 1_800

/// The rule a row would own: same station, same trigger, and either bound to this minute or
/// not bound at all.
private func popupRule(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                       at moment: Date, row: AlertPopupRow, enabled: Bool) -> AlertRule? {
    let want: Date? = row == .once ? alertMinute(moment) : nil
    return rules.first {
        $0.stationID == stationID && $0.trigger == offer && $0.once == want && $0.enabled == enabled
    }
}

/// Which rows read on. Neither does without Premium: notifications never fire without it,
/// however the stored rule reads.
func alertPopupState(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                     at moment: Date, premium: Bool) -> (once: Bool, every: Bool) {
    guard premium else { return (false, false) }
    return (popupRule(rules, stationID: stationID, offer: offer, at: moment,
                      row: .once, enabled: true) != nil,
            popupRule(rules, stationID: stationID, offer: offer, at: moment,
                      row: .every, enabled: true) != nil)
}

/// One tap on a row: remove the rule it owns, wake the switched-off one, or make it. The
/// moment is floored, so a second tap finds the first tap's rule however the caller rounded.
func alertPopupToggle(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                      at moment: Date, row: AlertPopupRow) -> AlertRuleChange {
    if let on = popupRule(rules, stationID: stationID, offer: offer, at: moment,
                          row: row, enabled: true) {
        return .remove(on.id)
    }
    if var off = popupRule(rules, stationID: stationID, offer: offer, at: moment,
                           row: row, enabled: false) {
        off.enabled = true
        return .upsert(off)
    }
    return .upsert(AlertRule(stationID: stationID, trigger: offer,
                             once: row == .once ? alertMinute(moment) : nil,
                             lead: alertPopupLead))
}

/// The repeating row's words. A crossing needs a clause — "Every rising past 3.3 ft" is not
/// English — and everything else is its event name with a small letter.
func alertEveryLabel(_ trigger: AlertTrigger, imperial: Bool) -> String {
    switch trigger {
    case .tideCrossing(let heightM, let rising):
        return "Every time it \(rising ? "rises" : "falls") past "
            + "\(formatHeight(heightM, imperial: imperial)) \(heightUnit(imperial: imperial))"
    default:
        let name = alertEventName(trigger, imperial: imperial)
        return "Every \(name.prefix(1).lowercased())\(name.dropFirst())"
    }
}
