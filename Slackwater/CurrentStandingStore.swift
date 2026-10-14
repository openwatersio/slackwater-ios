// Slackwater — GPL v3. One fortnight scan and one year scan per current
// station, held for the Next max tile and its sheet.
//
// The tide's store next door, with two differences. The fortnight is kept per
// DIRECTION, because floods rank against floods; and the year's series is
// SIGNED, so its envelope has flood above the line and ebb below, which is how
// the current track already draws.
import Foundation
import SlackwaterKit

@MainActor @Observable final class CurrentStandingStore {
    private(set) var floods: [Peak] = []
    private(set) var ebbs: [Peak] = []
    private(set) var window: (start: Date, end: Date) = (.distantPast, .distantPast)
    /// Kept per direction. A band drawn from the hardest ebb to the hardest
    /// flood is centred on zero, which makes a tenth's seasonal variation a
    /// twentieth of the drawn height and the year reads as a flat ribbon. One
    /// direction's own spread — its weakest monthly maximum to its strongest —
    /// is the question the sheet is asking anyway.
    private(set) var floodMonths: [YearFigure.Month] = []
    private(set) var ebbMonths: [YearFigure.Month] = []
    private var loaded: String?
    private var loadedYear: String?

    func load(record: CurrentStationRecord, around date: Date) async {
        guard loaded != record.id else { return }
        let w = TideStanding.window(around: date, tz: record.tz)
        let station = record.engineStation
        let events = await Task.detached(priority: .userInitiated) {
            station.events(from: w.start, to: w.end)
        }.value
        floods = CurrentStanding.peaks(events, kind: .maxFlood)
        ebbs = CurrentStanding.peaks(events, kind: .maxEbb)
        window = w
        loaded = record.id
    }

    /// The year, scanned only when the sheet that shows it opens — the tile
    /// reads no months, and this is the most expensive thing here.
    func loadYear(record: CurrentStationRecord, around date: Date) async {
        guard loadedYear != record.id else { return }
        let w = TideStanding.yearWindow(around: date, tz: record.tz)
        let station = record.engineStation, tz = record.tz
        let events = await Task.detached(priority: .userInitiated) {
            station.events(from: w.start, to: w.end)
        }.value
        floodMonths = YearFigure.months(CurrentStanding.peaks(events, kind: .maxFlood), tz: tz, window: w)
        ebbMonths = YearFigure.months(CurrentStanding.peaks(events, kind: .maxEbb), tz: tz, window: w)
        loadedYear = record.id
    }

    func months(_ kind: CurrentEventKind) -> [YearFigure.Month] {
        kind == .maxFlood ? floodMonths : ebbMonths
    }

    /// Where one maximum stands among its own direction's.
    func standing(speed: Double, time: Date, kind: CurrentEventKind) -> PeakStanding? {
        let among = kind == .maxFlood ? floods : ebbs
        return PeakStanding.at(abs(speed), time: time, among: among, window: window)
    }
}
