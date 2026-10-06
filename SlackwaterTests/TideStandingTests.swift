import XCTest
import SlackwaterKit
@testable import Slackwater

/// What counts as a remarkable tide, and over what window. The engine ranks;
/// these hold the two judgements the app makes on top of it.
final class TideStandingTests: XCTestCase {
    private let station = TideStationRecord.record(id: TideStationRecord.fridayHarborID)!
    /// A fixed instant so a ranking never depends on the day the suite runs.
    private let at = Date(timeIntervalSince1970: 1_780_000_000)  // 2026-05-29

    private func windowExtremes(_ around: Date) -> [TideExtreme] {
        let w = TideStanding.window(around: around, tz: station.tz)
        return station.engineStation.extremes(from: w.start, to: w.end)
    }

    func testTheWindowsLowestLowIsAWindowExtreme() {
        let all = windowExtremes(at)
        let lowest = all.filter { $0.kind == .low }.min { $0.height < $1.height }!
        let standing = TideStanding.at(lowest, among: all)!
        XCTAssertTrue(standing.isWindowExtreme)
        XCTAssertTrue(standing.marks)
        XCTAssertNil(standing.nextMoreExtreme, "nothing in the window is lower")
    }

    func testAMiddlingHighDoesNotMark() {
        let all = windowExtremes(at)
        let highs = all.filter { $0.kind == .high }.sorted { $0.height < $1.height }
        XCTAssertFalse(TideStanding.at(highs[highs.count / 2], among: all)!.marks)
    }

    /// Rarity is the feature. A fortnight holds about 29 highs; a mark that
    /// fires on half of them is wallpaper and says nothing.
    func testTheMarkStaysRare() {
        let all = windowExtremes(at)
        let marked = all.filter { TideStanding.at($0, among: all)?.marks == true }
        XCTAssertGreaterThan(marked.count, 0, "a fortnight always has a biggest tide")
        XCTAssertLessThan(Double(marked.count) / Double(all.count), 0.25)
    }

    /// A big tide's useful question is when the next bigger one comes, so
    /// "next" is forward in time, never the larger one last week.
    func testNextMoreExtremeLooksForward() {
        let all = windowExtremes(at)
        let lows = all.filter { $0.kind == .low }.sorted { $0.time < $1.time }
        let ordinary = lows.max { $0.height < $1.height }!
        let standing = TideStanding.at(ordinary, among: all)!
        let next = try? XCTUnwrap(standing.nextMoreExtreme)
        XCTAssertGreaterThan(next!.time, ordinary.time)
        XCTAssertLessThan(next!.height, ordinary.height)
    }

    /// Review Focus 3: a window with no company cannot rank anything.
    func testTooFewExtremesRanksNothing() {
        let one = windowExtremes(at)[0]
        XCTAssertNil(TideStanding.at(one, among: []))
        XCTAssertNil(TideStanding.at(one, among: [one]), "a set of one ranks nothing")
    }

    /// Review Focus 5. Thirty calendar days across a DST transition are not
    /// thirty × 86,400 seconds, so the window cannot be arithmetic on seconds.
    func testTheWindowIsCalendarDaysNotSeconds() {
        var cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        cal.timeZone = tz
        let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let w = TideStanding.window(around: noon, tz: tz, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day], from: w.start, to: w.end).day, 30)
        XCTAssertEqual(w.end.timeIntervalSince(w.start), 30 * 86_400 + 3_600, accuracy: 1,
                       "the fall-back day is 25 hours long")
    }

    func testTheStoreScansOnceAndRanksManyExtremes() async {
        let store = TideStandingStore()
        await store.load(record: station, around: at)
        XCTAssertGreaterThan(store.extremes.count, 50, "a fortnight either side is ~116 extremes")
        let lowest = store.extremes.filter { $0.kind == .low }.min { $0.height < $1.height }!
        XCTAssertEqual(store.standing(at: lowest)?.isWindowExtreme, true)
    }

    /// The tiles recompute as the scrubber moves; the scan must not. A second
    /// load for the same station is a no-op, which is what keeps it off the
    /// per-frame path.
    func testASecondLoadOfTheSameStationDoesNotRescan() async {
        let store = TideStandingStore()
        await store.load(record: station, around: at)
        let first = store.extremes.map(\.time)
        await store.load(record: station, around: at.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(store.extremes.map(\.time), first)
    }

    // MARK: - The Range tile's caption

    /// Real standings rather than fixtures: the caption rule is only
    /// interesting against tides that actually rank where they claim to.
    private func standings() -> (marked: TideStanding, plain: TideStanding) {
        let all = windowExtremes(at)
        let lows = all.filter { $0.kind == .low }.sorted { $0.height < $1.height }
        return (TideStanding.at(lows[0], among: all)!,
                TideStanding.at(lows[lows.count / 2], among: all)!)
    }

    /// Three claimants, one line. Seasonal wins: at a lake, "this number is
    /// not really a tide" outranks "this one is big".
    func testSeasonalCaptionOutranksTheStanding() {
        let seasonal = TideStationRecord.record(id: "ticon/algonac_mi-9014070-usa-noaa")!
        XCTAssertNotNil(seasonal.seasonalRatio, "fixture station lost its flag")
        XCTAssertEqual(rangeCaption(record: seasonal, standing: standings().marked, direction: "low to high"),
                       seasonalCaption(seasonal.seasonalRatio!))
    }

    func testAMarkedLowTakesTheCaptionFromTheDirection() {
        XCTAssertEqual(rangeCaption(record: station, standing: standings().marked, direction: "low to high"),
                       String(localized: "lowest in a fortnight"))
    }

    func testAnUnmarkedTideKeepsItsDirection() {
        XCTAssertEqual(rangeCaption(record: station, standing: standings().plain, direction: "low to high"),
                       "low to high")
    }

    /// A station whose scan has not landed yet, or one too sparse to rank,
    /// says the ordinary thing rather than nothing.
    func testNoStandingKeepsTheDirection() {
        XCTAssertEqual(rangeCaption(record: station, standing: nil, direction: "high to low"),
                       "high to low")
    }

    /// The window is the station's local days, not the device's.
    func testTheWindowStartsAtStationLocalMidnight() {
        let w = TideStanding.window(around: at, tz: station.tz)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        XCTAssertEqual(cal.component(.hour, from: w.start), 0)
    }
}
