// Slackwater — GPL v3. The tide detail's lead: the height as the hero, the
// phase word and its glyph above it, and the time below, one anatomy for
// every station with tide heights.
// Scrubber behavior here is specified in docs/scrubber.md: update the spec in the same change as any visible change.
import SwiftUI
import SlackwaterKit

struct TideLead: View {
    let timeline: TimelineData
    let scrubTime: Date
    /// Engine-exact height at `scrubTime` in metres (a preview's linear interpolation).
    let height: Double
    /// Metres per hour under the centerline, signed, clamped to the series (`TimelineData.rateAt`).
    let rate: Double
    let imperial: Bool
    let tz: TimeZone
    var ink: Color = .white
    /// The sky's ground the rate warning is lifted against.
    var chromeGround: UInt32 = 0

    private var unit: String { heightUnit(imperial: imperial) }

    /// SlackwaterKit's reading at the selection clamped into the series, so a selection past the loaded week keeps the end's phase.
    private var kit: TideReading? {
        guard let first = timeline.tidePoints.first?.time, let last = timeline.tidePoints.last?.time else { return nil }
        let t = min(max(scrubTime, first), last)
        return readTide(at: t, heights: timeline.tidePoints, rates: timeline.tideRates, extremes: timeline.tideExtremes)
    }
    private var atTurn: Bool { kit?.state == .high || kit?.state == .low }
    /// The kit is nil only on an empty series, where the lead is not shown: the rate's sign stands in.
    private var rising: Bool { kit?.rising ?? (rate >= 0) }
    /// "Rising 2.3 ft/hr" in place of the lead's bare word while the water is
    /// fast: it explains the yellow line under it.
    private var leadRate: String? {
        atTurn ? nil : tideRateReading(rate: rate, imperial: imperial)
    }
    private var leadState: String {
        switch kit?.state {
        case .high: String(localized: "High", comment: "High-tide state.")
        case .low: String(localized: "Low", comment: "Low-tide state.")
        default: rising
            ? String(localized: "Rising", comment: "Rising-tide state.")
            : String(localized: "Falling", comment: "Falling-tide state.")
        }
    }

    /// What the lead shows and says, apart from its clock.
    var reading: TideLeadReading {
        let turn = atTurn
        let word = leadState
        let value = formatHeight(height, imperial: imperial)
        let words = spokenReading(word, value, unit: unit)
        return TideLeadReading(
            state: leadRate ?? word,
            word: word,
            glyph: turn ? (rising ? "arrow.up.to.line" : "arrow.down.to.line")
                : (rising ? "arrow.up.right" : "arrow.down.right"),
            rising: rising,
            atTurn: turn,
            value: value,
            spoken: leadRate == nil ? words : spokenTideRate(after: words, rate: rate, imperial: imperial))
    }

    /// The lead in words, for the strip's spoken value.
    var spoken: String { reading.spoken }

    var body: some View {
        let reading = reading
        let warning = tideRateWarning(rate, over: chromeGround)
        let fast = reading.state != reading.word
        LeadCard(value: reading.value,
                 unit: unit,
                 time: leadWhen(scrubTime, tz),
                 valueColor: ink,
                 timeColor: ink) {
            // Word then glyph, the order the current lead reads in.
            // The rate, when it shows, outranks the word's usual ink (#95).
            Text(reading.state).fontWeight(.medium).monospacedDigit()
                .foregroundStyle(fast ? warning ?? ink : ink.opacity(0.85))
                .accessibilityLabel(fast ? spokenTideRate(after: reading.word, rate: rate, imperial: imperial)
                                    : reading.word)
            // The graph's own two inks, so the eyebrow names the curve the
            // reader is looking at — unless the rate is out of the ordinary
            // (#95), which outranks direction.
            LeadGlyph(systemName: reading.glyph)
                .foregroundStyle(warning ?? (reading.rising ? SN.graphHigh : SN.graphLow))
        }
    }
}

/// What the tide lead shows and says at an instant, apart from its clock: plain values, so a unit test can read what the lead renders (scrubber §9.1).
struct TideLeadReading: Equatable {
    /// `High`, `Low`, `Rising` or `Falling`, or the rate text (`Rising 0.60 m/hr`) while the water is fast and not at a turn.
    let state: String
    /// The bare word, for VoiceOver's label when `state` is the rate text.
    let word: String
    /// `arrow.up.to.line`, `arrow.down.to.line`, `arrow.up.right` or `arrow.down.right`.
    let glyph: String
    /// High or rising, rather than low or falling.
    let rising: Bool
    /// True at a turn; `rising` then says which.
    let atTurn: Bool
    /// The height as printed.
    let value: String
    /// The lead in words, for the strip's spoken value.
    let spoken: String
}

/// The rate ramp's colour when the rate is out of the ordinary (#95: at
/// Friday Harbor 0.8 ft/hr is nothing, at Ile Haute 8 ft/hr is the
/// warning), else nil and the direction colour stands. The lead's word
/// and glyph wear it for the selection's rate, the pill for the peak it
/// names, lifted for the sky they float on — the ramp's red end is
/// unreadable against a sunrise otherwise.
func tideRateWarning(_ rate: Double, over ground: UInt32) -> Color? {
    abs(rate) >= tideMovementRampAnchorsMHr[0]
        ? SN.speedLabelColour(Timeline.rampT(forTideRateMHr: abs(rate)), over: ground) : nil
}
