// Slackwater — GPL v3. Printable tables: the pure model under the week and month sheets.
// Spans, per-day rows, night and prediction coverage. No HTML or UI here.
import Foundation

enum PrintSpan: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
}

private func localCalendar(_ tz: TimeZone) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal
}

/// week: anchor ..< anchor+7 local days. month: first local day of anchor's month ..< first of next month.
/// Calendar arithmetic, not 7 * 86_400: a DST change makes a local day 23 or 25 hours.
func printRange(_ span: PrintSpan, anchor: Date, tz: TimeZone) -> Range<Date> {
    let cal = localCalendar(tz)
    switch span {
    case .week:
        let start = cal.startOfDay(for: anchor)
        return start..<cal.date(byAdding: .day, value: 7, to: start)!
    case .month:
        let start = cal.dateInterval(of: .month, for: anchor)!.start
        return start..<cal.date(byAdding: .month, value: 1, to: start)!
    }
}

/// Local midnights stepping 7 days from range.lowerBound while < range.upperBound.
func printWeekAnchors(_ range: Range<Date>, tz: TimeZone) -> [Date] {
    let cal = localCalendar(tz)
    var out: [Date] = []
    var d = range.lowerBound
    while d < range.upperBound {
        out.append(d)
        d = cal.date(byAdding: .day, value: 7, to: d)!
    }
    return out
}

struct PrintDay: Equatable {
    let start: Date          // local midnight
    let sunrise: Date?
    let sunset: Date?
    let entries: [ScheduleEntry]   // sorted by time, all inside this day
}

/// Groups entries from each week's timeline into local days inside `range`,
/// dropping entries outside `covered` (nil = all covered) and deduping by `ScheduleEntry.id`.
/// Sun times come from the matching `TimelineDay` (by `start`). Days with no entries are omitted.
func printDays(timelines: [TimelineData], entries: (TimelineData) -> [ScheduleEntry],
               range: Range<Date>, covered: [Range<Date>]?, tz: TimeZone) -> [PrintDay] {
    let cal = localCalendar(tz)
    var seen = Set<String>()
    var byDay: [Date: [ScheduleEntry]] = [:]
    var sun: [Date: (rise: Date?, set: Date?)] = [:]
    for tl in timelines {
        for d in tl.days where sun[d.start] == nil { sun[d.start] = (d.sunrise, d.sunset) }
        for e in entries(tl) {
            guard range.contains(e.time),
                  covered?.contains(where: { $0.contains(e.time) }) ?? true,
                  seen.insert(e.id).inserted else { continue }
            byDay[cal.startOfDay(for: e.time), default: []].append(e)
        }
    }
    return byDay.keys.sorted().map { start in
        PrintDay(start: start, sunrise: sun[start]?.rise, sunset: sun[start]?.set,
                 entries: byDay[start]!.sorted { $0.time < $1.time })
    }
}

/// True when `t` falls outside its day's sunrise..<sunset.
///
/// A day missing either sun event is never night, as on the strip: `sunSpans`
/// (TimelineStrip.swift) only pairs a sunrise with a sunset, and `nightShade`
/// tints only the night spans, so an unpaired day is left unshaded.
func printIsNight(_ t: Date, in day: PrintDay) -> Bool {
    guard let rise = day.sunrise, let set = day.sunset else { return false }
    return !(rise..<set).contains(t)
}

/// nil when `covered` is nil or contains all of `range`. Otherwise
/// "Predictions available Nov 4 – 10 only." with ranges joined by ", ".
func printCoverageNote(range: Range<Date>, covered: [Range<Date>]?, tz: TimeZone,
                       locale: Locale = .autoupdatingCurrent) -> String? {
    guard let covered else { return nil }
    if covered.contains(where: { $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound }) {
        return nil
    }
    let formatter = DateIntervalFormatter()
    formatter.locale = locale
    formatter.timeZone = tz
    formatter.dateTemplate = "MMMd"
    // Ranges are half-open at local midnight; name the last day inside.
    let parts = covered.map { formatter.string(from: $0.lowerBound, to: $0.upperBound.addingTimeInterval(-1)) }
    return "Predictions available \(parts.joined(separator: ", ")) only."
}
