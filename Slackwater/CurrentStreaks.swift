// Slackwater — GPL v3. Shared pure current-streak flow and geometry seams.
import CoreLocation
import Foundation
import MapLibre
import UIKit

let METRES_PER_SECOND_PER_KNOT = 0.514444
let STREAK_SPEED_SCALE = 40.0
let DODD_AXIS_M = 360.0
let DODD_SPREAD_M = 45.0
let DODD_STREAK_COUNT = 12
let STREAK_MIN_ZOOM = 9.0
let STREAK_HISTORY_LIMIT = 8

struct CurrentStreakParticle {
    let seed: CLLocationCoordinate2D
    var head: CLLocationCoordinate2D
    var history: [CLLocationCoordinate2D]
    var speedKn = 0.0
    var visible = false
}

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
    return abs(along) <= DODD_AXIS_M / 2 + 1e-6 && abs(across) <= DODD_SPREAD_M + 1e-6
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

/// One MapLibre source for both curved tails and coloured heads. The particle
/// state is intentionally small: local sampling is the field authority, and
/// a missing sample removes a mark rather than inventing still water.
final class CurrentStreakAnimator {
    static let sourceID = "current-streaks"
    static let tailLayerID = "current-streak-tails"
    static let headLayerID = "current-streak-heads"

    private var patchSample: (CLLocationCoordinate2D, Date) -> CurrentVector?
    private var fillSample: (CLLocationCoordinate2D, Date) -> CurrentVector?
    private let doddFlow: (Date) -> StationMapFlow?
    private weak var map: MLNMapView?
    private var source: MLNShapeSource?
    private var fillField: FillField?
    private var patchField: PatchField?
    private var timer: Timer?
    private var last = Date()
    private var visibleBounds: MLNCoordinateBounds?
    private var doddStamp = Date.distantPast
    private var cachedDodd: StationMapFlow?
    private(set) var certifiedParticles: [CurrentStreakParticle]
    private(set) var doddParticles: [CurrentStreakParticle] = []

    init(certifiedSeeds: [CLLocationCoordinate2D],
         patchSample: @escaping (CLLocationCoordinate2D, Date) -> CurrentVector?,
         fillSample: @escaping (CLLocationCoordinate2D, Date) -> CurrentVector?,
         doddFlow: @escaping (Date) -> StationMapFlow?) {
        self.certifiedParticles = certifiedSeeds.map(Self.particle)
        self.patchSample = patchSample
        self.fillSample = fillSample
        self.doddFlow = doddFlow
    }

    convenience init() {
        let dodd = DoddMapFlowProvider()
        self.init(certifiedSeeds: [], patchSample: { _, _ in nil }, fillSample: { _, _ in nil },
                  doddFlow: dodd.flow)
    }

    deinit { stop() }

    func attach(to style: MLNStyle, map: MLNMapView, fillField: FillField?, patchField: PatchField?) {
        self.map = map
        source = style.source(withIdentifier: Self.sourceID) as? MLNShapeSource
        self.fillField = fillField
        self.patchField = patchField
        fillSample = { coordinate, time in fillField?.sample(at: coordinate, time: time) }
        patchSample = { coordinate, time in patchField?.sample(at: coordinate, time: time) }
        certifiedParticles = []
        doddParticles = []
        cachedDodd = nil
        doddStamp = .distantPast
        last = Date()
        source?.shape = MLNShapeCollectionFeature(shapes: [MLNShape & MLNFeature]())
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        source = nil
        map = nil
    }

    /// Advances testable state and returns the exact shapes pushed to MapLibre.
    @discardableResult
    func advance(at time: Date, elapsed: TimeInterval, reduceMotion: Bool) -> [MLNShape & MLNFeature] {
        for index in certifiedParticles.indices {
            guard let vector = patchSample(certifiedParticles[index].head, time)
                    ?? fillSample(certifiedParticles[index].head, time)
            else {
                recycle(&certifiedParticles[index])
                continue
            }
            certifiedParticles[index].speedKn = vector.speedKn
            certifiedParticles[index].visible = true
            guard !reduceMotion else { continue }
            certifiedParticles[index].head = advanceCurrentCoordinate(
                certifiedParticles[index].head, vector: vector, dt: elapsed, speedScale: STREAK_SPEED_SCALE)
            appendHistory(&certifiedParticles[index])
        }

        updateDodd(at: time, elapsed: elapsed, reduceMotion: reduceMotion)
        return features(for: certifiedParticles) + features(for: doddParticles)
    }

