// Slackwater — GPL v3. One fortnight-either-side scan per station, held for the
// tile and its sheet to read.
//
// The summary tiles recompute as the scrubber moves and this cannot move with
// them: a ±6-month scan measures ~0.2 s on a Mac, so a ±15-day one is cheaper
// but still far too much for a frame. It also cannot run on the main actor,
// where SwiftUI's `.task` lands inside UIKit's first-commit block and
// synchronous work there delays the first frame — `StationIndexInfo
// .resolveTideRecord` hops off for the same reason.
import Foundation
import SlackwaterKit

@Observable final class TideStandingStore {
    private(set) var extremes: [TideExtreme] = []
    /// The window `extremes` came from, so a consumer can tell a whole local
    /// day from the fragment after its last midnight.
    private(set) var window: (start: Date, end: Date) = (.distantPast, .distantPast)
    /// The station already scanned. Keyed by id rather than by window: the
    /// window moves with the scrub and the ranking deliberately does not, so
    /// re-anchoring it per scrub would reintroduce the per-frame cost.
    private var loaded: String?

    func load(record: TideStationRecord, around date: Date) async {
        guard loaded != record.id else { return }
        let w = TideStanding.window(around: date, tz: record.tz)
        let station = record.engineStation
        extremes = await Task.detached(priority: .userInitiated) {
            station.extremes(from: w.start, to: w.end)
        }.value
        window = w
        loaded = record.id
    }

    /// The year, scanned only when the sheet that shows it opens.
    ///
    /// Twelve months of `extremes()` is the most expensive thing this feature
    /// does — #217's engine note measures ~0.2 s on a Mac, so budget about a
    /// second on a phone. The tile never pays for it: nothing on the tile reads
    /// a month, and a reader who does not open the sheet never asks the
    /// question this answers.
    private(set) var months: [YearFigure.Month] = []
    private var loadedYear: String?

    func loadYear(record: TideStationRecord, around date: Date) async {
        guard loadedYear != record.id, record.latDatum != nil else { return }
        let w = TideStanding.yearWindow(around: date, tz: record.tz)
        let station = record.engineStation, tz = record.tz
        months = await Task.detached(priority: .userInitiated) {
            YearFigure.months(station.extremes(from: w.start, to: w.end), tz: tz, window: w)
        }.value
        loadedYear = record.id
    }

    func standing(at extreme: TideExtreme) -> TideStanding? {
        TideStanding.at(extreme, among: extremes)
    }

    func swing(_ height: Double, time: Date) -> SwingStanding? {
        SwingStanding.at(height, time: time, among: extremes, window: window)
    }
}
