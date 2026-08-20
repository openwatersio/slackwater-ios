// Slackwater — GPL v3. SPIKE (#57, behind `-currentParticles`): an animated
// particle field over the 11 fitted CHS gates, so the fidelity decision can be
// made from something on a screen instead of in the abstract.
//
// Mechanism: a timer-driven GeoJSON point source updated at animation rate —
// NOT a Metal MLNCustomStyleLayer. ~170 points at 30 Hz is nothing for the
// GeoJSON path, and the style-JSON layer gets state colour (PIN_STATE_COLOUR,
// verbatim reuse) and the zoom threshold (`minzoom`) for free; a custom layer
// is a renderer to own, maintain, and keep working offline, and this spike
// exists to find out whether the cheap mechanism already reads as motion.
//
// The style build gets an EMPTY source + one layer dict (microseconds — the
// 300 ms ceiling in testPinLayerBuildsInsideAFrame is untouched); everything
// live happens post-load on the animator's timer. Flag off, nothing is added
// anywhere.
import CoreLocation
import Foundation
import MapLibre
import UIKit

/// The spike's gate — a launch argument, the same pattern as
/// `-networkKillSwitch`. No settings UI: judging the spike needs one switch,
/// not a surface.
let currentParticlesEnabled = CommandLine.arguments.contains("-currentParticles")

/// Below this zoom the particle layer is hidden (style `minzoom`) and the
/// timer skips all work — continental zooms show plain pins. 9 is where a
/// ~1 km gate axis is meaningfully sized on an iPhone (issue #57 decision 3).
let PARTICLE_MIN_ZOOM = 9.0

/// The drawn axis: a segment this long, centred on the gate, along its flood
/// axis. Long enough to read as "water moving through the pass" at z9–12.
let PARTICLE_AXIS_M = 1200.0
/// Perpendicular scatter so the field reads as water, not beads on a wire.
let PARTICLE_SPREAD_M = 150.0
let PARTICLES_PER_GATE = 28
/// Real water crosses 1.2 km in ~8 min at 5 kn — invisible. ×40 makes 5 kn
/// traverse the axis in ~12 s and slack (<0.15 kn) a near-still creep, so
/// particle speed still ENCODES water speed, just legibly.
let PARTICLE_SPEED_SCALE = 40.0
/// Comet tail: each particle drags a trail this many seconds of animated
/// motion long, so tail LENGTH also encodes speed — 5 kn ≈ 310 m, slack a
/// stub. The axis is straight, so the tail is the analytic segment behind
/// the head: no position history to keep.
let PARTICLE_TRAIL_S = 3.0

/// Tail endpoint along the axis: `trailM` behind the head w.r.t. motion
/// (ebb runs the axis backwards), clamped at the wrap boundary rather than
/// wrapped across it — a tail may briefly shorten, never jump.
func particleTailAlong(_ along: Double, signed: Double, trailM: Double,
                       axisM: Double) -> Double {
    let tail = along - (signed < 0 ? -trailM : trailM)
    return max(-axisM / 2, min(axisM / 2, tail))
}

/// Wrap `x` into [0, length) — particle recycling along the axis.
func particleWrap(_ x: Double, _ length: Double) -> Double {
    let m = x.truncatingRemainder(dividingBy: length)
    return m < 0 ? m + length : m
}

/// `center` displaced `alongM` metres along `bearingDeg` (true) and `acrossM`
/// metres perpendicular to it. Local-tangent-plane arithmetic — fine for a
/// kilometre at 50°N.
func particleCoordinate(_ center: CLLocationCoordinate2D, bearingDeg: Double,
                        alongM: Double, acrossM: Double) -> CLLocationCoordinate2D {
    let b = bearingDeg * .pi / 180
    let east = alongM * sin(b) + acrossM * cos(b)
    let north = alongM * cos(b) - acrossM * sin(b)
    return CLLocationCoordinate2D(
        latitude: center.latitude + north / 111_320,
        longitude: center.longitude + east / (111_320 * cos(center.latitude * .pi / 180)))
}

/// The style-build side: an empty GeoJSON source, a line layer for the comet
/// tails, and a circle layer for the heads — both coloured by the SAME state
/// expression the pins use, hidden below the zoom threshold. Appended (on
/// top — moving water over static pins) by both style builders when the flag
/// is on. One source carries both geometries; geometry-type filters keep
/// each layer to its own kind.
func addParticleStyle(_ style: inout [String: Any]) {
    var sources = style["sources"] as? [String: Any] ?? [:]
    sources[CurrentParticleAnimator.sourceID] = [
        "type": "geojson",
        "data": ["type": "FeatureCollection", "features": [] as [Any]],
    ]
    style["sources"] = sources
    let trail: [String: Any] = [
        "id": CurrentParticleAnimator.trailLayerID, "type": "line",
        "source": CurrentParticleAnimator.sourceID,
        "minzoom": PARTICLE_MIN_ZOOM,
        "filter": ["==", ["geometry-type"], "LineString"],
        "layout": ["line-cap": "round"],
        "paint": ["line-color": PIN_STATE_COLOUR, "line-width": 2.0,
                  "line-opacity": 0.35],
    ]
    let head: [String: Any] = [
        "id": CurrentParticleAnimator.sourceID, "type": "circle",
        "source": CurrentParticleAnimator.sourceID,
        "minzoom": PARTICLE_MIN_ZOOM,
        "filter": ["==", ["geometry-type"], "Point"],
        "paint": ["circle-radius": 1.8, "circle-color": PIN_STATE_COLOUR,
                  "circle-opacity": 0.9],
    ]
    style["layers"] = (style["layers"] as? [[String: Any]] ?? []) + [trail, head]
}

