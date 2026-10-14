import Almanac
import SwiftUI

struct SunDayFacts: Sendable {
    let interval: DateInterval
    let times: [SunMoment: Date]

    init(at: Date, tz: TimeZone, latitude: Double, longitude: Double) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        guard let interval = calendar.dateInterval(of: .day, for: at) else {
            throw AlmanacError.invalidArgument("Invalid calendar day")
        }
        let observer = try Observer(latitudeDeg: latitude, longitudeDeg: longitude)
        self.interval = interval
        var times: [SunMoment: Date] = [:]
        let events = try sunEvents(from: interval.start, to: interval.end, observer: observer)
        let edges = try sunWindowEdges(.goldenHour, from: interval.start, to: interval.end, observer: observer)
            + sunWindowEdges(.blueHour, from: interval.start, to: interval.end, observer: observer)
        for (time, moment) in events.map({ ($0.time, SunMoment($0.kind)) }) + edges where times[moment] == nil {
            times[moment] = time
        }
        self.times = times
    }

    func time(_ moment: SunMoment) -> Date? { times[moment] }

    /// Almanac's nine events always, a missing one reading "—"; a golden- or blue-hour
    /// edge only on a day it happens.
    var ordered: [SunMoment] {
        let nine = Set(SunEventKind.allCases.map(SunMoment.init))
        return SunMoment.allCases.filter { nine.contains($0) || times[$0] != nil }
            .sorted { (time($0) ?? interval.end) < (time($1) ?? interval.end) }
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
    /// Moves the timeline to a row's time; the sheet closes after.
    let onJump: (Date) -> Void
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


    private func table(_ facts: SunDayFacts) -> some View {
        VStack(spacing: 18) {
            ForEach(facts.ordered, id: \.rawValue) { moment in
                eventRow(moment, facts.time(moment))
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

    private func eventRow(_ moment: SunMoment, _ time: Date?) -> some View {
        let label: LocalizedStringKey
        let symbol: String
        let color: Color
        switch moment {
        case .astroDawn: (label, symbol, color) = ("Astronomical dawn", "sparkles", SN.sunrise)
        case .nauticalDawn: (label, symbol, color) = ("Nautical dawn", "moon.stars", SN.sunrise)
        case .morningBlueStart: (label, symbol, color) = ("Blue hour begins", "moon.haze", SN.graphLine)
        case .civilDawn: (label, symbol, color) = ("Civil dawn", "sun.horizon", SN.sunrise)
        case .morningBlueEnd: (label, symbol, color) = ("Blue hour ends", "moon.haze", SN.graphLine)
        case .rise: (label, symbol, color) = ("Sunrise", "sunrise", SN.sunrise)
        case .morningGoldenEnd: (label, symbol, color) = ("Golden hour ends", "sun.haze", SN.sun)
        case .transit: (label, symbol, color) = ("Solar noon", "sun.max", SN.sun)
        case .eveningGoldenStart: (label, symbol, color) = ("Golden hour begins", "sun.haze", SN.sun)
        case .set: (label, symbol, color) = ("Sunset", "sunset", SN.sunset)
        case .eveningBlueStart: (label, symbol, color) = ("Blue hour begins", "moon.haze", SN.graphLine)
        case .civilDusk: (label, symbol, color) = ("Civil dusk", "sun.horizon", SN.sunset)
        case .eveningBlueEnd: (label, symbol, color) = ("Blue hour ends", "moon.haze", SN.graphLine)
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
            HStack(spacing: 8) {
                Text(time.map { chartTime($0, tz) } ?? "—").foregroundStyle(color).fixedSize()
                if time != nil {
                    Image(systemName: "chevron.right").font(.caption2)
                        .foregroundStyle(SN.foam.opacity(0.5))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let time else { return }
            onJump(time)
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(time != nil ? .isButton : [])
        .accessibilityIdentifier("sun-event-\(moment.rawValue)")
    }
}
