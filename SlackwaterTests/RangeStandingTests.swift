import XCTest
import TideEngine
@testable import Slackwater

/// Tidal superlatives (#217): where a swing sits among the tides either side
/// of it, and the two independent gates on what a station may claim.
final class RangeStandingTests: XCTestCase {
    private var fridayHarbor: TideStationRecord {
        TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!
    }
    /// Nurse Channel — a NOAA subordinate with no constituents of its own.
    private var nurse: TideStationRecord {
        TideStationRecord.all.first { $0.id == "noaa/TEC4635" }!
    }
    private let day = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-14

    // MARK: - The two gates

    func testSeasonalGateReadsTheConstituentSetNotTheSource() {
        XCTAssertTrue(fridayHarbor.resolvesTheYear)
        // A subordinate has no constituents; it inherits its reference's answer
        // rather than reading its own empty set as "seasonless".
        XCTAssertTrue(nurse.constituents.isEmpty)
        XCTAssertEqual(nurse.resolvesTheYear, nurse.referenceRecord!.resolvesTheYear)

        // A CHS station is fitted over 60 days and Sa/Ssa need 183, so it can
        // never carry one — the gate closes without ever naming CHS.
        XCTAssertFalse(seasonlessFridayHarbor.resolvesTheYear)
        XCTAssertEqual(seasonlessFridayHarbor.rankingWindowMonths, 1)
        XCTAssertEqual(fridayHarbor.rankingWindowMonths, 6)
    }

    /// The envelope and the seasonal gate are independent facts. Asserting
    /// they travel together would be wrong for 230 bundled stations.
    func testEnvelopeAndSeasonalGateAreSeparateFacts() {
        let bounded = TideStationRecord.all.filter { $0.latDatum != nil }
        let yearly = TideStationRecord.all.filter(\.resolvesTheYear)
        XCTAssertGreaterThan(bounded.count, 4_700)
        XCTAssertGreaterThan(yearly.count, 4_500)
        XCTAssertFalse(bounded.allSatisfy(\.resolvesTheYear),
                       "a published envelope over a seasonless model is a real combination")
        XCTAssertTrue(TideStationRecord.all.allSatisfy { $0.latDatum == nil || $0.hatDatum! > $0.latDatum! })
    }

    /// 887 stations ship `latDatum` of exactly 0.000 because their chart datum
    /// IS LAT. Absence and zero mean different things and must stay distinct.
    func testZeroIsAValueAndAbsenceIsNot() {
        let zeroed = TideStationRecord.all.filter { $0.latDatum == 0 }
        XCTAssertGreaterThan(zeroed.count, 500)
        XCTAssertTrue(zeroed.allSatisfy { $0.hatDatum! > 0 })
        XCTAssertEqual(fridayHarbor.latDatum!, -1.123, accuracy: 0.001)
        XCTAssertEqual(fridayHarbor.hatDatum!, 2.86, accuracy: 0.001)
    }

    // MARK: - Standing

    private func series(_ values: [Double]) -> TideSeries {
        values.enumerated().map { (Date(timeIntervalSince1970: Double($0.offset) * 3600), $0.element) }
    }

