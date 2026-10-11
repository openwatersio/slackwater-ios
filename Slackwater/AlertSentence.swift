// Slackwater — GPL v3. A sentence becomes a rule: the drafts the model fills, and the pure mapping (docs/alerts.md §7.3).
import Foundation
import FoundationModels

// MARK: - What the model fills in

/// Never a date: the model is weak at dates and knows nothing of the station's zone. Swift
/// resolves the day through `Calendar` in that zone (`alertSentenceWindow`).
@Generable
enum AlertRelativeDay: Equatable {
    case today, tomorrow
    case daysAhead(Int)
}

/// One trigger enum per station kind, so the model cannot propose what the station cannot do.
@Generable
enum TideSentenceTrigger: Equatable {
    case lowTide, highTide, lunarEclipse
    case risesPast(height: Double)
    case fallsPast(height: Double)
}

@Generable
enum CurrentSentenceTrigger: Equatable {
    case slackWindow, maxFlood, maxEbb, lunarEclipse
}

@Generable
enum DerivedSentenceTrigger: Equatable {
    case slack, lunarEclipse
}

// The three drafts share their fields; `@Generable` is a macro on concrete types, so they are
// spelled out and meet in `AlertSentenceDraft`.
@Generable
struct TideSentenceDraft {
    @Guide(description: "What to alert on. A height is in the units the instructions name.")
    var trigger: TideSentenceTrigger
    @Guide(description: "true for 'every', 'each', 'whenever', 'all'; false for 'the next', 'tomorrow's', 'this', or one particular time")
    var repeats: Bool
    @Guide(description: "true when the person says during the day, in daylight, daytime, while it is light, or between sunrise and sunset")
    var daylightOnly: Bool
    @Guide(description: "Minutes of warning the person asked for, or null when they did not say")
    var leadMinutes: Int?
    @Guide(description: "Which day the person named, or null for the next occurrence")
    var day: AlertRelativeDay?
}

@Generable
struct CurrentSentenceDraft {
    @Guide(description: "What to alert on")
    var trigger: CurrentSentenceTrigger
    @Guide(description: "true for 'every', 'each', 'whenever', 'all'; false for 'the next', 'tomorrow's', 'this', or one particular time")
    var repeats: Bool
    @Guide(description: "true when the person says during the day, in daylight, daytime, while it is light, or between sunrise and sunset")
    var daylightOnly: Bool
    @Guide(description: "Minutes of warning the person asked for, or null when they did not say")
    var leadMinutes: Int?
    @Guide(description: "Which day the person named, or null for the next occurrence")
    var day: AlertRelativeDay?
}

@Generable
struct DerivedSentenceDraft {
    @Guide(description: "What to alert on")
    var trigger: DerivedSentenceTrigger
    @Guide(description: "true for 'every', 'each', 'whenever', 'all'; false for 'the next', 'tomorrow's', 'this', or one particular time")
    var repeats: Bool
    @Guide(description: "true when the person says during the day, in daylight, daytime, while it is light, or between sunrise and sunset")
    var daylightOnly: Bool
    @Guide(description: "Minutes of warning the person asked for, or null when they did not say")
    var leadMinutes: Int?
    @Guide(description: "Which day the person named, or null for the next occurrence")
    var day: AlertRelativeDay?
}

// MARK: - The pure half

struct AlertSentenceDraft: Equatable {
    var trigger: AlertTrigger
    var repeats: Bool
    var daylightOnly: Bool
    var leadMinutes: Int?
    var day: AlertRelativeDay?
}

enum AlertSentenceOutcome: Equatable {
    /// The rule the sentence described, and the moment "Does not repeat" binds to.
    case rule(AlertRule, boundMoment: Date?)
    /// A singular ask with no occurrence in its window.
    case nothingAhead
    /// The words name something this station kind cannot alert on.
    case notOffered
    /// The model was unavailable or threw; the sheet keeps the draft it had.
    case failed
}

