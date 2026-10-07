import Almanac
import SwiftUI

struct SunDayFacts: Sendable {
    let interval: DateInterval
    let events: [SunEvent]
    let dip: Double

    init(at: Date, tz: TimeZone, latitude: Double, longitude: Double, eyeHeight: Double) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        guard let interval = calendar.dateInterval(of: .day, for: at) else {
            throw AlmanacError.invalidArgument("Invalid calendar day")
        }
        // The sea surface is at zero elevation; Almanac separates eye elevation from height above it.
        let observer = try Observer(latitudeDeg: latitude, longitudeDeg: longitude, elevationM: eyeHeight)
        self.interval = interval
        dip = try horizonDip(observer: observer, heightAboveGroundM: eyeHeight)
        events = try sunEvents(from: interval.start, to: interval.end,
                               observer: observer, heightAboveGroundM: eyeHeight)
    }

    func time(_ kind: SunEventKind) -> Date? {
        events.first { $0.kind == kind }?.time
    }

    var daylight: TimeInterval? {
        guard let rise = time(.rise), let set = time(.set) else { return nil }
        let duration = set.timeIntervalSince(rise)
        return duration >= 0 ? duration : interval.duration + duration
    }
}

struct SunDetailSheet: View {
    let at: Date
    let latitude: Double
    let longitude: Double
    let tz: TimeZone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var eyeHeight = 0.0
    @State private var facts: SunDayFacts?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(monthDayYear(at, tz))
                        .font(.headline)
                    if let facts {
                        table(facts)
                        VStack(spacing: 14) {
                            LabeledContent("Solar noon", value: when(facts, .transit))
                            LabeledContent("Daylight", value: facts.daylight.map {
                                Duration.seconds($0.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
                            } ?? "—")
                            LabeledContent("Horizon dip", value: Measurement(value: facts.dip, unit: UnitAngle.degrees)
                                .formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(2)))))
                                .accessibilityIdentifier("sun-horizon-dip")
                        }
                        .font(.subheadline.monospacedDigit())
                    } else if failed {
                        Text("Sun times unavailable.")
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    Stepper(value: $eyeHeight, in: 0...10_000, step: 1) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Eye height above water")
                            Text(Measurement(value: eyeHeight, unit: UnitLength.meters),
                                 format: .measurement(width: .abbreviated, usage: .asProvided))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(SN.foam.opacity(0.7))
                        }
                    }
                    .accessibilityIdentifier("sun-eye-height")
                    Text("For an unobstructed sea horizon. Height adjusts this table only.")
                        .font(.footnote)
                        .foregroundStyle(SN.foam.opacity(0.7))
                }
                .padding(20)
            }
            .background(CanvasBackground())
            .navigationTitle("Sun activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task(id: eyeHeight) {
            facts = nil
            failed = false
            let height = eyeHeight
            let result = await Task.detached {
                try? SunDayFacts(at: at, tz: tz, latitude: latitude, longitude: longitude, eyeHeight: height)
            }.value
            guard !Task.isCancelled else { return }
            facts = result
            failed = result == nil
        }
    }

    private func when(_ facts: SunDayFacts, _ kind: SunEventKind) -> String {
        facts.time(kind).map { chartTime($0, tz) } ?? "—"
    }

    private func table(_ facts: SunDayFacts) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("Morning").foregroundStyle(SN.sunrise)
                    Text("Evening").foregroundStyle(SN.sunset)
                }
            }
            eventRow("Sunrise / sunset", facts, .rise, .set)
            eventRow("Civil twilight", facts, .civilDawn, .civilDusk)
            eventRow("Nautical twilight", facts, .nauticalDawn, .nauticalDusk)
            eventRow("Astronomical twilight", facts, .astroDawn, .astroDusk)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func eventRow(_ label: LocalizedStringKey, _ facts: SunDayFacts,
                          _ morning: SunEventKind, _ evening: SunEventKind) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                LabeledContent("Morning", value: when(facts, morning)).foregroundStyle(SN.sunrise)
                LabeledContent("Evening", value: when(facts, evening)).foregroundStyle(SN.sunset)
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sun-event-\(morning.rawValue)")
        } else {
            GridRow {
                Text(label).fixedSize(horizontal: false, vertical: true)
                Text(when(facts, morning)).foregroundStyle(SN.sunrise).monospacedDigit()
                    .fixedSize()
                Text(when(facts, evening)).foregroundStyle(SN.sunset).monospacedDigit()
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sun-event-\(morning.rawValue)")
        }
    }
}
