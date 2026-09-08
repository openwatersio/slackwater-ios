import XCTest
import SwiftUI
import TideEngine
@testable import Slackwater

/// The tidal plane ladder (#217): what it draws, what it refuses to draw, and
/// the label dodge that keeps true spacing honest when rungs crowd.
final class TideLadderTests: XCTestCase {
    private var fridayHarbor: TideStationRecord {
        TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!
    }
    private var nurse: TideStationRecord {
        TideStationRecord.all.first { $0.id == "noaa/TEC4635" }!
    }
    private let day = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-14

    private func ladder(_ r: TideStationRecord) throws -> [LadderRung] {
        let station = r.engineStation
        let facts = try XCTUnwrap(r.rangeFacts(at: day, station: station))
        let now = station.heights(from: day, to: day.addingTimeInterval(1), step: 1).first?.height ?? 0
        return tideLadder(record: r, facts: facts, nowHeight: now)
    }

    // MARK: - What the ladder contains

    func testFridayHarborLaddersTopToBottom() throws {
        let rungs = try ladder(fridayHarbor)
        let names = rungs.map(\.name)
        for (a, b) in zip(rungs, rungs.dropFirst()) {
            XCTAssertGreaterThan(a.height, b.height, "\(a.name) must sit above \(b.name)")
        }
        // The envelope brackets everything EXCEPT a year that pokes outside
        // it, which is a real 5%-of-stations case and not something the ladder
        // hides — see the note in TideLadder.swift on why "possible" is not
        // the word. Everything that is not a record sits inside.
        let hat = try XCTUnwrap(rungs.first { $0.code == "HAT" }).height
        let lat = try XCTUnwrap(rungs.first { $0.code == "LAT" }).height
        for rung in rungs where rung.kind != .record {
            XCTAssertLessThanOrEqual(rung.height, hat, rung.name)
            XCTAssertGreaterThanOrEqual(rung.height, lat, rung.name)
        }
        XCTAssertTrue(names.contains("Chart datum"))
        XCTAssertTrue(names.contains("Average sea level"))
        XCTAssertTrue(names.contains("Now"))

        // Plain words lead; the acronym is an annotation and never the label.
        XCTAssertEqual(try XCTUnwrap(rungs.first { $0.code == "HAT" }).name, "Highest tide")
        XCTAssertEqual(try XCTUnwrap(rungs.first { $0.code == "LAT" }).name, "Lowest tide")
        XCTAssertEqual(try XCTUnwrap(rungs.first { $0.code == "MSL" }).name, "Average sea level")
        XCTAssertEqual(try XCTUnwrap(rungs.first { $0.kind == .datum }).code, "MLLW")
        XCTAssertNil(rungs.first { $0.name == "HAT" || $0.name == "LAT" || $0.name == "MSL" })
    }

    /// Every rung the reader can act on is a moment, and every moment is
    /// tappable — the records and the two ends of this swing. A plane is not
    /// a moment and must not pretend to be one.
    func testOnlyMomentsAreTappable() throws {
        let rungs = try ladder(fridayHarbor)
        for rung in rungs {
            switch rung.kind {
            case .record, .swing: XCTAssertNotNil(rung.jump, rung.name)
            case .plane, .datum, .now: XCTAssertNil(rung.jump, rung.name)
            }
        }
    }

    func testRecordRungsNameTheWindowTheyMean() throws {
        XCTAssertTrue(try ladder(fridayHarbor).contains { $0.name == "Lowest this year" })
        // A seasonless model ranks over a month, and the rung says so rather
        // than claiming a year it cannot see.
        let seasonless = seasonlessFridayHarbor
        XCTAssertTrue(try ladder(seasonless).contains { $0.name == "Lowest this month" })
    }

    // MARK: - What it refuses to draw

    func testASubordinateHasNoMeanSeaLevelRung() throws {
        XCTAssertEqual(nurse.datumOffset, 0)
        XCTAssertFalse(try ladder(nurse).contains { $0.code == "MSL" },
                       "a subordinate's datumOffset is 0 by construction; drawing it would put MSL on chart datum")
        XCTAssertTrue(try ladder(nurse).contains { $0.kind == .datum })
    }

