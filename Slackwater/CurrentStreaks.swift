// Slackwater — GPL v3. Shared pure current-streak flow and geometry seams.
import CoreLocation
import Foundation

let METRES_PER_SECOND_PER_KNOT = 0.514444
let STREAK_SPEED_SCALE = 40.0
let DODD_AXIS_M = 360.0
let DODD_SPREAD_M = 45.0
let DODD_STREAK_COUNT = 12

struct StationMapFlow {
    let center: CLLocationCoordinate2D
    let speedKn: Double
    let bearingDeg: Double
}

/// The fitted Dodd model, reduced to one local map-flow reading.
final class DoddMapFlowProvider {
    private let flowAtDate: (Date) -> StationMapFlow?

    /// Production reads only the fitted Dodd model. A missing model stays
    /// absent rather than inventing a map flow.
    init() {
        flowAtDate = { date in
            guard let gate = ChsCurrentGateInfo.all.first(where: { $0.id == "chs-dodd-narrows" }),
                  let model = ChsModelStore.loadCurrent(gate.id)
            else { return nil }
            let record = gate.record(with: model)
            guard let signedKn = record.engineStation
                .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed
            else { return nil }
            return Self.flow(gate: record, signedKn: signedKn)
        }
    }

    /// Test seam: keep model-store I/O outside pure flow behavior tests.
    init(gate: CurrentStationRecord, signedSpeed: @escaping (Date) -> Double?) {
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

/// `center` displaced along/across a local current bearing in metres.
func particleCoordinate(_ center: CLLocationCoordinate2D, bearingDeg: Double,
                        alongM: Double, acrossM: Double) -> CLLocationCoordinate2D {
    let bearing = bearingDeg * .pi / 180
    let east = alongM * sin(bearing) + acrossM * cos(bearing)
    let north = alongM * cos(bearing) - acrossM * sin(bearing)
    return CLLocationCoordinate2D(
        latitude: center.latitude + north / 111_320,
        longitude: center.longitude + east / (111_320 * cos(center.latitude * .pi / 180)))
}

func advanceCurrentCoordinate(_ origin: CLLocationCoordinate2D, vector: CurrentVector,
                              dt: TimeInterval, speedScale: Double) -> CLLocationCoordinate2D {
    particleCoordinate(origin, bearingDeg: vector.bearingDeg,
                       alongM: vector.speedKn * METRES_PER_SECOND_PER_KNOT * speedScale * dt,
                       acrossM: 0)
}

/// Unrendered lifecycle bound for Dodd's station-local approximation.
func doddEnvelopeContains(_ coordinate: CLLocationCoordinate2D, center: CLLocationCoordinate2D,
                          bearingDeg: Double = 0) -> Bool {
    let north = (coordinate.latitude - center.latitude) * 111_320
    let east = (coordinate.longitude - center.longitude)
        * 111_320 * cos(center.latitude * .pi / 180)
    let bearing = bearingDeg * .pi / 180
    let along = east * sin(bearing) + north * cos(bearing)
    let across = east * cos(bearing) - north * sin(bearing)
    return abs(along) <= DODD_AXIS_M / 2 && abs(across) <= DODD_SPREAD_M
}

struct DoddStreakSeed: Equatable {
    let alongM: Double
    let acrossM: Double
}

func doddSeed(index: Int) -> DoddStreakSeed {
    let i = Double(index)
    return DoddStreakSeed(
        alongM: (i * 0.6180339887).truncatingRemainder(dividingBy: 1) * DODD_AXIS_M - DODD_AXIS_M / 2,
        acrossM: sin(i * 2.3999632297) * DODD_SPREAD_M)
}

func doddRecycleCoordinate(index: Int, center: CLLocationCoordinate2D,
                           bearingDeg: Double) -> CLLocationCoordinate2D {
    let seed = doddSeed(index: index)
    return particleCoordinate(center, bearingDeg: bearingDeg,
                              alongM: seed.alongM, acrossM: seed.acrossM)
}
