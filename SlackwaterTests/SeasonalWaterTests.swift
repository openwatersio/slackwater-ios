import XCTest
@testable import Slackwater

/// Water whose seasonal swing exceeds its principal tide (slackwater-database#220):
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
        XCTAssertEqual(flagged.count, 291)
    }

    /// The database flags a station when its seasonal peak exceeds the
    /// principal tide by more than 3 mm, so every flagged station's ratio, as
    /// the app computes it, is above 1. A station under 1 means the app's
    /// formula and the bundled flags come from different rules — a formula
    /// change without the database release that matches it, or the reverse.
    func testEveryFlaggedStationClearsTheDatabaseThreshold() {
        let flagged = TideStationRecord.all.filter { $0.seasonalDominant == true }
        let under = flagged.filter { ($0.seasonalRatio ?? 0) <= 1 }
        XCTAssertEqual(under.map(\.id), [], "\(under.count) of \(flagged.count) flagged stations sit at or under 1: " +
                       under.prefix(10).map { "\($0.id) \($0.seasonalRatio ?? -1)" }.joined(separator: ", "))
    }

    func testLeadsWhereTheAnnualCycleIsTheSignal() {
        // Cobourg on Lake Ontario: a principal tide of millimetres under a
        // third of a metre of seasonal swing.
        let cobourg = record("ticon/cobourg_ontario-13590-can-meds")
        XCTAssertEqual(cobourg.seasonalDominant, true)
        let ratio = try! XCTUnwrap(cobourg.seasonalRatio)
        XCTAssertEqual(ratio, 89.2, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(ratio, TideStationRecord.seasonalLeadRatio)
        XCTAssertEqual(seasonalTimes(ratio), "90")
    }

    func testStaysQuietWhereTheTideIsReal() {
        // Cedar Island, North Carolina, has a real tide and a seasonal swing
        // under twice its size. Leading with "mostly seasonal" there would be
        // false in effect while true in arithmetic — the reason there are two
        // bands rather than one sentence.
        let cedarIsland = record("noaa/8655151")
        XCTAssertEqual(cedarIsland.seasonalDominant, true)
        let ratio = try! XCTUnwrap(cedarIsland.seasonalRatio)
        XCTAssertEqual(ratio, 1.83, accuracy: 0.01)
        XCTAssertLessThan(ratio, TideStationRecord.seasonalLeadRatio)
    }

    /// A flagged synthetic station: the ratio's rules, apart from the bundle.
    private func flagged(_ constituents: [Con]) -> TideStationRecord {
        TideStationRecord(id: "test/seasonal", name: "Test", region: "", aliases: [],
                          latitude: 0, longitude: 0, timezone: "UTC", chartDatum: "",
                          datumOffset: 0, constituents: constituents, seasonalDominant: true)
    }

    func testTheRatioIsTheSeasonalPeakOverThePrincipalTide() {
        // N2 is left out: the database divides by M2+S2+K1+O1, and any other
        // denominator disagrees with its flag.
        let station = flagged([
            Con(name: "SA", amplitude: 0.3, phase: 0),
            Con(name: "M2", amplitude: 0.05, phase: 10), Con(name: "S2", amplitude: 0.02, phase: 20),
            Con(name: "K1", amplitude: 0.02, phase: 30), Con(name: "O1", amplitude: 0.01, phase: 40),
            Con(name: "N2", amplitude: 0.5, phase: 50),
        ])
        XCTAssertEqual(try XCTUnwrap(station.seasonalRatio), 3, accuracy: 1e-9)
    }

    func testTheSeasonalPeakWeighsPhase() {
        // In phase the terms add; a quarter apart the curve peaks at
        // 0.2·cos θ·(1 + sin θ) for θ = 30°, short of both their sum and
        // nothing like the larger amplitude alone.
        XCTAssertEqual(seasonalPeak([Con(name: "SA", amplitude: 0.2, phase: 0),
                                     Con(name: "SSA", amplitude: 0.1, phase: 0)]), 0.3, accuracy: 1e-9)
        XCTAssertEqual(seasonalPeak([Con(name: "SA", amplitude: 0.2, phase: 0),
                                     Con(name: "SSA", amplitude: 0.1, phase: 90)]),
                       0.2 * cos(Double.pi / 6) * 1.5, accuracy: 1e-9)
        XCTAssertEqual(seasonalPeak([Con(name: "SSA", amplitude: 0.1, phase: 77)]), 0.1, accuracy: 1e-9)
        XCTAssertEqual(seasonalPeak([Con(name: "M2", amplitude: 1, phase: 0)]), 0)
    }

    func testTheSeasonalTermsAreReadUnderEverySourcesNames() {
        // LINZ spells them Sa and Ssa.
        XCTAssertEqual(seasonalPeak([Con(name: "Sa", amplitude: 0.1, phase: 0),
                                     Con(name: "Ssa", amplitude: 0.1, phase: 0)]), 0.2, accuracy: 1e-9)
        // Kartverket's SA_KV is referenced to perihelion: moved by 283.4° it
        // lines up with an Ssa at 0° and the two add.
        XCTAssertEqual(seasonalPeak([Con(name: "SA_KV", amplitude: 0.1, phase: 76.6),
                                     Con(name: "Ssa", amplitude: 0.1, phase: 0)]), 0.2, accuracy: 1e-9)
        // SA_KV only stands in when there is no SA.
        XCTAssertEqual(seasonalPeak([Con(name: "SA", amplitude: 0.1, phase: 0),
                                     Con(name: "SA_KV", amplitude: 0.5, phase: 0)]), 0.1, accuracy: 1e-9)
    }

    func testAStationWithNoMeasurableTideHasAnInfiniteRatio() {
        // The database labels a station whose principal tide is published as
        // zero, so the ratio has to exist there rather than drop the screen.
        let lake = flagged([Con(name: "SA", amplitude: 0.3, phase: 0), Con(name: "M2", amplitude: 0, phase: 0)])
        let ratio = try! XCTUnwrap(lake.seasonalRatio)
        XCTAssertEqual(ratio, .infinity)
        XCTAssertEqual(seasonalCaption(ratio), "mostly seasonal")
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
        XCTAssertEqual(seasonalCaption(1.83), "partly seasonal")
    }

    func testRoundsToAFigureAReaderCanCarry() {
        // None of the precision is meaningful: it came out of a constituent fit.
        XCTAssertEqual(seasonalTimes(3.74), "3.7")
        XCTAssertEqual(seasonalTimes(43.3), "40")
        XCTAssertEqual(seasonalTimes(161.6), "160")
    }
}
