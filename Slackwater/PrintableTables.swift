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

/// The nights to shade, as the strip draws them: every `!daylight` span of each
/// timeline's `sunSpans`, deduped, sorted and merged across week timelines.
///
/// `sunSpans` pairs a sunrise with the adjacent sunset, so a sunset that falls
/// after local midnight, before its civil day's sunrise, is handled the same
/// way here. A day with no pair contributes nothing, as on the strip.
func printNightSpans(timelines: [TimelineData]) -> [Range<Date>] {
    let nights = timelines.flatMap { $0.sunSpans }.filter { !$0.daylight && $0.start < $0.end }
        .map { $0.start..<$0.end }
        .sorted { $0.lowerBound < $1.lowerBound }
    var out: [Range<Date>] = []
    for n in nights {
        if let last = out.last, n.lowerBound <= last.upperBound {
            out[out.count - 1] = last.lowerBound..<max(last.upperBound, n.upperBound)
        } else {
            out.append(n)
        }
    }
    return out
}

/// True when `t` falls inside one of `nights` (from `printNightSpans`).
func printIsNight(_ t: Date, nights: [Range<Date>]) -> Bool {
    nights.contains { $0.contains(t) }
}

/// Covered ranges sorted, with any that overlap or sit within one official
/// sample of each other joined: online blocks requested to abut arrive one
/// sample apart (`ChsOnlineWindow.sampleInterval`).
private func mergedCoverage(_ covered: [Range<Date>]) -> [Range<Date>] {
    var out: [Range<Date>] = []
    for r in covered.sorted(by: { $0.lowerBound < $1.lowerBound }) {
        if let last = out.last,
           r.lowerBound.timeIntervalSince(last.upperBound) <= ChsOnlineWindow.sampleInterval {
            out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
        } else {
            out.append(r)
        }
    }
    return out
}

/// nil when `covered` is nil or contains all of `range`. Otherwise
/// "Predictions available Nov 4 – 10 only." with ranges joined by ", ",
/// naming only the days inside `range`: a preview's coverage starts two days
/// before today, and stored online blocks can lie wholly outside a month.
func printCoverageNote(range: Range<Date>, covered: [Range<Date>]?, tz: TimeZone,
                       locale: Locale = .autoupdatingCurrent) -> String? {
    guard let covered else { return nil }
    let merged = mergedCoverage(covered).compactMap { r -> Range<Date>? in
        let lower = max(r.lowerBound, range.lowerBound), upper = min(r.upperBound, range.upperBound)
        return lower < upper ? lower..<upper : nil
    }
    if merged.contains(where: { $0 == range }) { return nil }
    if merged.isEmpty {
        return String(localized: "No predictions available for these days.",
                      comment: "Note on a printed tide or current table when the predictions on this device cover none of the printed days.")
    }
    let formatter = DateIntervalFormatter()
    formatter.locale = locale
    formatter.timeZone = tz
    formatter.dateTemplate = "MMMd"
    // Ranges are half-open at local midnight; name the last day inside.
    let parts = merged.map { formatter.string(from: $0.lowerBound, to: $0.upperBound.addingTimeInterval(-1)) }
    let list = parts.joined(separator: ", ")
    return String(localized: "Predictions available \(list) only.",
                  comment: "Note on a printed tide or current table when official predictions cover only part of the printed span. The value is a comma-separated list of date ranges in the place’s time zone, such as “Nov 4 – 10, Nov 15 – 17”.")
}

/// The printed header's source: the publisher by name, then the station's own ID.
/// "NOAA 9449880" for `noaa/9449880`; "Kartverket ANX" for `kartverket/ANX` when the
/// tcdb names its publisher. A CHS place prints "CHS" alone: its key (`chs-sechelt-rapids`)
/// is this app's, and the bundle carries no CHS station code. Anything else prints its ID.
func printSourceLabel(id: String, publisher: String? = nil) -> String {
    if id.hasPrefix("chs-") { return "CHS" }
    let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return id }
    if parts[0] == "noaa" { return "NOAA \(parts[1])" }
    if let publisher, !publisher.isEmpty { return "\(publisher) \(parts[1])" }
    return id
}

/// A derived gate's printed source. Its slack times are Slackwater's estimate
/// from a reference port's tides, not anything CHS publishes, so the header
/// names the port instead of a publisher.
func printDerivedSourceLabel(portName: String) -> String {
    String(localized: "Estimated from \(portName) tides",
           comment: "Source on a printed slack table for a pass where CHS publishes no current predictions. Slackwater estimates the slack times from high and low water at a nearby tide station. The value is that tide station’s name, such as “Point Atkinson”.")
}

// MARK: - Sources and building a page

enum PrintableSource {
    /// Bundled and downloaded models: predicts any range.
    case computed(TimelineSource)
    /// Data already on the device only. `timeline(w)` builds the week anchored at local midnight `w`
    /// from that data, or nil. Never fetches.
    case fetched(covered: [Range<Date>], timeline: @Sendable (Date) -> TimelineData?)
}

struct PrintableConfig {
    let source: PrintableSource
    let kind: PrintKind
    let facts: PrintFacts
    /// The detail's schedule closure, without eclipses; the builder adds `eclipseEntries`.
    let entries: (TimelineData) -> [ScheduleEntry]
    /// Sheet-only line after the coverage note, saying where to download more; nil for computed sources.
    var moreHint: String? = nil
}

/// One TimelineData per week anchor in `range` (`printWeekAnchors`). Pure and synchronous;
/// the sheet calls it off the main actor.
///
/// Each computed chunk runs one local day past its week. A chunk keeps an eclipse by its peak
/// and `eclipseEntries` keeps it by its start, so an eclipse that starts on a week's last day
/// and peaks after midnight needs that day to reach the page. Entries still filter to each
/// timeline's `scheduleRange`, and `printDays` drops the duplicates at the seam.
func printTimelines(_ source: PrintableSource, range: Range<Date>, tz: TimeZone, now: Date) -> [TimelineData] {
    let anchors = printWeekAnchors(range, tz: tz)
    switch source {
    case .computed(let src):
        let cal = localCalendar(tz)
        return anchors.map { w in
            let end = cal.date(byAdding: .day, value: 8, to: w)!
            return TimelineData.merged([TimelineChunk.build(src, index: 0, start: w, end: end)],
                                       source: src, anchor: w, today: dayLocal(now, tz))
        }
    case .fetched(_, let timeline):
        return anchors.compactMap(timeline)
    }
}

func printablePage(_ config: PrintableConfig, span: PrintSpan, anchor: Date, tz: TimeZone,
                   timelines: [TimelineData], printedAt: Date) -> PrintablePage {
    let range = printRange(span, anchor: anchor, tz: tz)
    let covered: [Range<Date>]?
    switch config.source {
    case .computed: covered = nil
    case .fetched(let c, _): covered = c
    }
    let days = printDays(timelines: timelines, entries: { config.entries($0) + eclipseEntries($0) },
                         range: range, covered: covered, tz: tz)
    return PrintablePage(span: span, range: range, tz: tz, kind: config.kind, facts: config.facts,
                         days: days, nights: printNightSpans(timelines: timelines),
                         covered: covered, printedAt: printedAt)
}
