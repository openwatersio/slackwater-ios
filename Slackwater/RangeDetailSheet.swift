// Slackwater — GPL v3. The Range tile's sheet (#217): the tidal plane ladder,
// and where this swing stands among the tides either side of it.
//
// Everything expensive runs ONCE, off the main actor, in the sheet's `.task` —
// a year of extremes is far more arithmetic than the scrub path would tolerate
// and none of it is on that path. `MoonDetailSheet` makes the same bargain.
import SwiftUI
import TideEngine

/// Loads, then hands off. The split is not ceremony: `ImageRenderer` runs no
/// `.task`, so a sheet that computes on appear renders as a spinner and the
/// render test can never see the thing it is meant to be checking.
struct RangeDetailSheet: View {
    let record: TideStationRecord
    let at: Date
    /// Passed, not read from the environment: `.sheet` content does not
    /// inherit what was set above the presenting view, and a station in
    /// another zone would otherwise print its turns in the device's.
    let tz: TimeZone
    let imperial: Bool
    let onJump: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var facts: RangeFacts?
    @State private var rungs: [LadderRung] = []
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let facts {
                        RangeDetailBody(record: record, facts: facts, rungs: rungs, at: at,
                                        tz: tz, imperial: imperial, onJump: jump)
                    } else if scanned {
                        // The tile guards on the same swing this scan looks
                        // for, so the two disagreeing is a narrow case (a
                        // subordinate whose corrections invert the pair
                        // `ranges()` would have built). Narrow is not never,
                        // and a spinner that never stops is the worst way to
                        // say so.
                        Text("No tides to compare this against.")
                            .font(.footnote).foregroundStyle(SN.foam.opacity(0.55))
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(20)
            }
            .background(CanvasBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .navigationTitle("Range")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard !scanned else { return }
            let record = record, at = at
            let station = record.engineStation
            let built = await Task.detached(priority: .userInitiated) { () -> (RangeFacts, [LadderRung])? in
                guard let f = record.rangeFacts(at: at, station: station) else { return nil }
                let now = station.heights(from: at, to: at.addingTimeInterval(1), step: 1).first?.height ?? 0
                return (f, tideLadder(record: record, facts: f, nowHeight: now))
            }.value
            facts = built?.0
            rungs = built?.1 ?? []
            scanned = true
        }
    }

    private func jump(_ t: Date) {
        onJump(t)
        dismiss()
    }
}

/// Everything the sheet shows once its scan has landed.
struct RangeDetailBody: View {
    let record: TideStationRecord
    let facts: RangeFacts
    let rungs: [LadderRung]
    let at: Date
    let tz: TimeZone
    let imperial: Bool
    let onJump: (Date) -> Void

    private var unit: String { heightUnit(imperial: imperial) }
    private var span: String { facts.yearly ? "this year" : "this month" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head(facts)
            TideLadderView(rungs: rungs, imperial: imperial, tz: tz, onJump: onJump)
                .padding(.vertical, 8)
            standings(facts)
            footnote(facts)
        }
    }

    // MARK: - Head

    private func head(_ facts: RangeFacts) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(formatHeight(facts.swing.height, imperial: imperial)) \(unit)")
                .font(ReadoutType.lead.monospacedDigit())
                .foregroundStyle(.white)
            Text(facts.swing.isRising ? "low to high" : "high to low")
                .font(.caption)
                .foregroundStyle(SN.foam.opacity(0.55))
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Where it stands

    @ViewBuilder
    private func standings(_ facts: RangeFacts) -> some View {
        if let low = facts.low {
            line("THIS LOW", standingSentence(low, lower: true, noun: "low", verb: "go lower", span: span),
                 caption: low.nextTime.map { "next big low \(when($0))" } ?? "",
                 jumpTo: low.nextTime, id: "range-next-low")
        }
        if let high = facts.high {
            line("THIS HIGH", standingSentence(high, lower: false, noun: "high", verb: "go higher", span: span),
                 caption: high.nextTime.map { "next big high \(when($0))" } ?? "",
                 jumpTo: high.nextTime, id: "range-next-high")
        }
        if let range = facts.range {
            line("THIS SWING", standingSentence(range, lower: false, noun: "swing", verb: "are bigger", span: span),
                 caption: range.nextTime.map { "next big swing \(when($0))" } ?? "",
                 jumpTo: range.nextTime, id: "range-next-swing")
        }
    }

    /// "Aug 27", with the year once it is not the one being scrubbed — a bare
    /// "Feb 3" under "next big low" on a December evening reads as the past.
    private func when(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.year, from: d) == cal.component(.year, from: at)
            ? monthDay(d, tz)
            : formatter("MMM d, yyyy", tz).string(from: d)
    }

    /// The same label/value row `MoonDetailSheet` uses, on the same terms:
    /// with `jumpTo` it is somewhere to go.
    private func line(_ label: String, _ value: String, caption: String = "",
                      jumpTo: Date? = nil, id: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(text: label, color: SN.foam.opacity(0.55))
                Spacer()
                Text(value).font(.footnote).foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                if jumpTo != nil {
                    Image(systemName: "chevron.right").font(.caption2)
                        .foregroundStyle(SN.foam.opacity(0.5))
                }
            }
            if !caption.isEmpty {
                Text(caption).font(.caption2).foregroundStyle(SN.foam.opacity(0.55))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if let jumpTo { onJump(jumpTo) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(jumpTo != nil ? .isButton : [])
        .accessibilityIdentifier(id ?? "")
    }

    // MARK: - What the numbers do and do not promise

    private func footnote(_ facts: RangeFacts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The one thing the original plate teaches that survives having no
            // bathymetry: what the zero means. Charted depth and drying height
            // hang off this line, and they are the reason the ladder is drawn
            // against it rather than against sea level.
            Text("Chart datum is the zero soundings are measured from. A tide below it means there is less water than the chart shows.")
            if record.latDatum != nil {
                Text("Highest and lowest tide are the extremes of the 19-year astronomical cycle — not records. A storm surge goes over the top of one, and a single year can run a centimetre or two outside them.")
            } else {
                Text("This station has no published astronomical extremes, so the ladder shows only chart datum and what the tide does \(span).")
            }
            if !facts.yearly {
                Text("Its harmonic model is fitted on this device over 60 days, which cannot resolve the seasonal swing — so the comparison covers a month rather than a year.")
            }
        }
        .font(.caption2)
        .foregroundStyle(SN.foam.opacity(0.4))
        .padding(.top, 10)
    }
}
