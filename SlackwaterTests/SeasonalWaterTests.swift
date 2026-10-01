import XCTest
@testable import Slackwater

/// Water whose yearly swing exceeds its daily one (slackwater-database#220):
/// a Great Lakes gauge, a river reach, a Baltic bodden. The predictions are
/// right; presenting them as a tide table is what misleads, so the detail view
/// says what the water is. The database decides which stations those are so the
/// app and slackwater.xyz cannot describe the same water two ways.
final class SeasonalWaterTests: XCTestCase {
    private func record(_ id: String) -> TideStationRecord {
        TideStationRecord.record(id: id)!
    }

    func testTheBundleCarriesTheDatabaseFlag() {
        // gen-tides drops the rest of the quality detail and keeps this one bit,
        // so a regeneration that dropped it too would leave every screen silent
        // with nothing failing.
        let flagged = TideStationRecord.all.filter { $0.seasonalDominant == true }
        XCTAssertEqual(flagged.count, 384)
    }

    func testLeadsWhereTheAnnualCycleIsTheSignal() {
        // Cobourg on Lake Ontario: a tidal range of millimetres under a third of
        // a metre of annual swing.
        let cobourg = record("ticon/cobourg_ontario-13590-can-meds")
        XCTAssertEqual(cobourg.seasonalDominant, true)
        let ratio = try! XCTUnwrap(cobourg.seasonalRatio)
        XCTAssertEqual(ratio, 161.6, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(ratio, TideStationRecord.seasonalLeadRatio)
        XCTAssertEqual(seasonalTimes(ratio), "160")
    }

    func testStaysQuietWhereTheTideIsReal() {
        // Annapolis (US Naval Academy) carries the flag at barely over 1 and has
        // a genuine Chesapeake tide. Leading with "mostly seasonal" there would
        // be false in effect while true in arithmetic — the reason there are two
        // bands rather than one sentence.
        let annapolis = record("noaa/8575512")
        XCTAssertEqual(annapolis.seasonalDominant, true)
        let ratio = try! XCTUnwrap(annapolis.seasonalRatio)
        XCTAssertEqual(ratio, 1.008, accuracy: 0.01)
        XCTAssertLessThan(ratio, TideStationRecord.seasonalLeadRatio)
    }

    func testAStationWithARealTideCarriesNothing() {
        let seattle = record("noaa/9447130")
        XCTAssertNil(seattle.seasonalRatio)
        // nil, not false: the database path and the stations.json path have to
        // spell "no" the same way or any comparison of the two is a trap.
        XCTAssertNil(seattle.seasonalDominant)
    }

    func testAFlaggedSubordinateIsMeasuredOnItsReference() {
        // A subordinate ships no constituents of its own, so reading its empty
        // list would drop it into the quieter band whatever its water is doing.
        let flagged = TideStationRecord.all.filter { $0.seasonalDominant == true && $0.isSubordinate }
        for station in flagged {
            XCTAssertNotNil(station.seasonalRatio,
                            "\(station.id) is flagged but has no ratio to speak with")
        }
    }

    func testTheTileCaptionIsGradedByHowFarTheTideIsLeftBehind() {
        // The caption replaces the swing's direction, so it has to earn the
        // line: two words that change the reading of the number above them.
        XCTAssertEqual(seasonalCaption(161.6), "mostly seasonal")
        XCTAssertEqual(seasonalCaption(3), "mostly seasonal")
        XCTAssertEqual(seasonalCaption(1.008), "partly seasonal")
    }

    func testRoundsToAFigureAReaderCanCarry() {
        // None of the precision is meaningful: it came out of a constituent fit.
        XCTAssertEqual(seasonalTimes(3.74), "3.7")
        XCTAssertEqual(seasonalTimes(43.3), "40")
        XCTAssertEqual(seasonalTimes(161.6), "160")
    }
}
