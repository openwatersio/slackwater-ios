// Slackwater — GPL v3. Printable tables: the page as HTML, ready for WebKit to print.
// Pure string building over the Task 1 model. No UI, no I/O.
import Foundation

enum PrintKind: Equatable {
    case tide(heightUnit: String)                        // "ft" / "m"
    case current(floodDeg: Double, ebbDeg: Double)       // set shown in the user's set format
    case derivedGate
}

struct PrintFacts: Equatable {
    let name: String
    let region: String
    let units: String          // e.g. "knots", "feet"
    let datum: String?         // tide only, e.g. "MLLW"
    let source: String         // e.g. "NOAA 9449880", "CHS 07795"
    let link: URL?             // shareURL(forStationID:at: nil, tz:)
}

struct PrintablePage {
    let span: PrintSpan
    let range: Range<Date>
    let tz: TimeZone
    let kind: PrintKind
    let facts: PrintFacts
    let days: [PrintDay]
    /// Night ranges from `printNightSpans`; an entry inside one is shaded.
    let nights: [Range<Date>]
    let covered: [Range<Date>]?
    let printedAt: Date
}

func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

private let printCSS = """
body { font-family: -apple-system, system-ui, sans-serif; color: #000; background: #fff; margin: 0; font-size: 9pt; line-height: 1.15; }
h1 { font-size: 14pt; margin: 0 0 2pt; }
.meta { margin: 0 0 4pt; font-size: 8.5pt; }
.coverage { margin: 0 0 4pt; font-size: 8.5pt; font-weight: bold; }
table { width: 100%; border-collapse: collapse; }
thead { display: table-header-group; }
th { text-align: left; border-bottom: 1px solid #000; padding: 1.5pt 4pt; white-space: nowrap; }
td { padding: 1pt 4pt; border-bottom: 1px solid #000; white-space: nowrap; }
tr { break-inside: avoid; page-break-inside: avoid; }
tr.day td { font-weight: bold; background: #f2f2f2; }
.night { background: #e8ecf2; }
.note { margin-left: 6pt; font-size: 8pt; }
/* Top, not middle: WebKit's print layout offset some cells of a middle-aligned month row. */
.mday td { padding: 1pt 3pt; vertical-align: top; }
.mday td + td { white-space: normal; }
.cur .mday td { font-size: 8.5pt; }
.mday .t { display: inline-block; white-space: nowrap; }
.mday .t + .t { margin-left: 3pt; }
.foot { margin-top: 6pt; font-size: 8pt; break-inside: avoid; page-break-inside: avoid; page-break-before: avoid; }
"""

func printableHTML(_ page: PrintablePage, setFormat: String) -> String {
    let tz = page.tz
    var out = "<!doctype html><html><head><meta charset=\"utf-8\"><style>\(printCSS)</style></head><body>\n"

    var title = htmlEscape(page.facts.name)
    if page.span == .month {
        title += " · " + htmlEscape(localizedFormatter("yMMMM", tz).string(from: page.range.lowerBound))
    }
    out += "<h1>\(title)</h1>\n"

    // Meta line: region · zone(s) · units · datum · source.
    let first = tz.abbreviation(for: page.range.lowerBound) ?? tz.identifier
    let last = tz.abbreviation(for: page.range.upperBound.addingTimeInterval(-1)) ?? tz.identifier
    var meta = [page.facts.region, first == last ? first : "\(first)/\(last)", page.facts.units]
    if case .tide = page.kind, let datum = page.facts.datum { meta.append(datum) }
    meta.append(page.facts.source)
    if case .current(let flood, let ebb) = page.kind {
        let f = formatSet(flood, format: setFormat), e = formatSet(ebb, format: setFormat)
        meta.append(String(localized: "Flood \(f), ebb \(e)",
                           comment: "Printed current table header: the set (compass point or bearing) of the flood and of the ebb, such as “Flood 090°, ebb 270°”."))
    }
    out += "<p class=\"meta\">\(meta.filter { !$0.isEmpty }.map(htmlEscape).joined(separator: " · "))</p>\n"

    if let note = printCoverageNote(range: page.range, covered: page.covered, tz: tz) {
        out += "<p class=\"coverage\">\(htmlEscape(note))</p>\n"
    }

    out += page.span == .week ? weekTable(page, setFormat: setFormat) : monthTable(page)

    out += "<div class=\"foot\">"
    if let link = page.facts.link { out += "<div>\(htmlEscape(link.absoluteString))</div>" }
    let printed = monthDayYear(page.printedAt, tz)
    out += "<div>\(htmlEscape(String(localized: "Printed \(printed)", comment: "Footer of a printed tide or current table. The value is the date it was printed.")))</div>"
    out += "<div>\(htmlEscape(String(localized: "Predictions are not observations. Not for navigation.", comment: "Footer disclaimer of a printed tide or current table.")))</div>"
    out += "</div>\n</body></html>\n"
    return out
}

// MARK: - Words

/// The schedule pill's word in sentence case.
func eventWord(_ pill: SchedulePill) -> String {
    switch pill {
    case .high: String(localized: "High", comment: "High-tide event label.")
    case .low: String(localized: "Low", comment: "Low-tide event label.")
    case .flood: String(localized: "Max flood", comment: "Maximum flood-current event label.")
    case .ebb: String(localized: "Max ebb", comment: "Maximum ebb-current event label.")
    case .minFlood: String(localized: "Minimum flood", comment: "Local minimum speed while the current continues in the flood direction without reversing.")
    case .minEbb: String(localized: "Minimum ebb", comment: "Local minimum speed while the current continues in the ebb direction without reversing.")
    case .slack: String(localized: "Slack", comment: "Slack-water event label.")
    case .eclipse: String(localized: "Lunar eclipse", comment: "Lunar eclipse event label.")
    case .solarEclipse: String(localized: "Solar eclipse", comment: "Solar eclipse event label in a printed table, sentence case.")
    }
}

