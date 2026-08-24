// Slackwater — GPL v3. Station provenance shown on tide details (#170).
import XCTest
@testable import Slackwater

final class TideStationDetailsTests: XCTestCase {
    func testChsRecordNamesItsLLWLTChartDatum() throws {
        let info = try XCTUnwrap(ChsStationInfo.all.first)
        let model = ChsModel(
            stationID: info.id, iwlsID: "iwls", iwlsName: info.name,
            fittedAt: .now, fitStartMs: 0, fitEndMs: 1,
            offset: 1, rms: 0,
            constituents: [.init(name: "M2", amplitude: 1, phase: 0)])

        XCTAssertEqual(info.record(with: model).chartDatum, "LLWLT")
    }

    func testDatumDetailsNameOnlyKnownProviders() {
        XCTAssertEqual(record(id: "noaa/9449880", datum: "MLLW").detailsDatum,
                       "MLLW (NOAA chart datum)")
        XCTAssertEqual(record(id: "ticon/avonmouth", datum: "LAT").detailsDatum,
                       "LAT chart datum")
    }

    private func record(id: String, datum: String) -> TideStationRecord {
        TideStationRecord(
            id: id, name: "Test", region: "Test", aliases: [],
            latitude: 0, longitude: 0, timezone: "UTC",
            chartDatum: datum, datumOffset: 0, constituents: [])
    }
}
