// Slackwater — GPL v3. Static current-direction features for the map.
import CoreLocation
import Foundation
import MapLibre
import SlackwaterKit
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
            return Self.flow(
                center: CLLocationCoordinate2D(latitude: gate.latitude, longitude: gate.longitude),
                signedKn: reading.signedKn, flood: reading.floodDirection,
                ebb: reading.ebbDirection, at: date)
        }
    }

    /// Test seam: keep model-store I/O outside pure flow behavior tests.
    init(gate: CurrentStationRecord, signedSpeed: @escaping @Sendable (Date) -> Double?) {
        flowAtDate = { date in
            guard let signedKn = signedSpeed(date) else { return nil }
            return Self.flow(
                center: CLLocationCoordinate2D(latitude: gate.latitude, longitude: gate.longitude),
                signedKn: signedKn, flood: gate.floodDirection, ebb: gate.ebbDirection, at: date)
        }
    }

    func flow(at date: Date) -> StationMapFlow? { flowAtDate(date) }

    /// The kit's vector reading takes the gate's published flood or ebb bearing by sign, which
    /// need not be reciprocal; a zero vector has no direction and draws no arrow.
    private static func flow(center: CLLocationCoordinate2D, signedKn: Double,
                             flood: Double, ebb: Double, at date: Date) -> StationMapFlow? {
        guard let vector = [CurrentPoint(time: date, speed: signedKn)]
            .vector(at: date, flood: flood, ebb: ebb),
              let bearing = vector.direction else { return nil }
        return StationMapFlow(center: center, speedKn: vector.magnitude, bearingDeg: bearing)
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
