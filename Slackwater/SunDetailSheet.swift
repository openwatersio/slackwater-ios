import Almanac
import SwiftUI

struct SunDayFacts: Sendable {
    let interval: DateInterval
    let events: [SunEvent]

    init(at: Date, tz: TimeZone, latitude: Double, longitude: Double) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        guard let interval = calendar.dateInterval(of: .day, for: at) else {
            throw AlmanacError.invalidArgument("Invalid calendar day")
        }
        let observer = try Observer(latitudeDeg: latitude, longitudeDeg: longitude)
        self.interval = interval
        events = try sunEvents(from: interval.start, to: interval.end, observer: observer)
    }

    func time(_ kind: SunEventKind) -> Date? {
        events.first { $0.kind == kind }?.time
    }

    var orderedKinds: [SunEventKind] {
        let kinds: [SunEventKind] = [.astroDawn, .nauticalDawn, .civilDawn, .rise, .transit,
                                    .set, .civilDusk, .nauticalDusk, .astroDusk]
        return kinds.sorted { (time($0) ?? interval.end) < (time($1) ?? interval.end) }
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
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 24
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
                    } else if failed {
                        Text("Sun times unavailable.")
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .background(CanvasBackground())
            .navigationTitle("Sun activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task {
            facts = nil
            failed = false
            let result = await Task.detached {
                try? SunDayFacts(at: at, tz: tz, latitude: latitude, longitude: longitude)
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
        VStack(spacing: 18) {
            ForEach(facts.orderedKinds, id: \.rawValue) { kind in
                eventRow(facts, kind)
            }
            Divider()
            LabeledContent("Daylight", value: facts.daylight.map {
                Duration.seconds($0.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            } ?? "—")
            .fontWeight(.semibold)
            .accessibilityIdentifier("sun-daylight")
        }
        .font(.subheadline.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18))
    }

    private func eventRow(_ facts: SunDayFacts, _ kind: SunEventKind) -> some View {
        let label: LocalizedStringKey
        let symbol: String
        let color: Color
        switch kind {
        case .astroDawn: (label, symbol, color) = ("Astronomical dawn", "sparkles", SN.sunrise)
        case .nauticalDawn: (label, symbol, color) = ("Nautical dawn", "moon.stars", SN.sunrise)
        case .civilDawn: (label, symbol, color) = ("Civil dawn", "sun.horizon", SN.sunrise)
        case .rise: (label, symbol, color) = ("Sunrise", "sunrise", SN.sunrise)
        case .transit: (label, symbol, color) = ("Solar noon", "sun.max", SN.sun)
        case .set: (label, symbol, color) = ("Sunset", "sunset", SN.sunset)
        case .civilDusk: (label, symbol, color) = ("Civil dusk", "sun.horizon", SN.sunset)
        case .nauticalDusk: (label, symbol, color) = ("Nautical dusk", "moon.stars", SN.sunset)
        case .astroDusk: (label, symbol, color) = ("Astronomical dusk", "sparkles", SN.sunset)
        }
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                Text(label).fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(when(facts, kind)).foregroundStyle(color).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sun-event-\(kind.rawValue)")
    }
}
