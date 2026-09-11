import XCTest
@testable import Slackwater

/// The identity index (#317): the first frame renders from `station-index.json`
/// alone, so it has to say exactly what the full catalogs say about identity —
/// a name or a coordinate that drifts is a station the list and the detail
/// disagree about.
final class StationIndexTests: XCTestCase {
    func testIndexCoversEveryTideStation() {
        let rows = Dictionary(uniqueKeysWithValues: StationIndex.bundled.tides.map { ($0.id, $0) })
        XCTAssertEqual(rows.count, TideStationRecord.all.count)
        for record in TideStationRecord.all {
            guard let row = rows[record.id] else {
                return XCTFail("stations.json \(record.id) is missing from station-index.json")
            }
            XCTAssertEqual(row.name, record.name, record.id)
            XCTAssertEqual(row.region, record.region, record.id)
            XCTAssertEqual(row.aliases, record.aliases, record.id)
            XCTAssertEqual(row.latitude, record.latitude, record.id)
            XCTAssertEqual(row.longitude, record.longitude, record.id)
            XCTAssertEqual(row.timezone, record.timezone, record.id)
        }
    }

    func testIndexCoversEveryRenderedCurrentStation() {
        let rows = Dictionary(uniqueKeysWithValues: StationIndex.bundled.currents.map { ($0.id, $0) })
        let rendered = CurrentStationRecord.all.filter { $0.referenceOnly != true }
        XCTAssertEqual(rows.count, rendered.count)
        for record in rendered {
            guard let row = rows[record.id] else {
                return XCTFail("currents.json \(record.id) is missing from station-index.json")
            }
            XCTAssertEqual(row.name, record.name, record.id)
            XCTAssertEqual(row.region, record.region, record.id)
            XCTAssertEqual(row.aliases, record.aliases, record.id)
            XCTAssertEqual(row.latitude, record.latitude, record.id)
            XCTAssertEqual(row.longitude, record.longitude, record.id)
            XCTAssertEqual(row.timezone, record.timezone, record.id)
        }
        // A reference-only bin (#269) is a harmonic shape, never a station.
        for record in CurrentStationRecord.all where record.referenceOnly == true {
            XCTAssertNil(rows[record.id], "\(record.id) is reference-only")
        }
    }

    /// The regression this exists for: `StationItem.all` going back to
    /// `TideStationRecord.all` / `CurrentStationRecord.all` and putting the
    /// 9.1 MB constituent decode back on the first frame. Every NOAA item's id
    /// comes from the index and from nowhere else.
    func testStationItemAllIsIndexBacked() {
        let indexed = Set(StationIndex.bundled.tides.map(\.id))
            .union(StationIndex.bundled.currents.map { "current:" + $0.id })
        let noaa = Set(StationItem.all.compactMap { item -> String? in
            switch item {
            case .tide, .current: item.id
            case .chs, .chsGate, .chsCurrent: nil
            }
        })
        XCTAssertEqual(noaa, indexed)
    }

    /// The index is only useful if the record is still reachable by id — that
    /// lazy hop is what every detail view, card and map pin now takes.
    func testEveryIndexedStationResolvesItsRecord() {
        for item in StationItem.all {
            switch item {
            case .tide(let info):
                XCTAssertNotNil(info.tideRecord, "no tide record for \(info.id)")
            case .current(let info):
                XCTAssertNotNil(info.currentRecord, "no current record for \(info.id)")
            case .chs, .chsGate, .chsCurrent:
                continue
            }
        }
    }

    /// The point of the file: it has to be a fraction of what it replaces.
    func testIndexIsFarSmallerThanTheCatalogsItReplaces() throws {
        func bytes(_ name: String) throws -> Int {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"))
            return try Data(contentsOf: url).count
        }
        let index = try bytes("station-index")
        let catalogs = try bytes("stations") + bytes("currents")
        XCTAssertLessThan(index * 4, catalogs, "index \(index) vs catalogs \(catalogs)")
    }
}