    func testStandingReadsALowFromTheBottom() {
        // 0…9 at one-hour steps; stand at hour 5 and rank the value 2.
        let s = series([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let now = Date(timeIntervalSince1970: 5 * 3600)
        let low = standing(of: 2, in: s, at: now, lower: true)!
        XCTAssertEqual(low.rank, 0.3, accuracy: 1e-9)     // 0, 1, 2 are at or below
        XCTAssertEqual(low.recordValue, 0)
        XCTAssertEqual(low.recordTime, s[0].time)
        // Bottom 5% of ten samples is nearest-rank the minimum itself, which
        // lies behind `now` — so nothing remarkable is still ahead.
        XCTAssertNil(low.nextTime)
        // The last time the water went below 2, looking back from hour 5.
        XCTAssertEqual(low.previousTime, s[1].time)
    }

    func testStandingReadsAHighFromTheTop() {
        let s = series([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let now = Date(timeIntervalSince1970: 5 * 3600)
        let high = standing(of: 6, in: s, at: now, lower: false)!
        XCTAssertEqual(high.rank, 0.7, accuracy: 1e-9)
        XCTAssertEqual(high.recordValue, 9)
        XCTAssertEqual(high.nextValue, 9)                 // top 5% is still ahead
        XCTAssertEqual(high.nextTime, s[9].time)
        XCTAssertNil(high.previousTime, "nothing before hour 5 went above 6")
    }

    func testStandingIsNilOnAnEmptyWindow() {
        XCTAssertNil(standing(of: 1, in: [], at: day, lower: true))
    }

    // MARK: - The sentence

    private func fixture(_ value: Double, rank: Double, record: Double) -> Standing {
        Standing(value: value, rank: rank, recordValue: record, recordTime: day,
                 nextValue: nil, nextTime: nil, previousTime: nil)
    }

    /// The polarity is the one thing here that is easy to invert and
    /// impossible to eyeball: `rank` counts what is at or BELOW, so a low
    /// reads it straight and a high reads its complement.
    func testTheSentenceCountsWhatGoesPastNotWhatSitsBelow() {
        // A low that 97% of lows go below is a HIGH low, not a remarkable one.
        XCTAssertEqual(standingSentence(fixture(1.4, rank: 0.97, record: -1.1),
                                        lower: true, noun: "low", verb: "go lower", span: "this year"),
                       "97% of lows this year go lower")
        // ...and a genuinely low one leaves almost nothing beneath it.
        XCTAssertEqual(standingSentence(fixture(-1.0, rank: 0.03, record: -1.1),
                                        lower: true, noun: "low", verb: "go lower", span: "this year"),
                       "3% of lows this year go lower")
        // A high reads from the top, so the same rank means the opposite.
        XCTAssertEqual(standingSentence(fixture(2.4, rank: 0.92, record: 2.9),
                                        lower: false, noun: "high", verb: "go higher", span: "this year"),
                       "8% of highs this year go higher")
        XCTAssertEqual(standingSentence(fixture(1.1, rank: 0.17, record: 3.0),
                                        lower: false, noun: "swing", verb: "are bigger", span: "this month"),
                       "83% of swings this month are bigger")
    }

    /// The claim the whole feature exists to make must not come out as "0%".
    func testTheSentenceSaysTheSuperlativeWhenNothingGoesPast() {
        XCTAssertEqual(standingSentence(fixture(-1.1, rank: 0.0007, record: -1.1),
                                        lower: true, noun: "low", verb: "go lower", span: "this year"),
                       "the lowest low this year")
        XCTAssertEqual(standingSentence(fixture(2.9, rank: 1, record: 2.9),
                                        lower: false, noun: "high", verb: "go higher", span: "this month"),
                       "the highest high this month")
        // A swing is biggest, never highest.
        XCTAssertEqual(standingSentence(fixture(3.0, rank: 1, record: 3.0),
                                        lower: false, noun: "swing", verb: "are bigger", span: "this year"),
                       "the biggest swing this year")
    }

    // MARK: - End to end

    func testFridayHarborRanksTheSwingItStandsIn() throws {
        let facts = try XCTUnwrap(fridayHarbor.rangeFacts(at: day, station: fridayHarbor.engineStation))
        XCTAssertTrue(facts.yearly)
        // Six months either side, so the window spans about a year.
        XCTAssertEqual(facts.to.timeIntervalSince(facts.from) / 86_400, 365, accuracy: 2)

        let swing = facts.swing
        XCTAssertGreaterThan(swing.height, 0)
        XCTAssertLessThan(swing.low.time, facts.to)
        // The swing is the one still to complete: its later turn is ahead.
        XCTAssertGreaterThan(swing.time, day)

        for standing in [facts.low, facts.high, facts.range] {
            let s = try XCTUnwrap(standing)
            XCTAssertGreaterThan(s.rank, 0)
            XCTAssertLessThanOrEqual(s.rank, 1)
        }
        // The window's own lowest low sits at or below the published LAT's
        // neighbourhood — the check that the relative ranking and the absolute
        // yardstick describe the same water.
        let low = try XCTUnwrap(facts.low)
        XCTAssertGreaterThanOrEqual(low.recordValue, fridayHarbor.latDatum! - 0.05)
        XCTAssertLessThan(low.recordValue, low.value + 0.001)
        let high = try XCTUnwrap(facts.high)
        XCTAssertLessThanOrEqual(high.recordValue, fridayHarbor.hatDatum! + 0.05)
    }

    /// A seasonless model must not be ranked over a year: the window narrows
    /// to a month, and the copy that depends on `yearly` never fires.
    func testASeasonlessModelRanksOverAMonth() throws {
        let seasonless = seasonlessFridayHarbor
        let facts = try XCTUnwrap(seasonless.rangeFacts(at: day, station: seasonless.engineStation))
        XCTAssertFalse(facts.yearly)
        XCTAssertNil(seasonless.latDatum, "nothing fitted on device earns an envelope")
        XCTAssertEqual(facts.to.timeIntervalSince(facts.from) / 86_400, 61, accuracy: 2)
    }

    func testSubordinateRanksThroughItsOwnOffsets() throws {
        let reference = try XCTUnwrap(nurse.referenceRecord)
        let sub = try XCTUnwrap(nurse.rangeFacts(at: day, station: nurse.engineStation))
        let ref = try XCTUnwrap(reference.rangeFacts(at: day, station: reference.engineStation))
        // Nurse Channel's highs are scaled 0.79 against Settlement Point's, so
        // its record high lands below the reference's: the ranking runs on
        // corrected water, never on the reference's own.
        XCTAssertLessThan(try XCTUnwrap(sub.high).recordValue,
                          try XCTUnwrap(ref.high).recordValue)
        XCTAssertGreaterThan(try XCTUnwrap(sub.range).rank, 0)
    }

    /// Friday Harbor with its seasonal terms struck out — what a 60-day CHS
    /// fit produces, without needing a device to fit one.
    private var seasonlessFridayHarbor: TideStationRecord {
        TideStationRecord(
            id: "chs-fake", name: "F", region: "R", aliases: [],
            latitude: fridayHarbor.latitude, longitude: fridayHarbor.longitude,
            timezone: fridayHarbor.timezone, chartDatum: "LLWLT",
            datumOffset: fridayHarbor.datumOffset,
            constituents: fridayHarbor.constituents.filter { $0.name != "SA" && $0.name != "SSA" })
    }
}
