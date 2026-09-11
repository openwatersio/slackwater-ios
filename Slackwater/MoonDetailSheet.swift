// Slackwater — GPL v3. The Moon tile's sheet: what this app knows about the
// moon tonight, drawn rather than tabulated, and the eclipses either side of
// the scrub time.
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
    /// The last eclipse VISIBLE FROM HERE — the search skips the ones this
    /// observer misses, so the sheet never offers a jump to a night with
    /// nothing to look at.
    let last: WindowEclipse?
    /// The next eclipse of each KIND visible from here, in date order. One of
    /// each rather than three of whatever comes next: the three kinds are the
    /// thing worth learning, and a list of three penumbrals teaches none of it.
    let upcoming: [WindowEclipse]
}

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

    // Five years, and no further. Walking forward one eclipse at a time until
    // all three kinds turn up is both slower and worse: from a fixed observer
    // it reaches dates like June 2039 (measured, Perth in 2031), because a
    // partial needs its umbral magnitude to fall strictly between 0 and 1 and
    // THEN be visible from here. A row that far out is noise, so a kind with
    // nothing inside the window simply has no row. One range search costs
    // ~145 ms flat against this sheet's 500 ms budget, where the walk ran to
    // 317 ms for the worse answer.
    var firstOfKind: [LunarEclipseKind: WindowEclipse] = [:]
    for e in visibleEclipses(from: at, to: at.addingTimeInterval(5 * 365.25 * 86_400),
                             observer: observer) where firstOfKind[e.kind] == nil {
        firstOfKind[e.kind] = e
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
        last: previousVisibleEclipse(before: at, observer: observer),
        upcoming: firstOfKind.values.sorted { $0.peak < $1.peak })
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
                VStack(alignment: .leading, spacing: 14) {
                    if let facts {
                        head(facts)
                        group {
                            horizonCell("RISE", facts.rise, rising: true, facts, id: "moon-rise")
                            divider
                            horizonCell("SET", facts.set, rising: false, facts, id: "moon-set")
                        }
                        group {
                            phaseCell("NEXT FULL", facts.nextFull, fraction: 1,
                                      id: "moon-next-full")
                            divider
                            phaseCell("NEXT NEW", facts.nextNew, fraction: 0,
                                      id: "moon-next-new")
                        }
                        distance(facts)
                        group {
                            eclipseRow("LAST ECLIPSE", facts.last,
                                       id: "moon-last-eclipse", color: SN.umbraLabel)
                        }
                        if !facts.upcoming.isEmpty {
                            group {
                                ForEach(Array(facts.upcoming.enumerated()), id: \.element.id) {
                                    index, e in
                                    if index > 0 { divider }
                                    eclipseRow(index == 0 ? "NEXT ECLIPSE" : "THEN", e,
                                               id: "moon-next-eclipse-\(e.kind.rawValue)",
                                               color: SN.umbraLabel)
                                }
                            }
                        }
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
                      size: 54, umbra: eclipse?.shadow(at: at) ?? 0,
                      wash: eclipse?.wash(at: at) ?? 0)
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
        .accessibilityElement(children: .combine)
    }

    /// The sheet's one container. Rows that belong together share a card, so
    /// rise and set read as one fact about tonight rather than two entries in
    /// a list — which is what a flat run of label/value rows made of them.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity)
            .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SN.cardStroke, lineWidth: 0.5))
    }

    private var divider: some View {
        Rectangle().fill(SN.cardStroke).frame(height: 0.5).padding(.horizontal, 14)
    }

    /// Rise and set: the moon on the horizon, going the way it is going.
    ///
    /// Tappable, which they were not while every other time in this sheet was.
    /// The rule `line(_:_:jumpTo:)` states — every time the scrubber can reach
    /// is somewhere to go — had exactly two exceptions, and they were these.
    private func horizonCell(_ label: String, _ time: Date?, rising: Bool,
                             _ facts: MoonFacts, id: String) -> some View {
        cell(label, value: time.map { chartTime($0, tz) } ?? "—", jumpTo: time, id: id) {
            // No mark when there is no event. A moon drawn crossing the horizon
            // beside a "—" would be claiming a moonrise the day does not have —
            // and days without one are real: the moon rises ~50 minutes later
            // each day, so it skips a calendar day roughly monthly, every
            // latitude included.
            if time != nil {
                MoonHorizonMark(fraction: facts.illumination.fraction,
                                waxing: facts.illumination.waxing, rising: rising)
            } else {
                Color.clear.frame(width: 78, height: 44)
            }
        }
    }

    /// The next full and the next new, drawn at the shape they will be. A full
    /// disc and an unlit one say which is which before the label is read.
    private func phaseCell(_ label: String, _ time: Date?, fraction: Double,
                           id: String) -> some View {
        cell(label, value: when(time), jumpTo: time, id: id) {
            MoonGlyph(fraction: fraction, waxing: true, size: 34)
                .frame(width: 78, height: 44)
        }
    }

    /// A drawing, its label, and its time — the shape every row in the top half
    /// of this sheet takes. A row without a `jumpTo` still draws; it just does
    /// not pretend to be a destination.
    private func cell<Mark: View>(_ label: String, value: String, jumpTo: Date?, id: String,
                                  @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 12) {
            mark()
            VStack(alignment: .leading, spacing: 3) {
                MonoLabel(text: label, color: SN.foam.opacity(0.55))
                Text(value).font(.footnote.monospacedDigit()).foregroundStyle(.white)
            }
            Spacer()
            if jumpTo != nil {
                Image(systemName: "chevron.right").font(.caption2)
                    .foregroundStyle(SN.foam.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let jumpTo else { return }
            onJump(jumpTo)
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(jumpTo != nil ? .isButton : [])
        .accessibilityIdentifier(id)
    }

    /// Distance, and the orbit that explains it. Labelled from Earth because
    /// "DISTANCE" alone on a page about the moon does not say from what.
    private func distance(_ facts: MoonFacts) -> some View {
        // Grouped — "369,900 km", not "369900 km". Six digits run together are
        // a number you count rather than read, and this one is only ever read.
        let km = (Int((facts.distanceKm / 100).rounded()) * 100).formatted(.number)
        return group {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MonoLabel(text: "DISTANCE FROM EARTH", color: SN.foam.opacity(0.55))
                    Spacer()
                    Text(verbatim: "\(km) km")
                        .font(.footnote.monospacedDigit()).foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .accessibilityElement(children: .combine)

                MoonOrbitMark(at: at, perigee: facts.closest, apogee: facts.farthest,
                              tz: tz, onJump: { onJump($0); dismiss() })
                    .padding(.bottom, 6)
            }
        }
    }

    /// An eclipse, drawn as it will look at greatest — a bite for a partial, a
    /// dark disc for a total, a dimming for a penumbral.
    ///
    /// This is the whole reason the row has a picture: "penumbral" is a term,
    /// and the difference between the three is exactly the kind of thing a
    /// drawing settles and a word does not. `MoonGlyph` already takes both
    /// shadow channels, so nothing new is drawn here.
    @ViewBuilder
    private func eclipseRow(_ label: String, _ e: WindowEclipse?, id: String,
                            color: Color) -> some View {
        if let e {
            HStack(spacing: 12) {
                MoonGlyph(fraction: 1, waxing: true, size: 34,
                          umbra: e.shadow(at: e.peak), wash: e.wash(at: e.peak))
                    .frame(width: 78, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    MonoLabel(text: label, color: color)
                    Text(eclipseTileText(e.kind)).font(ReadoutType.tileText)
                        .foregroundStyle(.white)
                    Text(when(e.peak)).font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            // The START, not the peak: "scrub to the eclipse" means the moment
            // the shadow first touches, which is what there is to wait for.
            .onTapGesture { onJump(e.start); dismiss() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
        } else {
            // Nil reads "none visible from here" rather than vanishing: a
            // missing row would say the app forgot to look, and "none from
            // here" is the actual answer for an observer the shadow misses.
            cell(label, value: "none visible from here", jumpTo: nil, id: id) {
                Color.clear.frame(width: 78, height: 44)
            }
        }
    }
}