    func testAFittedStationHasNoCeilingOrFloor() throws {
        let rungs = try ladder(seasonlessFridayHarbor)
        XCTAssertFalse(rungs.contains { $0.code == "HAT" || $0.code == "LAT" })
        // It still gets the water, the datum and its own month's records — the
        // gauge degrades by losing rungs, never by inventing them.
        XCTAssertTrue(rungs.contains { $0.kind == .now })
        XCTAssertTrue(rungs.contains { $0.kind == .datum })
        XCTAssertTrue(rungs.contains { $0.kind == .record })
    }

    /// At the 887 stations charted on LAT the floor IS chart datum. One rung,
    /// not two on the same line.
    func testCoincidentRungsCollapse() throws {
        let onLat = try XCTUnwrap(TideStationRecord.all.first { $0.latDatum == 0 && !$0.isSubordinate })
        let rungs = try ladder(onLat)
        XCTAssertEqual(rungs.filter { abs($0.height) < 0.001 }.count, 1)
        XCTAssertEqual(rungs.first { abs($0.height) < 0.001 }?.kind, .datum)
    }

    // MARK: - The dodge

    func testDodgeLeavesUncrowdedLabelsWhereTheyWere() {
        let ys: [CGFloat] = [10, 60, 120, 200]
        XCTAssertEqual(dodgedLabelYs(ys, minGap: 17, in: 0...300), ys)
    }

    func testDodgePushesCrowdedLabelsApartInOrder() {
        let out = dodgedLabelYs([100, 102, 104, 106], minGap: 17, in: 0...300)
        XCTAssertEqual(out, [100, 117, 134, 151])
        for (a, b) in zip(out, out.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 17) }
    }

    func testDodgeBacksOffTheBottomEdge() {
        let out = dodgedLabelYs([280, 285, 290, 295], minGap: 17, in: 0...300)
        XCTAssertEqual(out.last, 300)
        XCTAssertEqual(out, [249, 266, 283, 300])
        XCTAssertGreaterThanOrEqual(out.first!, 0)
    }

    /// More rungs than the gauge can space: spread evenly and lose true
    /// spacing, rather than clip rungs off the bottom.
    func testDodgeSpreadsEvenlyWhenTheGaugeIsTooShort() {
        let out = dodgedLabelYs([0, 1, 2, 3, 4, 5], minGap: 17, in: 0...50)
        XCTAssertEqual(out.first, 0)
        XCTAssertEqual(out.last, 50)
        XCTAssertEqual(out.count, 6)
        for (a, b) in zip(out, out.dropFirst()) { XCTAssertEqual(b - a, 10, accuracy: 0.001) }
    }

    func testDodgeHandlesOneAndNone() {
        XCTAssertEqual(dodgedLabelYs([], minGap: 17, in: 0...300), [])
        XCTAssertEqual(dodgedLabelYs([400], minGap: 17, in: 0...300), [300])
    }

    // MARK: - It draws

    /// The whole sheet body draws — the failure mode RenderProbes.swift opens
    /// with is a chart that renders nothing while every readout around it is
    /// right, and this page is mostly chart.
    @MainActor
    func testTheSheetBodyPutsInkOnTheCanvas() throws {
        let station = fridayHarbor.engineStation
        let facts = try XCTUnwrap(fridayHarbor.rangeFacts(at: day, station: station))
        let now = station.heights(from: day, to: day.addingTimeInterval(1), step: 1).first?.height ?? 0
        let rungs = tideLadder(record: fridayHarbor, facts: facts, nowHeight: now)
        let renderer = ImageRenderer(content:
            RangeDetailBody(record: fridayHarbor, facts: facts, rungs: rungs, at: day,
                            tz: fridayHarbor.tz, imperial: true, onJump: { _ in })
                .padding(20)
                .frame(width: 390, height: 780)
                .background(SN.canvas))
        let image = try XCTUnwrap(renderer.uiImage)
        // Measured against the same frame with no rungs: 0.0 (flat canvas).
        XCTAssertGreaterThan(inkFraction(image), 0.05)
    }

    private var seasonlessFridayHarbor: TideStationRecord {
        TideStationRecord(
            id: "chs-fake", name: "F", region: "R", aliases: [],
            latitude: fridayHarbor.latitude, longitude: fridayHarbor.longitude,
            timezone: fridayHarbor.timezone, chartDatum: "LLWLT",
            datumOffset: fridayHarbor.datumOffset,
            constituents: fridayHarbor.constituents.filter { $0.name != "SA" && $0.name != "SSA" })
    }
}
