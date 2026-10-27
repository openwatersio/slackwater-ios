// Slackwater — GPL v3. The Next max tile's sheet: how hard this maximum runs
// against the ones around it, when this gate runs hardest across the year, and
// what the maximum costs you at slack.
//
// Two sections where the Range sheet has three. The missing one is "against
// this station's own ends", and it is missing because there is nothing to
// measure against: LAT and HAT are hydrographic datums for water LEVEL, and no
// equivalent astronomical floor and ceiling is published for current speed.
// `CurrentStationRecord` carries no datum fields at all.
import SwiftUI
import SlackwaterKit
import Almanac

struct MaxDetailSheet: View {
    /// The speed itself, exactly as the tile prints it: "5.9 kn".
    let value: String
    /// "Flood" or "Ebb" — which way the maximum runs.
    let direction: String
    let place: String
    /// Where this maximum stands among its own direction's over the fortnight.
    var standing: PeakStanding? = nil
    /// The Moon's quarter phases across the standing's window: the speed
    /// beats with them the way a swing does.
    var phases: [MoonPhaseEvent] = []
    /// Twelve months of signed monthly extremes: flood above, ebb below.
    var months: [YearFigure.Month] = []
    /// The solstices and equinoxes around those months.
    var seasons: [SeasonEvent] = []
    /// The loaded timeline's slack runs, for what this maximum costs.
    var slackRuns: [(slack: Date, start: Date, end: Date)] = []
    var maximumAt: Date = .now
    /// The reader's speed unit, for the lit bar's label.
    var speedUnit = "kn"
    var tz: TimeZone = .current
    var now: Date = .now
    var onJump: ((Date) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    head
                    if let standing {
                        section(String(localized: "Is this beyond normal?",
                                       comment: "Current sheet section: how this maximum compares with the fortnight's.")) {
                            VStack(alignment: .leading, spacing: 6) {
                                SwingFigure(standing: standing, tz: tz, onJump: onJump,
                                            format: swingLabel, phases: phases)
                                    .accessibilityIdentifier("max-section-peaks")
                                // The moon sentence only where the bars bear
                                // it out, as on the Range sheet.
                                Group {
                                    if SwingFigure.springsFollowThePhases(peaks: SwingFigure.dailyPeaks(standing, tz: tz),
                                                                          phases: phases) {
                                        Text("Each bar is one day's hardest \(direction.lowercased()). Springs follow the new and full moon.",
                                             comment: "Explains the unit of the current figure's bars and why they beat with the moon. The value is 'flood' or 'ebb'.")
                                    } else {
                                        Text("Each bar is one day's hardest \(direction.lowercased()).",
                                             comment: "Explains the unit of the current figure's bars. The value is 'flood' or 'ebb'.")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(SN.foam.opacity(0.5))
                            }
                        }
                        facts
                    }
                    if months.count > 1 {
                        section(String(localized: "When this gate runs hardest",
                                       comment: "Current sheet section: the months this gate sees its strongest water.")) {
                            VStack(alignment: .leading, spacing: 6) {
                                YearFigure(months: months, now: now, tz: tz, seasons: seasons)
                                    .accessibilityIdentifier("max-section-year")
                                if let widest = YearFigure.standout(months).first {
                                    Group {
                                        switch YearFigure.follows(months: months, seasons: seasons, tz: tz) {
                                        case .solstices:
                                            Text("Hardest around \(monthName(widest.start, tz: tz)), near the solstice.",
                                                 comment: "Caption under the year figure on a current. The value is a month name.")
                                        case .equinoxes:
                                            Text("Hardest around \(monthName(widest.start, tz: tz)), near the equinox.",
                                                 comment: "Caption under the year figure on a current. The value is a month name.")
                                        case nil:
                                            Text("Hardest around \(monthName(widest.start, tz: tz)).",
                                                 comment: "Caption under the year figure on a current. The value is a month name.")
                                        }
                                    }
                                        .font(.caption)
                                        .foregroundStyle(SN.foam.opacity(0.5))
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(CanvasBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .navigationTitle("Next max")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    /// The lit bar's label prints a speed the way the tile does. Its one
    /// renderer is the figure's own Text, which carries the mono trait
    /// (TypeScaleTests' known indirections records the pair).
    private func swingLabel(_ knots: Double) -> String {
        "\(formatSpeed(knots, unit: speedUnit)) \(speedUnitLabel(speedUnit))"
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ReadoutType.hero.monospacedDigit())
                .foregroundStyle(.white)
            Text("The hardest the water runs before it turns, at \(place).",
                 comment: "Explains what the next-maximum number measures. The value is a place name.")
                .font(.callout)
                .foregroundStyle(SN.foam.opacity(0.75))
        }
    }

    /// The ranking in words, then what it costs at slack — the fact that is
    /// this sheet's own, and the reason to open it rather than read the tile.
    @ViewBuilder private var facts: some View {
        let items = [rankFact, slackFact(windows: slackRuns, around: maximumAt)].compactMap { $0 }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.text) { fact in
                if let to = fact.jumpTo, let onJump {
                    Button {
                        onJump(to)
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Text(fact.text)
                            Image(systemName: "arrow.right.circle").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(SN.graphLine)
                        .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("max-jump")
                } else {
                    Text(fact.text).foregroundStyle(SN.foam.opacity(0.75))
                }
            }
        }
        .font(.callout.monospacedDigit())
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Counts rather than a percentile: "all but three of 58" is a fact a
    /// reader can picture and "the 95th percentile" is not.
    private var rankFact: StandingFact? {
        guard let standing else { return nil }
        let bigger = standing.all.filter { $0.magnitude > standing.selected.magnitude }.count
        if bigger == 0 {
            return StandingFact(text: String(localized: "The hardest \(direction.lowercased()) of the fortnight.",
                                             comment: "Current sheet caption. The value is 'flood' or 'ebb'."))
        }
        return StandingFact(
            text: String(localized: "Harder than all but \(bigger) of this fortnight's \(standing.all.count).",
                         comment: "Current sheet caption. Both values are counts of current maxima."),
            jumpTo: standing.nextBigger?.time)
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: title, color: SN.foam.opacity(0.55), isHeader: true)
            VStack(spacing: 0) { content().padding(14) }
                .frame(maxWidth: .infinity)
                .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        }
    }
}