private func th(_ s: String) -> String { "<th>\(htmlEscape(s))</th>" }

// MARK: - Week

private func weekTable(_ page: PrintablePage, setFormat: String) -> String {
    let tz = page.tz
    let timeH = String(localized: "Time", comment: "Column header of a printed tide or current table: the time of day.")
    let eventH = String(localized: "Event", comment: "Column header of a printed tide or current table: what happens at that time.")
    var heads = [timeH, eventH]
    var columns = 2
    switch page.kind {
    case .tide:
        heads.append(String(localized: "Height", comment: "Column header of a printed tide table: the water height."))
        columns = 3
    case .current:
        heads.append(String(localized: "Speed", comment: "Column header of a printed current table: the current speed."))
        heads.append(String(localized: "printable.column.set", defaultValue: "Set", comment: "Column header on a printed current table: the direction the current flows toward."))
        columns = 4
    case .derivedGate:
        break
    }
    var out = "<table><thead><tr>\(heads.map(th).joined())</tr></thead><tbody>\n"
    let dayFmt = localizedFormatter("EEEMMMd", tz)
    for day in page.days {
        var label = htmlEscape(dayFmt.string(from: day.start))
        if let rise = day.sunrise, let set = day.sunset {
            label += " &nbsp; ☀︎ \(htmlEscape(chartTime(rise, tz))) – \(htmlEscape(chartTime(set, tz)))"
        } else {
            label += " &nbsp; ☀︎ —"
        }
        out += "<tr class=\"day\"><td colspan=\"\(columns)\">\(label)</td></tr>\n"
        for e in day.entries {
            let night = printIsNight(e.time, nights: page.nights)
            out += night ? "<tr class=\"night\">" : "<tr>"
            let isEclipse = e.pill == .eclipse || e.pill == .solarEclipse
            // An eclipse row's value is its peak time, which belongs with the event, not under Height.
            var event = eventWord(e.pill)
            if isEclipse, let peak = e.value {
                event = String(localized: "\(event) (peak \(peak))",
                               comment: "Event on a printed week table for a lunar or solar eclipse. The first value is the event name, “Lunar eclipse” or “Solar eclipse”. The second is the time of greatest eclipse, such as “3:12 AM”. The row’s own time is when the eclipse begins.")
            }
            out += "<td>\(htmlEscape(chartTime(e.time, tz)))</td><td>\(htmlEscape(event))</td>"
            switch page.kind {
            case .tide:
                out += "<td>\(htmlEscape(isEclipse ? "—" : (e.value ?? "—")))</td>"
            case .current:
                let hasSpeed = e.pill == .flood || e.pill == .ebb || e.pill == .minFlood || e.pill == .minEbb
                out += "<td>\(htmlEscape(hasSpeed ? (e.value ?? "—") : "—"))</td>"
                let set = hasSpeed ? e.arrowDeg.map { formatSet($0, format: setFormat) } : nil
                out += "<td>\(htmlEscape(set ?? "—"))</td>"
            case .derivedGate:
                break
            }
            out += "</tr>\n"
        }
    }
    return out + "</tbody></table>\n"
}

// MARK: - Month

private func monthTable(_ page: PrintablePage) -> String {
    let tz = page.tz
    let dayH = String(localized: "Day", comment: "Column header of a printed month table: the date.")
    let slack = eventWord(.slack), flood = eventWord(.flood), ebb = eventWord(.ebb)
    let high = eventWord(.high), low = eventWord(.low)
    // Each column lists the pills it holds.
    let columns: [(head: String, pills: [SchedulePill])]
    switch page.kind {
    case .tide: columns = [(high, [.high]), (low, [.low])]
    case .current: columns = [(slack, [.slack]), (flood, [.flood]), (ebb, [.ebb])]
    case .derivedGate: columns = [(slack, [.slack])]
    }
    // A current month is the widest page; its rows print a size smaller so a usual month fits one sheet unwrapped.
    let cls = if case .current = page.kind { " class=\"cur\"" } else { "" }
    var out = "<table\(cls)><thead><tr>\(th(dayH))\(columns.map { th($0.head) }.joined())</tr></thead><tbody>\n"
    let dayFmt = localizedFormatter("EEEMMMd", tz)
    for day in page.days {
        var label = htmlEscape(dayFmt.string(from: day.start))
        for e in day.entries where e.pill == .eclipse || e.pill == .solarEclipse {
            label += "<span class=\"note\">\(htmlEscape(eventWord(e.pill))) \(htmlEscape(chartTime(e.time, tz)))</span>"
        }
        for e in day.entries where e.pill == .minFlood || e.pill == .minEbb {
            label += "<span class=\"note\">\(htmlEscape(eventWord(e.pill))) \(htmlEscape(chartTime(e.time, tz))) \(htmlEscape(e.value ?? ""))</span>"
        }
        out += "<tr class=\"mday\"><td>\(label)</td>"
        for col in columns {
            let cell = day.entries.filter { col.pills.contains($0.pill) }.map { e -> String in
                var text = htmlEscape(chartTime(e.time, tz))
                if let v = e.value, e.pill != .slack { text += " " + htmlEscape(v) }
                let cls = printIsNight(e.time, nights: page.nights) ? "t night" : "t"
                return "<span class=\"\(cls)\">\(text)</span>"
            }
            // A space between times gives a busy cell somewhere to wrap.
            out += "<td>\(cell.joined(separator: " "))</td>"
        }
        out += "</tr>\n"
    }
    return out + "</tbody></table>\n"
}
