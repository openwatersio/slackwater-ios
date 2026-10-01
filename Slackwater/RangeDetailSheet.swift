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

struct RangeDetailSheet: View {
    /// The swing itself, exactly as the tile prints it: "0.1 ft".
    let value: String
    /// "low to high" or "high to low" — which way this swing runs.
    let direction: String
    /// How many times the yearly change exceeds the largest tidal term.
    let seasonalRatio: Double
    /// The place, so the sheet can name the water rather than say "this station".
    let place: String

    @Environment(\.dismiss) private var dismiss

    private var leads: Bool { seasonalRatio >= TideStationRecord.seasonalLeadRatio }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    head
                    group { yearly }
                    explanation
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
        HStack(alignment: .firstTextBaseline) {
            Text("Yearly change", comment: "Label for how much the water level moves across a year.")
                .font(.callout)
                .foregroundStyle(SN.foam.opacity(0.75))
            Spacer()
            // "about 1× the daily tide" is a number that says nothing, and at
            // the bottom of the band that is exactly what the ratio rounds to.
            Text(seasonalTimes(seasonalRatio) == "1"
                 ? String(localized: "about the same as the daily tide", comment: "The annual swing is about the size of the daily tide.")
                 : String(localized: "about \(seasonalTimes(seasonalRatio))× the daily tide", comment: "How much larger the annual swing is than the daily tide."))
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
