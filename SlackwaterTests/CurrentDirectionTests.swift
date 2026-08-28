import CoreLocation
import MapLibre
import XCTest
@testable import Slackwater

final class CurrentDirectionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_787_000_000)
    private let gate = CurrentStationRecord(
        id: "chs-dodd-narrows", name: "Dodd Narrows", region: "Nanaimo", aliases: [],
        latitude: 49.1344, longitude: -123.8171, timezone: "America/Vancouver",
        floodDirection: 21, ebbDirection: 201, meanFlow: 0, tideReference: nil, constituents: [])

    private func cell(_ bearing: Double = 73) -> FillCell {
        FillCell(polygon: [
            .init(latitude: 48.0, longitude: -123.0),
            .init(latitude: 48.0, longitude: -122.7),
            .init(latitude: 48.3, longitude: -123.0),
        ], speedKn: 2.5, bearingDeg: bearing)
    }

    func testCellProducesPolygonAndCentroidDirection() throws {
        let features = currentCellFeatures([cell()])
        XCTAssertEqual(features.count, 2)
        XCTAssertTrue(features[0] is MLNPolygonFeature)
        let point = try XCTUnwrap(features[1] as? MLNPointFeature)
        XCTAssertEqual(point.coordinate.latitude, 48.1, accuracy: 1e-12)
        XCTAssertEqual(point.coordinate.longitude, -122.9, accuracy: 1e-12)
        let bearing = try XCTUnwrap(point.attribute(forKey: "bearing") as? NSNumber)
        XCTAssertEqual(bearing.doubleValue, 73)
    }

    func testPatchCoverageSuppressesBackdropDirectionButNotPolygon() {
        let features = currentCellFeatures([cell()], excludingDirectionsIn: [cell(201)])
        XCTAssertEqual(features.count, 1)
        XCTAssertTrue(features[0] is MLNPolygonFeature)
    }

    func testDoddUsesAbsoluteSpeedAndReciprocalEbbBearing() throws {
        var evaluations = 0
        let provider = DoddMapFlowProvider(gate: gate, signedSpeed: { _ in
            evaluations += 1
            return -6
        })
        let flow = try XCTUnwrap(provider.flow(at: date))
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(flow.speedKn, 6)
        XCTAssertEqual(flow.bearingDeg, 201)
        XCTAssertEqual(flow.center.latitude, gate.latitude, accuracy: 1e-12)
        XCTAssertEqual(flow.center.longitude, gate.longitude, accuracy: 1e-12)
    }

    func testDoddOmitsMissingModel() {
        XCTAssertNil(DoddMapFlowProvider(gate: gate, signedSpeed: { _ in nil }).flow(at: date))
    }
}
