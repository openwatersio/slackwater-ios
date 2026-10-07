// Slackwater — GPL v3. One fortnight scan and one year scan per current
// station, held for the Next max tile and its sheet.
//
// The tide's store next door, with two differences. The fortnight is kept per
// DIRECTION, because floods rank against floods; and the year's series is
// SIGNED, so its envelope has flood above the line and ebb below, which is how
// the current track already draws.
import Foundation
import SlackwaterKit

@Observable final class CurrentStandingStore {
    private(set) var floods: [Peak] = []
    private(set) var ebbs: [Peak] = []
    private(set) var window: (start: Date, end: Date) = (.distantPast, .distantPast)
    private(set) var months: [YearFigure.Month] = []
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
        months = await Task.detached(priority: .userInitiated) {
            YearFigure.months(station.events(from: w.start, to: w.end)
                .filter { $0.kind != .slack }
                .map { Peak(time: $0.time, magnitude: $0.speed) }, tz: tz, window: w)
        }.value
        loadedYear = record.id
    }

    /// Where one maximum stands among its own direction's.
    func standing(speed: Double, time: Date, kind: CurrentEventKind) -> PeakStanding? {
        let among = kind == .maxFlood ? floods : ebbs
        return PeakStanding.at(abs(speed), time: time, among: among, window: window)
    }
}
