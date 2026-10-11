import Almanac
import Foundation

/// A band of the Sun's altitude: daylight is sunrise to sunset, golden hour the Sun's
/// center between the horizon and +6°, blue hour between −4° and −8°. Golden hour's
/// horizon edges are Almanac's sunrise and sunset, so it meets daylight exactly.
enum SunWindow: String, Codable, Sendable { case daylight, goldenHour, blueHour }

/// A named moment in the Sun's day: Almanac's nine events plus the golden- and blue-hour
/// edges. Declared in a day's order; the raw values are the Sun sheet's accessibility ids.
enum SunMoment: String, CaseIterable, Sendable {
    case astroDawn, nauticalDawn, morningBlueStart, civilDawn, morningBlueEnd, rise,
         morningGoldenEnd, transit, eveningGoldenStart, set, eveningBlueStart, civilDusk,
         eveningBlueEnd, nauticalDusk, astroDusk

    init(_ kind: SunEventKind) { self.init(rawValue: kind.rawValue)! }

    /// True where a window opens; every other edge closes one.
    var opens: Bool { [.rise, .morningBlueStart, .eveningGoldenStart, .eveningBlueStart].contains(self) }
}

/// Every edge of `window` in `[from, to)`, in time order. The Sun sheet's rows and
/// `sunWindowSpans` both read this, so the two cannot disagree.
func sunWindowEdges(_ window: SunWindow, from: Date, to: Date,
                    observer: Observer) throws -> [(time: Date, moment: SunMoment)] {
    func horizon() throws -> [(time: Date, moment: SunMoment)] {
        try sunEvents(from: from, to: to, observer: observer)
            .filter { $0.kind == .rise || $0.kind == .set }
            .map { ($0.time, SunMoment($0.kind)) }
    }
    func crossings(_ deg: Double, rising: SunMoment,
                   falling: SunMoment) throws -> [(time: Date, moment: SunMoment)] {
        try sunAltitudeEvents(from: from, to: to, observer: observer, altitudeDeg: deg)
            .map { ($0.time, $0.kind == .rising ? rising : falling) }
    }
    let edges: [(time: Date, moment: SunMoment)]
    switch window {
    case .daylight: edges = try horizon()
    case .goldenHour: edges = try horizon() + crossings(6, rising: .morningGoldenEnd, falling: .eveningGoldenStart)
    case .blueHour: edges = try crossings(-8, rising: .morningBlueStart, falling: .eveningBlueEnd)
        + crossings(-4, rising: .morningBlueEnd, falling: .eveningBlueStart)
    }
    return edges.sorted { $0.time < $1.time }
}

/// The spans of `window` at a position, padded a day either side of the range so a time
/// near either end still finds its span — `daylightSpans`' contract, and for `.daylight`
/// its exact result. Each opening edge pairs with the next closing one, so a band the Sun
/// stays inside across midnight (a −4° to −4° blue night at 60° N in June) is one span.
/// ponytail: a day with no edge at all (the Sun parked inside or outside the band) has no
/// span, as a polar day has no daylight span.
func sunWindowSpans(_ window: SunWindow, from: Date, to: Date,
                    lat: Double, lon: Double) -> [ClosedRange<Date>] {
    guard let observer = try? Observer(latitudeDeg: lat, longitudeDeg: lon),
          let edges = try? sunWindowEdges(window, from: from.addingTimeInterval(-86_400),
                                          to: to.addingTimeInterval(86_400), observer: observer)
    else { return [] }
    var spans: [ClosedRange<Date>] = []
    var open: Date?
    for edge in edges {
        if edge.moment.opens {
            open = edge.time
        } else {
            if let start = open { spans.append(start...edge.time) }
            open = nil
        }
    }
    return spans
}
