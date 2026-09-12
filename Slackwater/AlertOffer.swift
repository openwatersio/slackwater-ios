// Slackwater — GPL v3. What the alert row offers for the moment under the centerline, and what a tap on it does (notifications spec §7.1).
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

enum AlertDelivery {
    case calendar, live
}

enum AlertRuleChange: Equatable {
    case upsert(AlertRule)
    case remove(UUID)
}

/// A rule made from the row reminds half an hour ahead; the Alerts screen changes it.
let alertRowLead: TimeInterval = 1_800

/// One tap on Calendar or Live for this station and offer: turn that delivery on or off on the
/// matching rule, create the rule with it on, or remove a rule left with nothing. Turning a
/// delivery on also turns a rule that was switched off back on.
func alertRowToggle(_ rules: [AlertRule], stationID: String, offer: AlertTrigger,
                    delivery: AlertDelivery) -> AlertRuleChange {
    guard var rule = rules.first(where: { $0.stationID == stationID && $0.trigger == offer }) else {
        return .upsert(AlertRule(stationID: stationID, trigger: offer, lead: alertRowLead,
                                 calendar: delivery == .calendar,
                                 alert: delivery == .live ? .notification : .none))
    }
    let wasOn = rule.enabled && (delivery == .calendar ? rule.calendar : rule.alert == .notification)
    switch delivery {
    case .calendar: rule.calendar = !wasOn
    case .live: rule.alert = wasOn ? .none : .notification
    }
    if !wasOn { rule.enabled = true }
    return (!rule.calendar && rule.alert == .none) ? .remove(rule.id) : .upsert(rule)
}

/// Which of the row's two buttons read on for this station and offer.
func alertRowState(_ rules: [AlertRule], stationID: String, offer: AlertTrigger) -> (calendar: Bool, live: Bool) {
    guard let rule = rules.first(where: { $0.stationID == stationID && $0.trigger == offer && $0.enabled })
    else { return (false, false) }
    return (rule.calendar, rule.alert == .notification)
}
