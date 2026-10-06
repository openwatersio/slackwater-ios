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
    /// interesting against swings that actually rank where they claim to.
    /// Level standings, for the max/min section's facts — a different
    /// judgement from the swing's, and tested separately for that reason.
    private func standings() -> (marked: TideStanding, plain: TideStanding) {
        let all = windowExtremes(at)
        let lows = all.filter { $0.kind == .low }.sorted { $0.height < $1.height }
        return (TideStanding.at(lows[0], among: all)!,
                TideStanding.at(lows[lows.count / 2], among: all)!)
    }

    private func swingStandings() -> (marked: SwingStanding, plain: SwingStanding) {
        let all = windowExtremes(at)
        let sorted = all.ranges().sorted { $0.height < $1.height }
        let big = sorted.last!, mid = sorted[sorted.count / 2]
        return (SwingStanding.at(big.height, time: big.time, among: all)!,
                SwingStanding.at(mid.height, time: mid.time, among: all)!)
    }

    /// Three claimants, one line. Seasonal wins: at a lake, "this number is
    /// not really a tide" outranks "this one is big".
    func testSeasonalCaptionOutranksTheStanding() {
        let seasonal = TideStationRecord.record(id: "ticon/algonac_mi-9014070-usa-noaa")!
        XCTAssertNotNil(seasonal.seasonalRatio, "fixture station lost its flag")
        XCTAssertEqual(rangeCaption(record: seasonal, swing: swingStandings().marked, direction: "low to high"),
                       seasonalCaption(seasonal.seasonalRatio!))
    }

    /// The tile prints a swing, so its mark is about the swing.
    func testABigSwingTakesTheCaptionFromTheDirection() {
        XCTAssertEqual(rangeCaption(record: station, swing: swingStandings().marked, direction: "low to high"),
                       String(localized: "the fortnight's biggest"))
    }

    func testAnOrdinarySwingKeepsItsDirection() {
        XCTAssertEqual(rangeCaption(record: station, swing: swingStandings().plain, direction: "low to high"),
                       "low to high")
    }

    /// A station whose scan has not landed yet, or one too sparse to rank,
    /// says the ordinary thing rather than nothing.
    func testNoStandingKeepsTheDirection() {
        XCTAssertEqual(rangeCaption(record: station, swing: nil, direction: "high to low"),
                       "high to low")
    }

    // MARK: - The swing's standing (what the TILE ranks)

    private func swings(_ around: Date) -> [TideRange] { windowExtremes(around).ranges() }

    func testTheFortnightsBiggestSwingMarks() {
        let all = windowExtremes(at)
        let biggest = all.ranges().max { $0.height < $1.height }!
        let standing = SwingStanding.at(biggest.height, time: biggest.time, among: all)!
        XCTAssertTrue(standing.marks)
        XCTAssertNil(standing.nextBigger, "nothing in the window swings further")
    }

    func testAMiddlingSwingDoesNotMark() {
        let all = windowExtremes(at)
        let sorted = all.ranges().sorted { $0.height < $1.height }
        let middling = sorted[sorted.count / 2]
        XCTAssertFalse(SwingStanding.at(middling.height, time: middling.time, among: all)!.marks)
    }

    /// The tile ranks the quantity it prints. A station can have a big swing on
    /// a day whose low is unremarkable, so the two rankings genuinely differ —
    /// which is why ranking the level on a tile that prints a range was wrong.
    func testSwingRankAndLevelRankAreNotTheSameJudgement() {
        let all = windowExtremes(at)
        let disagreements = all.ranges().filter { r in
            let swing = SwingStanding.at(r.height, time: r.time, among: all)?.marks ?? false
            let level = TideStanding.at(r.low, among: all)?.marks ?? false
            return swing != level
        }
        XCTAssertFalse(disagreements.isEmpty, "if these always agreed the distinction would be academic")
    }

    func testTheNextBiggerSwingIsAheadInTime() {
        let all = windowExtremes(at)
        let sorted = all.ranges().sorted { $0.height < $1.height }
        let small = sorted[sorted.count / 3]
        let next = SwingStanding.at(small.height, time: small.time, among: all)?.nextBigger
        XCTAssertGreaterThan(try XCTUnwrap(next).time, small.time)
        XCTAssertGreaterThan(try XCTUnwrap(next).height, small.height)
    }

    func testTooFewSwingsRanksNothing() {
        XCTAssertNil(SwingStanding.at(2.0, time: at, among: []))
    }

    // MARK: - The sheet's facts

    private func facts(_ s: TideStanding, lat: Double?, hat: Double?) -> [StandingFact] {
        standingFacts(s, latDatum: lat, hatDatum: hat, imperial: false, unit: "m",
                      tz: station.tz, now: at)
    }

    /// The fact that makes the whole feature worth building: a superlative you
    /// cannot go and look at is trivia.
    func testTheNextBiggerOneIsTappable() {
        let s = standings().plain
        let fact = facts(s, lat: nil, hat: nil).first { $0.jumpTo != nil }
        XCTAssertEqual(fact?.jumpTo, s.nextMoreExtreme?.time)
    }

    func testTheWindowExtremeSaysSoAndOffersNoJump() {
        let marked = standings().marked
        let spoken = facts(marked, lat: nil, hat: nil)
        XCTAssertTrue(spoken.contains { $0.text.contains("lowest") && $0.jumpTo == nil })
        XCTAssertFalse(spoken.contains { $0.jumpTo != nil }, "nothing in the window is lower")
    }

    /// Review Focus 1: the absolute facts are absent, not zero, where the
    /// station's constituents cannot bound a year.
    func testWithoutBoundsNoAbsoluteFactIsClaimed() {
        let spoken = facts(standings().marked, lat: nil, hat: nil)
        XCTAssertFalse(spoken.contains { $0.text.contains("ever") })
    }

    /// A station whose chart datum IS LAT ships latDatum exactly 0.0, and 887
    /// of them do. Zero is a real floor, so the gap must still be stated.
    func testAZeroFloorIsAFloorNotAMissingValue() {
        let spoken = facts(standings().marked, lat: 0.0, hat: 5.4)
        XCTAssertTrue(spoken.contains { $0.text.contains("ever") })
    }

    /// The window is the station's local days, not the device's.
    func testTheWindowStartsAtStationLocalMidnight() {
        let w = TideStanding.window(around: at, tz: station.tz)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = station.tz
        XCTAssertEqual(cal.component(.hour, from: w.start), 0)
    }
}