    private func tick() {
        guard let map, let source else { return }
        let now = Date()
        let elapsed = min(now.timeIntervalSince(last), 0.5)
        last = now
        guard map.zoomLevel >= STREAK_MIN_ZOOM - 0.25 else { return }
        let bounds = map.visibleCoordinateBounds
        guard bounds.sw.latitude <= bounds.ne.latitude, bounds.sw.longitude <= bounds.ne.longitude else { return }
        if certifiedParticles.isEmpty { seedCertified(in: bounds, at: appNow()) }
        visibleBounds = bounds
        let shapes = advance(at: appNow(), elapsed: elapsed,
                             reduceMotion: UIAccessibility.isReduceMotionEnabled)
        visibleBounds = nil
        source.shape = MLNShapeCollectionFeature(shapes: shapes)
    }

    private func seedCertified(in bounds: MLNCoordinateBounds, at time: Date) {
        let box = FillBBox(minLon: bounds.sw.longitude, minLat: bounds.sw.latitude,
                           maxLon: bounds.ne.longitude, maxLat: bounds.ne.latitude)
        let cells = (patchField?.cells(at: time, in: box) ?? []) + (fillField?.cells(at: time, in: box) ?? [])
        let stride = max(1, cells.count / 48)
        certifiedParticles = cells.enumerated().compactMap { index, cell in
            guard index % stride == 0 else { return nil }
            let latitude = cell.polygon.reduce(0) { $0 + $1.latitude } / Double(cell.polygon.count)
            let longitude = cell.polygon.reduce(0) { $0 + $1.longitude } / Double(cell.polygon.count)
            return Self.particle(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }

    private func updateDodd(at time: Date, elapsed: TimeInterval, reduceMotion: Bool) {
        if abs(time.timeIntervalSince(doddStamp)) >= 60 {
            cachedDodd = doddFlow(time)
            doddStamp = time
            if let flow = cachedDodd, doddParticles.isEmpty {
                doddParticles = (0..<DODD_STREAK_COUNT).map { index in
                    Self.particle(doddRecycleCoordinate(index: index, center: flow.center,
                                                        bearingDeg: flow.bearingDeg))
                }
            }
        }
        guard let flow = cachedDodd else {
            doddParticles = []
            return
        }
        let vector = CurrentVector(speedKn: flow.speedKn, bearingDeg: flow.bearingDeg)
        for index in doddParticles.indices {
            doddParticles[index].speedKn = flow.speedKn
            doddParticles[index].visible = true
            if !reduceMotion {
                doddParticles[index].head = advanceCurrentCoordinate(
                    doddParticles[index].head, vector: vector, dt: elapsed, speedScale: STREAK_SPEED_SCALE)
                appendHistory(&doddParticles[index])
            }
            guard doddEnvelopeContains(doddParticles[index].head, center: flow.center,
                                      bearingDeg: flow.bearingDeg) else {
                doddParticles[index] = Self.particle(doddRecycleCoordinate(
                    index: index, center: flow.center, bearingDeg: flow.bearingDeg))
                doddParticles[index].speedKn = flow.speedKn
                doddParticles[index].visible = true
                continue
            }
        }
    }

    private static func particle(_ coordinate: CLLocationCoordinate2D) -> CurrentStreakParticle {
        CurrentStreakParticle(seed: coordinate, head: coordinate, history: [coordinate])
    }

    private func recycle(_ particle: inout CurrentStreakParticle) {
        particle.head = particle.seed
        particle.history = [particle.seed]
        particle.speedKn = 0
        particle.visible = false
    }

    private func appendHistory(_ particle: inout CurrentStreakParticle) {
        particle.history.append(particle.head)
        if particle.history.count > STREAK_HISTORY_LIMIT { particle.history.removeFirst() }
    }

    private func features(for particles: [CurrentStreakParticle]) -> [MLNShape & MLNFeature] {
        particles.flatMap { particle -> [MLNShape & MLNFeature] in
            guard particle.visible, isVisible(particle.head) else { return [] }
            let head = MLNPointFeature()
            head.coordinate = particle.head
            head.attributes = ["colour": fillColourHex(forSpeedKn: particle.speedKn)]
            guard particle.history.count > 1 else { return [head] }
            var history = particle.history
            let tail = MLNPolylineFeature(coordinates: &history, count: UInt(history.count))
            return [tail, head]
        }
    }

    private func isVisible(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let bounds = visibleBounds else { return true }
        return coordinate.latitude >= bounds.sw.latitude && coordinate.latitude <= bounds.ne.latitude
            && coordinate.longitude >= bounds.sw.longitude && coordinate.longitude <= bounds.ne.longitude
    }
}
