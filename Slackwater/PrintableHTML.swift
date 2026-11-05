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
body { font-family: -apple-system, system-ui, sans-serif; color: #000; background: #fff; margin: 0; font-size: 11pt; }
h1 { font-size: 18pt; margin: 0 0 4pt; }
.meta { margin: 0 0 8pt; font-size: 10pt; }
.coverage { margin: 0 0 8pt; font-size: 10pt; font-weight: bold; }
table { width: 100%; border-collapse: collapse; }
thead { display: table-header-group; }
th { text-align: left; border-bottom: 1px solid #000; padding: 3pt 4pt; }
td { padding: 2pt 4pt; border-bottom: 1px solid #000; }
tr { break-inside: avoid; }
tr.day td { font-weight: bold; background: #f2f2f2; }
.night { background: #e8ecf2; }
.note { margin-left: 6pt; font-size: 9pt; }
.mday .t { display: inline-block; margin-right: 8pt; white-space: nowrap; }
.foot { margin-top: 12pt; font-size: 9pt; }
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
private func eventWord(_ pill: SchedulePill) -> String {
    switch pill {
    case .high: String(localized: "High", comment: "High-tide event label.")
    case .low: String(localized: "Low", comment: "Low-tide event label.")
    case .flood: String(localized: "Max flood", comment: "Maximum flood-current event label.")
    case .ebb: String(localized: "Max ebb", comment: "Maximum ebb-current event label.")
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
        heads.append(String(localized: "Set", comment: "Column header of a printed current table: the direction the water flows."))
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
            out += "<td>\(htmlEscape(chartTime(e.time, tz)))</td><td>\(htmlEscape(eventWord(e.pill)))</td>"
            switch page.kind {
            case .tide:
                out += "<td>\(htmlEscape(e.value ?? "—"))</td>"
            case .current:
                let isMax = e.pill == .flood || e.pill == .ebb
                out += "<td>\(htmlEscape(isMax ? (e.value ?? "—") : "—"))</td>"
                let set = isMax ? e.arrowDeg.map { formatSet($0, format: setFormat) } : nil
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
    var out = "<table><thead><tr>\(th(dayH))\(columns.map { th($0.head) }.joined())</tr></thead><tbody>\n"
    let dayFmt = localizedFormatter("EEEMMMd", tz)
    for day in page.days {
        var label = htmlEscape(dayFmt.string(from: day.start))
        for e in day.entries where e.pill == .eclipse || e.pill == .solarEclipse {
            label += "<span class=\"note\">\(htmlEscape(eventWord(e.pill))) \(htmlEscape(chartTime(e.time, tz)))</span>"
        }
        out += "<tr class=\"mday\"><td>\(label)</td>"
        for col in columns {
            let cell = day.entries.filter { col.pills.contains($0.pill) }.map { e -> String in
                var text = htmlEscape(chartTime(e.time, tz))
                if let v = e.value, e.pill != .slack { text += " " + htmlEscape(v) }
                let cls = printIsNight(e.time, nights: page.nights) ? "t night" : "t"
                return "<span class=\"\(cls)\">\(text)</span>"
            }
            out += "<td>\(cell.joined())</td>"
        }
        out += "</tr>\n"
    }
    return out + "</tbody></table>\n"
}
