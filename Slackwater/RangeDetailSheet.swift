// Slackwater — GPL v3. The Range tile's sheet: what the swing between this
// high and this low actually measures, and — at a station whose water is
// seasonal rather than tidal — why that number is small and why the heights on
// this screen drift through the year.
//
// The tile only offers this where there is something to say that the tile does
// not already say, which today means a station the database flags
// `seasonal_dominant` (slackwater-database#220). A Gulf port's range tile is
// complete on its own and stays inert.
import SwiftUI
import SlackwaterKit

struct RangeDetailSheet: View {
    /// The swing itself, exactly as the tile prints it: "0.1 ft".
    let value: String
    /// "low to high" or "high to low" — which way this swing runs.
    let direction: String
    /// How many times the yearly change exceeds the largest tidal term, at a
    /// station the database flags seasonal. Nil everywhere else, which is most
    /// of the bundle and now still opens this sheet.
    var seasonalRatio: Double? = nil
    /// The place, so the sheet can name the water rather than say "this station".
    let place: String
    /// Where the turn ahead stands among the fortnight's own turns, and the
    /// swing's heights to draw inside it. Nil before the scan lands.
    var standing: TideStanding? = nil
    /// Where this swing sits among the fortnight's swings — section 1's
    /// subject, and a different judgement from `standing`'s.
    var swing: SwingStanding? = nil
    var latDatum: Double? = nil
    var hatDatum: Double? = nil
    var imperial = false
    var unit = "m"
    var tz: TimeZone = .current
    var now: Date = .now
    /// Moves the scrubber to a tapped fact, the way the Moon sheet's facts
    /// already do. A superlative you cannot go and look at is trivia.
    var onJump: ((Date) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var leads: Bool { (seasonalRatio ?? 0) >= TideStationRecord.seasonalLeadRatio }

    private var facts: [StandingFact] {
        standing.map {
            standingFacts($0, latDatum: latDatum, hatDatum: hatDatum, imperial: imperial,
                          unit: unit, tz: tz, now: now)
        } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    head
                    // Three questions, three figures. One figure answering all
                    // three read as a conflation on screen: "how big is this
                    // swing", "where does this turn sit between the station's
                    // ends" and "when does this station see its extremes" are
                    // different quantities on different axes.
                    if let swing {
                        section(String(localized: "Is this beyond normal?",
                                       comment: "Range sheet section: how this swing compares with the fortnight's.")) {
                            SwingFigure(standing: swing, onJump: onJump)
                        }
                        factRow(swingFact)
                    }
                    if let standing, latDatum != nil {
                        section(String(localized: "Against this station's own ends",
                                       comment: "Range sheet section: where this turn sits between the station's floor and ceiling.")) {
                            StandingFigure(standing: standing, latDatum: latDatum,
                                           hatDatum: hatDatum, imperial: imperial)
                        }
                        factRows
                    }
                    if seasonalRatio != nil {
                        group { yearly }
                        explanation
                    }
                }
                .padding(20)
            }
            .background(CanvasBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .navigationTitle("Range")
            .navigationBarTitleDisplayMode(.inline)
        }
        // Three short paragraphs do not need the whole screen, and a sheet that
        // takes it reads as more alarming than the thing it explains.
        .presentationDetents([.medium, .large])
    }

    /// A titled section: one question, one figure. The heading is what keeps
    /// the three apart — without it the reader has to infer which quantity
    /// each axis carries, which is the conflation this structure fixes.
    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: title, color: SN.foam.opacity(0.55))
            group { content().padding(14) }
        }
    }

    /// Section 1's caption. Counts rather than a percentile: "all but three of
    /// 58" is a fact a reader can picture, and "the 95th percentile" is not.
    private var swingFact: StandingFact? {
        guard let swing else { return nil }
        let bigger = swing.all.filter { $0.height > swing.selectedHeight }.count
        if bigger == 0 {
            return StandingFact(text: String(localized: "The biggest swing of the fortnight.",
                                             comment: "Range sheet caption."))
        }
        return StandingFact(
            text: String(localized: "Bigger than all but \(bigger) of this fortnight's \(swing.all.count) swings.",
                         comment: "Range sheet caption. Both values are counts of tide swings."),
            jumpTo: swing.nextBigger?.time)
    }

    @ViewBuilder private func factRow(_ fact: StandingFact?) -> some View {
        if let fact { rows([fact]) }
    }

    /// The figure's captions. A fact with somewhere to go is a button that
    /// moves the scrubber and closes the sheet — the reader asked to see it,
    /// not to read about it.
    @ViewBuilder private var factRows: some View { rows(facts) }

    @ViewBuilder private func rows(_ items: [StandingFact]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.text) { fact in
                if let to = fact.jumpTo, let onJump {
                    Button {
                        onJump(to)
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Text(fact.text)
                            Image(systemName: "arrow.right.circle")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(SN.graphLine)
                        .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(fact.text).foregroundStyle(SN.foam.opacity(0.75))
                }
            }
        }
        // The facts carry formatted heights and day counts, so the digits are
        // fixed-width here — `standingFacts` formats them and this is their one
        // renderer (TypeScaleTests' known indirections records the pair).
        .font(.callout.monospacedDigit())
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The number the tile showed, restated with what it is the difference
    /// between — the question a reader taps this to ask.
    private var head: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ReadoutType.hero.monospacedDigit())
                .foregroundStyle(.white)
            Text("The difference between this swing's high and low, \(direction).",
                 comment: "Explains what the tide-range number measures. The placeholder is 'low to high' or 'high to low'.")
                .font(.callout)
                .foregroundStyle(SN.foam.opacity(0.75))
        }
    }

    /// The comparison itself, as a row rather than a sentence: it is the one
    /// number a reader might carry away, and prose buries it.
    private var yearly: some View {
        let ratio = seasonalRatio ?? 0
        return HStack(alignment: .firstTextBaseline) {
            Text("Yearly change", comment: "Label for how much the water level moves across a year.")
                .font(.callout)
                .foregroundStyle(SN.foam.opacity(0.75))
            Spacer()
            // "about 1× the daily tide" is a number that says nothing, and at
            // the bottom of the band that is exactly what the ratio rounds to.
            Text(seasonalTimes(ratio) == "1"
                 ? String(localized: "about the same as the daily tide", comment: "The annual swing is about the size of the daily tide.")
                 : String(localized: "about \(seasonalTimes(ratio))× the daily tide", comment: "How much larger the annual swing is than the daily tide."))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }

    /// Two paragraphs, graded by how far the water has left the tide behind.
    ///
    /// The strong case is a lake, a river reach or a lagoon, where the annual
    /// cycle IS the signal and the daily rise and fall is almost nothing — the
    /// reader needs to know the schedule below is not a tide table in any
    /// useful sense. The mild case is a real tidal port where the annual cycle
    /// merely rivals the tide: the times stand, and only the heights wander.
    ///
    /// Neither says the prediction is wrong, because it is not. What is wrong
    /// is reading it as a tide when it is mostly a season.
    @ViewBuilder private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            if leads {
                Text("The water at \(place) rises and falls far more across a year than it does across a day. Rivers, lakes and lagoons behave this way: the level follows the seasons — runoff, rainfall, wind — and the daily tide is a ripple on top of it.",
                     comment: "Explains a station whose annual cycle dominates its tide. The placeholder is a place name.")
                Text("The highs and lows below are still computed the same way and are still correct. They are just a small movement inside a much larger seasonal one, so a whole day can sit above or below what the same day looks like six months from now.",
                     comment: "Reassures that predictions are correct at a seasonal station.")
            } else {
                Text("The water at \(place) has a real tide, and a yearly cycle of about the same size. The times below are unaffected — high and low arrive when they arrive — but the heights drift across the year as the seasonal level rises and falls underneath them.",
                     comment: "Explains a station whose annual cycle is comparable to its tide. The placeholder is a place name.")
            }
        }
        .font(.callout)
        .foregroundStyle(SN.foam.opacity(0.75))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity)
            .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SN.cardStroke, lineWidth: 0.5))
    }
}
