// Slackwater — GPL v3. Static current-direction features for the map.
import CoreLocation
import Foundation
import MapLibre
import UIKit

let CURRENT_DIRECTION_MIN_ZOOM = 9.0

struct StationMapFlow {
    let center: CLLocationCoordinate2D
    let speedKn: Double
    let bearingDeg: Double
}

/// Dodd predictions reduced to one local map-flow reading.
final class DoddMapFlowProvider: Sendable {
    private let flowAtDate: @Sendable (Date) -> StationMapFlow?

    /// Missing predictions stay absent rather than inventing a map flow.
    init() {
        flowAtDate = { date in
            guard let gate = ChsCurrentGateInfo.all.first(where: { $0.id == "chs-dodd-narrows" }),
                  let reading = gate.cachedReading(at: date) else { return nil }
            return StationMapFlow(
                center: CLLocationCoordinate2D(latitude: gate.latitude, longitude: gate.longitude),
                speedKn: abs(reading.signedKn),
                bearingDeg: reading.signedKn >= 0 ? reading.floodDirection
                    : (reading.floodDirection + 180).truncatingRemainder(dividingBy: 360))
        }
    }

    /// Test seam: keep model-store I/O outside pure flow behavior tests.
    init(gate: CurrentStationRecord, signedSpeed: @escaping @Sendable (Date) -> Double?) {
        flowAtDate = { date in
            guard let signedKn = signedSpeed(date) else { return nil }
            return Self.flow(gate: gate, signedKn: signedKn)
        }
    }

    func flow(at date: Date) -> StationMapFlow? { flowAtDate(date) }

    private static func flow(gate: CurrentStationRecord, signedKn: Double) -> StationMapFlow {
        StationMapFlow(
            center: CLLocationCoordinate2D(latitude: gate.latitude, longitude: gate.longitude),
            speedKn: abs(signedKn),
            bearingDeg: signedKn >= 0
                ? gate.floodDirection
                : (gate.floodDirection + 180).truncatingRemainder(dividingBy: 360))
    }
}

func currentDirectionFeature(at coordinate: CLLocationCoordinate2D,
                             bearingDeg: Double) -> MLNPointFeature {
    let feature = MLNPointFeature()
    feature.coordinate = coordinate
    feature.attributes = ["bearing": bearingDeg]
    return feature
}

func currentCellFeatures(_ cells: [FillCell],
                         excludingDirectionsIn exclusions: [FillCell] = [])
    -> [MLNShape & MLNFeature] {
    cells.flatMap { cell -> [MLNShape & MLNFeature] in
        var coordinates = cell.polygon
        let polygon = MLNPolygonFeature(coordinates: &coordinates,
                                        count: UInt(coordinates.count))
        polygon.attributes = [
            "colour": fillColourHex(forSpeedKn: cell.speedKn),
            "kn": cell.speedKn,
        ]
        let count = Double(cell.polygon.count)
        guard count > 0 else { return [polygon] }
        let center = CLLocationCoordinate2D(
            latitude: cell.polygon.reduce(0) { $0 + $1.latitude } / count,
            longitude: cell.polygon.reduce(0) { $0 + $1.longitude } / count)
        guard !exclusions.contains(where: {
            triangleContains(center, vertices: $0.polygon)
        }) else { return [polygon] }
        return [polygon, currentDirectionFeature(at: center, bearingDeg: cell.bearingDeg)]
    }
}

func currentDirectionImage() -> UIImage {
    let configuration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
    return UIImage(systemName: "arrow.up", withConfiguration: configuration)!
        .withRenderingMode(.alwaysTemplate)
}
