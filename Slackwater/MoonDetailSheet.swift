// Slackwater — GPL v3. The Moon tile's sheet: what this app knows about the
// moon tonight, and the two eclipses either side of the scrub time.
//
// Every search in here runs ONCE, in the sheet's `.task`. None of it is on the
// scrub path — which is exactly what lets it be this expensive.
import Almanac
import SwiftUI

struct MoonFacts {
    let illumination: MoonIllumination
    let rise: Date?
    let set: Date?
    let nextFull: Date?
    let nextNew: Date?
    let distanceKm: Double
    let closest: Date?
    let farthest: Date?
    /// The last and next eclipse VISIBLE FROM HERE — `lunarEclipses` filters on
    /// the observer's horizon, so the sheet never offers a jump to a night
    /// with nothing to look at.
    let last: WindowEclipse?
    let next: WindowEclipse?
}

/// 400 days back covers the longest gap between consecutive lunar eclipses
/// (under a year across the 1950–2100 catalog), which is what lets "the last
/// one" be a forward walk from there. Almanac has no backward or range search;
/// openwatersio/almanac#6 asks whether it should.
private let eclipseLookBack = 400.0 * 86_400
private let eclipseLookAhead = 800.0 * 86_400

func moonFacts(at: Date, observer: Observer, tz: TimeZone) -> MoonFacts? {
    guard let illumination = try? moonIllumination(at),
          let position = try? moonPosition(at) else { return nil }

    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.startOfDay(for: at)
    let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
    let events = (try? moonEvents(from: dayStart, to: dayEnd, observer: observer)) ?? []
    let phases = (try? searchMoonPhases(from: at, to: at.addingTimeInterval(45 * 86_400))) ?? []

    // Almanac has no apogee/perigee search, so sample it: 6-hour steps across
    // half a month either side resolve a perigee to within a few hours, and a
    // few hours is enough to name the date, which is all this line does.
    var closest: (time: Date, km: Double)?
    var farthest: (time: Date, km: Double)?
    var t = at.addingTimeInterval(-15 * 86_400)
    let stop = at.addingTimeInterval(15 * 86_400)
    while t <= stop {
        if let km = try? moonPosition(t).distanceKm {
            if closest == nil || km < closest!.km { closest = (t, km) }
            if farthest == nil || km > farthest!.km { farthest = (t, km) }
        }
        t = t.addingTimeInterval(6 * 3600)
    }

    return MoonFacts(
        illumination: illumination,
        rise: events.first { $0.kind == .rise }?.time,
        set: events.first { $0.kind == .set }?.time,
        nextFull: phases.first { $0.phase == .full }?.time,
        nextNew: phases.first { $0.phase == .new }?.time,
        distanceKm: position.distanceKm,
        closest: closest?.time,
        farthest: farthest?.time,
        last: lunarEclipses(from: at.addingTimeInterval(-eclipseLookBack), to: at,
                            observer: observer).last,
        next: lunarEclipses(from: at, to: at.addingTimeInterval(eclipseLookAhead),
                            observer: observer).first)
}

struct MoonDetailSheet: View {
    let at: Date
    var eclipse: WindowEclipse? = nil
    let latitude: Double
    let longitude: Double
    /// Passed, not read from the environment: `.sheet` content does not
    /// inherit what was set above the presenting view (the story is on
    /// `CurrentDetailView.openChsRoute`), and a station in another zone would
    /// otherwise print its rise and set in the device's.
    let tz: TimeZone
    let onJump: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var facts: MoonFacts?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let facts {
                        head(facts)
                        line("RISE", facts.rise.map { chartTime($0, tz) } ?? "—")
                        line("SET", facts.set.map { chartTime($0, tz) } ?? "—")
                        line("NEXT FULL", when(facts.nextFull),
                             jumpTo: facts.nextFull, id: "moon-next-full")
                        line("NEXT NEW", when(facts.nextNew),
                             jumpTo: facts.nextNew, id: "moon-next-new")
                        line("DISTANCE", "\(Int((facts.distanceKm / 100).rounded()) * 100) km",
                             caption: [facts.closest.map { "closest \(monthDay($0, tz))" },
                                       facts.farthest.map { "farthest \(monthDay($0, tz))" }]
                                 .compactMap { $0 }.joined(separator: " · "))
                        eclipseRow("LAST ECLIPSE", facts.last, id: "moon-last-eclipse")
                        eclipseRow("NEXT ECLIPSE", facts.next, id: "moon-next-eclipse")
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(20)
            }
            .background(CanvasBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .navigationTitle("Moon")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard let observer = try? Observer(latitudeDeg: latitude, longitudeDeg: longitude)
            else { return }
            facts = moonFacts(at: at, observer: observer, tz: tz)
        }
    }

    /// "Aug 27 · 9:12pm", and "Aug 17, 2027 · 12:13am" when the year is not
    /// the one being scrubbed. The year is not decoration here: the next
    /// eclipse is usually months out and often the following year, and a bare
    /// "Aug 17" under a "NEXT ECLIPSE" label on September 7th reads as a date
    /// in the past. `weekRangeLabel` makes the same call for the same reason.
    private func when(_ d: Date?) -> String {
        guard let d else { return "—" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: at)
        let day = sameYear ? monthDay(d, tz) : formatter("MMM d, yyyy", tz).string(from: d)
        return "\(day) · \(chartTime(d, tz))"
    }

    private func head(_ facts: MoonFacts) -> some View {
        HStack(spacing: 14) {
            MoonGlyph(fraction: facts.illumination.fraction, waxing: facts.illumination.waxing,
                      size: 54, umbra: eclipse?.shadow(at: at) ?? 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(eclipse.map { eclipseTileText($0.kind) }
                        ?? moonPhaseName(phase: facts.illumination.phase))
                    .font(ReadoutType.tileText)
                    .foregroundStyle(.white)
                Text("\(Int((facts.illumination.fraction * 100).rounded()))% lit")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.55))
            }
            Spacer()
        }
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }

    /// A label/value row. With `jumpTo` it becomes a destination — chevron,
    /// tap, dismiss — on the same terms as the eclipse rows below: every time
    /// printed in this sheet that the scrubber can reach is somewhere to go,
    /// and one that isn't tappable while its neighbour is reads as broken.
    private func line(_ label: String, _ value: String, caption: String = "",
                      jumpTo: Date? = nil, id: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                MonoLabel(text: label, color: SN.foam.opacity(0.55))
                Spacer()
                Text(value).font(.footnote.monospacedDigit()).foregroundStyle(.white)
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
        .onTapGesture {
            guard let jumpTo else { return }
            onJump(jumpTo)
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(jumpTo != nil ? .isButton : [])
        .accessibilityIdentifier(id ?? "")
    }

    /// An eclipse either side of now. Nil reads "none visible from here" rather
    /// than vanishing: a missing row would say the app forgot to look, and
    /// "none from here" is the actual answer for an observer the shadow misses.
    @ViewBuilder
    private func eclipseRow(_ label: String, _ e: WindowEclipse?, id: String) -> some View {
        if let e {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    MonoLabel(text: label, color: SN.umbraLabel)
                    Text(eclipseTileText(e.kind)).font(ReadoutType.tileText).foregroundStyle(.white)
                    Text(when(e.peak)).font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.5))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            // The START, not the peak: "scrub to the eclipse" means the moment
            // the shadow first touches, which is what there is to wait for.
            .onTapGesture { onJump(e.start); dismiss() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
        } else {
            line(label, "none visible from here")
        }
    }
}