/// The model never refuses: asked for wind at a tide station it answers "low tide". These words
/// are the asks it gets wrong most, caught before it is asked. Short on purpose — the sheet shows
/// every parse before Save, and that is the real guard.
/// ponytail: a word list; a classifier if the misses ever measure.
func alertSentenceOutOfScope(_ sentence: String, kind: StationCalendarKind) -> Bool {
    let words = sentence.lowercased()
    let everywhere = ["wind", "weather", "waves?", "swell", "rain", "fog", "sunset", "sunrise", "moonrise", "moonset"]
    let perKind: [String] = switch kind {
    case .tide: ["slack", "currents?", "ebb", "flood", "knots?", "passage", "pass", "narrows", "rapids"]
    case .current: ["low tide", "high tide", "low water", "high water", "tide height", "feet", "metres?", "meters?"]
    case .derived: ["low tide", "high tide", "ebb", "flood", "max", "knots?", "feet", "metres?", "meters?"]
    }
    // Whole words: "wind" must not match "window", nor "pass" "passage" on a current station.
    return (everywhere + perKind).contains { words.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
}

/// A height as the person said it, in their units, to the engine's metres at the precision the
/// strip displays — so "8 ft" lands on the same rule a press at 8.0 ft makes.
private func metres(_ height: Double, imperial: Bool) -> Double {
    displayedHeightM(imperial ? height / toFeet(1) : height, imperial: imperial)
}

func alertSentenceDraft(_ d: TideSentenceDraft, imperial: Bool) -> AlertSentenceDraft {
    let trigger: AlertTrigger = switch d.trigger {
    case .lowTide: .tideExtreme(high: false)
    case .highTide: .tideExtreme(high: true)
    case .lunarEclipse: .eclipse
    case .risesPast(let h): .tideCrossing(heightM: metres(h, imperial: imperial), rising: true)
    case .fallsPast(let h): .tideCrossing(heightM: metres(h, imperial: imperial), rising: false)
    }
    return AlertSentenceDraft(trigger: trigger, repeats: d.repeats, daylightOnly: d.daylightOnly,
                              leadMinutes: d.leadMinutes, day: d.day)
}

func alertSentenceDraft(_ d: CurrentSentenceDraft, imperial: Bool) -> AlertSentenceDraft {
    let trigger: AlertTrigger = switch d.trigger {
    case .slackWindow: .slackWindowOpens
    case .maxFlood: .currentPeak(flood: true)
    case .maxEbb: .currentPeak(flood: false)
    case .lunarEclipse: .eclipse
    }
    return AlertSentenceDraft(trigger: trigger, repeats: d.repeats, daylightOnly: d.daylightOnly,
                              leadMinutes: d.leadMinutes, day: d.day)
}

func alertSentenceDraft(_ d: DerivedSentenceDraft, imperial: Bool) -> AlertSentenceDraft {
    AlertSentenceDraft(trigger: d.trigger == .slack ? .slack : .eclipse, repeats: d.repeats,
                       daylightOnly: d.daylightOnly, leadMinutes: d.leadMinutes, day: d.day)
}

/// The span a sentence's occurrence is searched in. No day: from now across the notification
/// horizon. A named day: that calendar day in the station's zone, which is 23, 24 or 25 hours
/// long — and today starts now, so a low already past this morning is not "today's".
func alertSentenceWindow(day: AlertRelativeDay?, now: Date, tz: TimeZone) -> (from: Date, to: Date) {
    guard let day else { return (now, now.addingTimeInterval(AlertHorizon.notifications)) }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let offset = switch day { case .today: 0; case .tomorrow: 1; case .daysAhead(let n): max(n, 0) }
    let start = cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: now)!)
    let end = cal.date(byAdding: .day, value: 1, to: start)!
    return (max(start, now), end)
}

/// Draft → rule. The occurrence finder is a parameter so this stays testable without a station;
/// the sheet passes `alertOccurrences` over the real one.
func alertSentenceOutcome(_ draft: AlertSentenceDraft, stationID: String, now: Date, tz: TimeZone,
                          nextOccurrence: (AlertTrigger, Bool, Date, Date) -> Date?) -> AlertSentenceOutcome {
    let window = alertSentenceWindow(day: draft.day, now: now, tz: tz)
    let next = nextOccurrence(draft.trigger, draft.daylightOnly, window.from, window.to).map(alertMinute)
    if !draft.repeats && next == nil { return .nothingAhead }
    // The sheet offers six leads; a sentence's "45 minutes" lands on the nearest.
    let lead = draft.leadMinutes.map { minutes in
        alertLeads.min { abs($0 - Double(minutes) * 60) < abs($1 - Double(minutes) * 60) }!
    } ?? alertNewRuleLead
    let rule = AlertRule(stationID: stationID, trigger: draft.trigger, once: draft.repeats ? nil : next,
                         lead: lead, daylightOnly: draft.daylightOnly)
    return .rule(rule, boundMoment: next)
}

// MARK: - The model

/// A fixed paragraph per kind: what the place is, what each trigger means in a boater's words,
/// the units. Kept short — the 4K-token window holds this, the schema and the reply.
func alertSentenceInstructions(kind: StationCalendarKind, imperial: Bool) -> String {
    let unit = imperial ? "feet" : "metres"
    switch kind {
    case .tide:
        return """
        You turn one sentence into an alert at a tide station. The sentence is about this place only.
        What can be alerted on here: low tide, high tide, the water rising past a height, the water falling past a height, a lunar eclipse. Heights are in \(unit).
        Pick the closest trigger. Never invent one. "The next", "this", or a named day is once: repeats is false. "Every", "each", "whenever", "all" is repeats true.
        """
    case .current:
        return """
        You turn one sentence into an alert at a tidal current station. The sentence is about this place only.
        What can be alerted on here: the slack window opening (when the current is slow enough to get through), max flood, max ebb, a lunar eclipse.
        Pick the closest trigger. Never invent one. "The next", "this", or a named day is once: repeats is false. "Every", "each", "whenever", "all" is repeats true.
        """
    case .derived:
        return """
        You turn one sentence into an alert at a tidal gate whose slacks are known but whose speeds are not. The sentence is about this place only.
        What can be alerted on here: slack, a lunar eclipse.
        Pick the closest trigger. Never invent one. "The next", "this", or a named day is once: repeats is false. "Every", "each", "whenever", "all" is repeats true.
        """
    }
}

/// Whether the field is worth showing: the on-device model, ready. Anything else — a phone
/// without Apple Intelligence, a device language it does not support, a model still
/// downloading — hides the field and the sheet works as it does for a press.
var alertSentenceAvailable: Bool {
    if case .available = SystemLanguageModel.default.availability { return true }
    return false
}

/// One session per parse, no transcript carried: five parses on one session overflow the window.
/// The draft comes back as the engine's trigger; the caller resolves the occurrence.
func alertSentenceParse(_ sentence: String, kind: StationCalendarKind, imperial: Bool) async -> AlertSentenceDraft? {
    let session = LanguageModelSession(instructions: alertSentenceInstructions(kind: kind, imperial: imperial))
    do {
        switch kind {
        case .tide:
            return alertSentenceDraft(try await session.respond(to: sentence, generating: TideSentenceDraft.self).content, imperial: imperial)
        case .current:
            return alertSentenceDraft(try await session.respond(to: sentence, generating: CurrentSentenceDraft.self).content, imperial: imperial)
        case .derived:
            return alertSentenceDraft(try await session.respond(to: sentence, generating: DerivedSentenceDraft.self).content, imperial: imperial)
        }
    } catch {
        return nil
    }
}
