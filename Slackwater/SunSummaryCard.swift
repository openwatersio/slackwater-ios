import SwiftUI

struct SunSummaryState {
    struct Event {
        let time: Date
        let isRise: Bool
    }

    let day: TimelineDay?
    let daylight: TimeInterval?
    let previous: Event?
    let next: Event?

    init(days: [TimelineDay], at: Date, tz: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        day = days.first { calendar.isDate($0.start, inSameDayAs: at) }
        if let day, let rise = day.sunrise, let set = day.sunset,
           let interval = calendar.dateInterval(of: .day, for: day.start) {
            let duration = set.timeIntervalSince(rise)
            daylight = duration >= 0 ? duration : interval.duration + duration
        } else {
            daylight = nil
        }
        let events = days.flatMap { day in
            [day.sunrise.map { Event(time: $0, isRise: true) },
             day.sunset.map { Event(time: $0, isRise: false) }].compactMap { $0 }
        }.sorted { $0.time < $1.time }
        previous = events.last { $0.time < at }
        next = events.first { $0.time > at }
    }
}

struct SunSummaryCard: View {
    let days: [TimelineDay]
    let at: Date
    let latitude: Double
    let longitude: Double
    let onJump: (Date) -> Void
    @Environment(\.timeZone) private var tz

    var body: some View {
        let state = SunSummaryState(days: days, at: at, tz: tz)
        let duration = state.daylight.map {
            Duration.seconds($0.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        } ?? "—"
        let nextEvent = state.next.map { event in
            let name = event.isRise ? String(localized: "Sunrise") : String(localized: "Sunset")
            return String(localized: "\(name) · \(chartTime(event.time, tz))",
                          comment: "Sun event name and local time.")
        } ?? "—"
        return ReadoutTile(label: String(localized: "Sun"), caption: duration,
                           accessibility: String(localized: "Sun"), detail: {
            AnyView(SunDetailSheet(at: at, latitude: latitude, longitude: longitude,
                                  tz: tz, onJump: onJump, days: days))
        }, fillsRow: true) {
            Image(systemName: state.next.map { $0.isRise ? "sunrise" : "sunset" } ?? "sun.max")
                .foregroundStyle(SN.sunrise)
        } value: {
            Text(nextEvent).font(ReadoutType.tileText.monospacedDigit())
        }
        .accessibilityIdentifier("sun-card-details")
    }
}
