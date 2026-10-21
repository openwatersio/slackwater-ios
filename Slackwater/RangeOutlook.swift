import SwiftUI

/// A week of daily range bars beside the Range readout. The week holds while
/// the scrub walks it, so the bars stand still and only the highlight moves.
struct RangeOutlook: View {
    let timeline: TimelineData
    /// The week's first local midnight, from `week(from:scrub:tz:)`.
    let week: Date
    /// The highlighted day is the one this instant falls in.
    let at: Date
    private var tz: TimeZone { timeline.tz }

    struct Day {
        let start: Date
        /// The day's biggest swing; nil until the loaded timeline holds the whole day.
        let peak: Peak?
    }

    /// The day of the week, counted from zero, that starts a new week: the
    /// sixth, which leaves one day of outlook.
    static let newWeekDay = 5

    /// The week the bars show with the scrub at `scrub`. Days before
    /// `newWeekDay` keep `week`; from it on, a new week starts on the scrub's
    /// day. A day before the week lands on the new week's day just short of
    /// `newWeekDay`, so going back travels as far between weeks as going forward.
    static func week(from week: Date?, scrub: Date, tz: TimeZone) -> Date {
        let day = dayLocal(scrub, tz)
        guard let week else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let offset = calendar.dateComponents([.day], from: week, to: day).day ?? 0
        if offset < 0 { return calendar.date(byAdding: .day, value: 1 - newWeekDay, to: day) ?? day }
        return offset < newWeekDay ? week : day
    }

    static func days(_ timeline: TimelineData, week: Date) -> [Day] {
        let tz = timeline.tz
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let peaks = SwingFigure.dailyPeaks(PeakStanding.swings(timeline.tideExtremes), tz: tz,
                                           window: (timeline.start, timeline.end))
        let byDay = Dictionary(peaks.map { (dayLocal($0.time, tz), $0) }, uniquingKeysWith: { first, _ in first })
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: week).map { Day(start: $0, peak: byDay[$0]) }
        }
    }

    var body: some View {
        let days = Self.days(timeline, week: week)
        let biggest = max(days.compactMap(\.peak?.magnitude).max() ?? 0, 0.001)
        let scrubDay = dayLocal(at, tz)
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(days, id: \.start) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SN.graphLine.opacity(day.start == scrubDay ? 1 : 0.4))
                        .frame(height: day.peak.map { max(2, geometry.size.height * $0.magnitude / biggest) } ?? 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("range-outlook")
    }
}