/// Owns the particle state and the animation timer. One instance per
/// `MapStyler`; `attach` re-runs on every style load (fallback, then
/// Seascape) because the source object belongs to the style that loaded it.
final class CurrentParticleAnimator {
    static let sourceID = "gate-particles"
    static let trailLayerID = "gate-particle-trails"

    private struct Gate {
        let record: CurrentStationRecord
        let center: CLLocationCoordinate2D
        /// Fixed per-particle placement: fraction along the axis
        /// (golden-ratio spread) and metres across it (golden-angle scatter).
        /// Deterministic — no RNG, no state to seed.
        let offsets: [(along: Double, across: Double)]
        /// Metres travelled along the flood axis, signed — ebb runs the same
        /// axis backwards. ponytail: real ebbDirection isn't always the exact
        /// reciprocal; a shipping version would swing the axis via
        /// setDegrees(signed:).
        var displacement = 0.0
        var signed = 0.0          // kn, from the on-device fitted model
        var speedStamp = Date.distantPast
    }

    private var gates: [Gate] = []
    private weak var map: MLNMapView?
    /// Strong on purpose: a source looked up out of a JSON-declared style is
    /// a fresh wrapper the style does NOT retain — held weakly it is gone
    /// before the first tick, and the field silently never draws.
    private var source: MLNShapeSource?
    private var timer: Timer?
    private var last = Date()
    private var loggedFirstTick = false

    deinit { timer?.invalidate() }

    /// Post-style-load: find the JSON-declared source, load the fitted gates
    /// (11 tiny model files, once), start the timer. A gate with no
    /// on-device model is simply absent — same honesty as the pins.
    func attach(to style: MLNStyle, map: MLNMapView) {
        self.map = map
        source = style.source(withIdentifier: Self.sourceID) as? MLNShapeSource
        if gates.isEmpty {
            gates = ChsCurrentGateInfo.all.filter { !$0.isOnline }.compactMap { info in
                guard let model = ChsModelStore.loadCurrent(info.id) else { return nil }
                let offsets = (0..<PARTICLES_PER_GATE).map { k in
                    (along: (Double(k) * 0.6180339887).truncatingRemainder(dividingBy: 1),
                     across: sin(Double(k) * 2.3998) * PARTICLE_SPREAD_M)
                }
                return Gate(record: info.record(with: model),
                            center: CLLocationCoordinate2D(latitude: info.latitude,
                                                           longitude: info.longitude),
                            offsets: offsets)
            }
        }
        print("[particles] attach: source=\(source != nil) gates=\(gates.count)")
        guard timer == nil, !gates.isEmpty else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        // .common, or the timer stalls for the whole duration of a pan gesture.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let map, let source else { return }
        let now = Date()
        let dt = min(now.timeIntervalSince(last), 0.5)   // clamp resume jumps
        last = now
        // Below the threshold the layer is hidden anyway — do no work at all.
        guard map.zoomLevel >= PARTICLE_MIN_ZOOM - 0.25 else { return }
        let bounds = map.visibleCoordinateBounds
        // Reduce Motion: the field stays, frozen — state colour still reads.
        let freeze = UIAccessibility.isReduceMotionEnabled
        var features: [MLNShape & MLNFeature] = []
        for i in gates.indices {
            let c = gates[i].center
            guard c.latitude >= bounds.sw.latitude, c.latitude <= bounds.ne.latitude,
                  c.longitude >= bounds.sw.longitude, c.longitude <= bounds.ne.longitude
            else { continue }
            if now.timeIntervalSince(gates[i].speedStamp) > 60 {
                let t = appNow()
                gates[i].signed = gates[i].record.engineStation
                    .speeds(from: t, to: t.addingTimeInterval(1), step: 1).first?.speed ?? 0
                gates[i].speedStamp = now
            }
            if !freeze {
                gates[i].displacement = particleWrap(
                    gates[i].displacement + gates[i].signed * 0.514444 * PARTICLE_SPEED_SCALE * dt,
                    PARTICLE_AXIS_M)
            }
            features += particleFeatures(gates[i])
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
        if !loggedFirstTick {
            loggedFirstTick = true
            print("[particles] first tick: zoom=\(map.zoomLevel) features=\(features.count) "
                + "signed=\(gates.map { String(format: "%.1f", $0.signed) })")
        }
    }

    private func particleFeatures(_ gate: Gate) -> [MLNShape & MLNFeature] {
        let phase = currentPhase(signed: gate.signed)
        let state = phase == .flood ? "flood" : phase == .ebb ? "ebb" : "slack"
        let trailM = abs(gate.signed) * 0.514444 * PARTICLE_SPEED_SCALE * PARTICLE_TRAIL_S
        var shapes: [MLNShape & MLNFeature] = []
        for off in gate.offsets {
            let along = particleWrap(off.along * PARTICLE_AXIS_M + gate.displacement,
                                     PARTICLE_AXIS_M) - PARTICLE_AXIS_M / 2
            let head = particleCoordinate(gate.center,
                                          bearingDeg: gate.record.floodDirection,
                                          alongM: along, acrossM: off.across)
            let f = MLNPointFeature()
            f.coordinate = head
            f.attributes = ["state": state]
            shapes.append(f)
            // Near-slack the tail collapses to nothing — the head alone is
            // the honest render of barely-moving water.
            guard trailM > 1 else { continue }
            let tailAlong = particleTailAlong(along, signed: gate.signed,
                                              trailM: trailM, axisM: PARTICLE_AXIS_M)
            var coords = [particleCoordinate(gate.center,
                                             bearingDeg: gate.record.floodDirection,
                                             alongM: tailAlong, acrossM: off.across),
                          head]
            let line = MLNPolylineFeature(coordinates: &coords, count: 2)
            line.attributes = ["state": state]
            shapes.append(line)
        }
        return shapes
    }
}
