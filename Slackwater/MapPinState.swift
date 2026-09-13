// Slackwater — GPL v3. What colour a station's map pin takes: the tide and
// current tone derivations, and the cache the pin source is built from.
import Foundation
import TideEngine

/// The exact-search fallback's window: 13h clears a diurnal station's ~12.4h
/// half-period, so it always finds the next turn. Only the minority of
/// stations flagged by the cheap check below pay for it.
let PIN_TIDE_FALLBACK_WINDOW: TimeInterval = 13 * 3600

/// Exact direction via the same search `cardState(at:)` uses, just over a
/// shorter (but still turn-guaranteeing) window. nil only if even that comes
/// up empty — draw neutral rather than default "rising" the way the card
/// does; a wrong colour is worse than an admitted grey.
func tidePinRising(_ record: TideStationRecord, at now: Date, window: TimeInterval) -> Bool? {
    let next = record.engineStation.extremes(from: now, to: now.addingTimeInterval(window))
        .first { $0.time > now }
    return next.map { $0.kind == .high }
}

/// The cheap two-sample check's spacing and trust floor. A raw height diff
/// points the wrong way only near a turn (measured: 62/5,700 mismatches, all
/// on small |Δh|), so small diffs fall back to the exact search. The floor is
/// speed-weighted (A·ω, not A — a diurnal wave's peak slope is roughly half a
/// semidiurnal one's); the sweep behind 0.0004 lives in
/// `testHybridDirectionHasFullCoverageAndMatchesBaseline`'s doc comment.
let PIN_TIDE_DIFF_DT: TimeInterval = 30 * 60
let PIN_TIDE_DIFF_THRESHOLD: Double = 0.0004
private let constituentSpeed: [String: Double] = [   // degrees/hour
    "M2": 28.9841, "S2": 30.0, "N2": 28.4397, "K2": 30.0821,
    "K1": 15.0411, "O1": 13.9430, "P1": 14.9589, "Q1": 13.3987,
]

/// Direction for one tide station: cheap almost everywhere, exact always —
/// a two-sample height diff, falling back to `tidePinRising`'s exact search
/// when the diff is under the station's speed-weighted trust floor.
///
/// GOTCHA kept on purpose: the engine's `makeTimeline` snaps to the `step`
/// grid, so the pair is a 30-minute window *straddling* `now` (at 12:29 that
/// is 12:00 and 12:30) — which is what the sweep measured and trusts.
func tidePinRisingHybrid(_ record: TideStationRecord, at now: Date) -> Bool? {
    // A subordinate has no cheap path: its curve is only defined by its
    // extremes, so the exact search is the only search. 2,017 of them cost
    // ~0.26 ms each here (debug) — the pin budget in
    // `testPinLayerBuildsInsideAFrame` was re-based for it.
    if record.isSubordinate { return tidePinRising(record, at: now, window: PIN_TIDE_FALLBACK_WINDOW) }
    let fallback = { tidePinRising(record, at: now, window: PIN_TIDE_FALLBACK_WINDOW) }
    let rangeProxy = record.constituents.reduce(0.0) { $0 + $1.amplitude * (constituentSpeed[$1.name] ?? 0) }
    guard rangeProxy > 0 else { return fallback() }  // no M2/K1-class amplitude — don't divide by it
    let pts = record.engineStation.heights(from: now, to: now.addingTimeInterval(PIN_TIDE_DIFF_DT),
                                           step: PIN_TIDE_DIFF_DT)
    guard pts.count >= 2 else { return fallback() }
    let delta = pts[1].height - pts[0].height
    guard abs(delta) / rangeProxy >= PIN_TIDE_DIFF_THRESHOLD else { return fallback() }
    return delta > 0
}

/// One pin's stateful attributes, resolved together per cache rebuild: the
/// tone the colour expressions read, and the high-zoom readout
/// (`READOUT_MIN_ZOOM`) — a formatted reading under the name, plus, for a
/// speed-bearing current, the bearing its flow arrow rotates to.
struct PinState: Equatable {
    var state: String
    /// "3.2 ft ↑" / "1.8 kn" — formatted at build time with the app's units,
    /// which are part of the cache key for exactly that reason.
    var reading: String?
    /// True bearing the water flows toward — the arrow every current pin
    /// wears, slack included: near slack the sign still names the set, and
    /// the go-green fill is what says "slack".
    var bearing: Double?
    /// Tide gauge fill, bucketed 0...PIN_GAUGE_BUCKETS: where the current
    /// height sits between the surrounding low and high. nil when either
    /// extreme is out of reach — the pin falls back to a dot.
    var gauge: Int?
}

/// The gauge glyph's fill resolution: 0...8 covers ~12% steps, which is all
/// a 10pt bar can show anyway, and keeps the registered image count small.
let PIN_GAUGE_BUCKETS = 8

/// A fitted tide record's pin state. The tone is not `cardState(at:)` — that
/// computes 30h searches the pin discards; the hybrid is the load-bearing
/// shortcut (`testPinLayerBuildsInsideAFrame` budgets the whole source build
/// at 0.3s, and the readout's one extra height sample per pin lives inside
/// the same budget).
func tidePinState(_ record: TideStationRecord, at now: Date, imperial: Bool) -> PinState {
    guard let rising = tidePinRisingHybrid(record, at: now) else { return PinState(state: "unknown") }
    let state = rising ? "rising" : "falling"
    let station = record.engineStation
    guard let height = station
        .heights(from: now, to: now.addingTimeInterval(1), step: 1).first?.height
    else { return PinState(state: state) }
    // The gauge: where the height sits between the surrounding extremes.
    // ±15h brackets any station's cycle. ponytail: a second extremes search
    // per pin on top of the hybrid — if testPinLayerBuildsInsideAFrame
    // blows, derive the range from constituent amplitudes instead.
    let gauge: Int? = {
        let extremes = station.extremes(from: now.addingTimeInterval(-15 * 3600),
                                        to: now.addingTimeInterval(15 * 3600))
        guard let prev = extremes.last(where: { $0.time <= now }),
              let next = extremes.first(where: { $0.time > now }) else { return nil }
        let lo = min(prev.height, next.height), hi = max(prev.height, next.height)
        guard hi - lo > 0.01 else { return nil }
        let f = min(1, max(0, (height - lo) / (hi - lo)))
        return Int((f * Double(PIN_GAUGE_BUCKETS)).rounded())
    }()
    // ↑/↓ ride the label fontstack; offline packs may not cache their glyph
    // range, where the arrow drops and the number stands alone.
    return PinState(state: state,
                    reading: "\(formatHeight(height, imperial: imperial)) \(heightUnit(imperial: imperial)) \(rising ? "↑" : "↓")",
                    gauge: gauge)
}

/// A speed-bearing current pin's state IS a colour (#13): green exactly when
/// the instant sits inside the slack window — |v| under the same
/// `slackThresholdKn` that defines the strip's green column — and the
/// darkened #97 ramp at the current speed otherwise. Hue no longer says
/// flood-versus-ebb here; at readout zooms the flow arrow (and the detail
/// card's arrow + cardinal) carries direction.
func currentPinState(_ station: CurrentStationRecord, at now: Date, speedUnit: String) -> PinState {
    let signed = station.isSubordinate
        ? subordinateCurrentPinSpeed(station, at: now)
        : station.engineStation.speeds(from: now, to: now.addingTimeInterval(1), step: 1).first?.speed ?? 0
    let slack = abs(signed) <= slackThresholdKn
    return PinState(
        state: slack ? mapHex(SN.goHex, darkenedBy: PIN_STATE_DARKEN)
                     : pinRampHex(forSpeedKn: abs(signed)),
        reading: "\(formatSpeed(abs(signed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
        bearing: station.setDegrees(signed: signed))
}

/// 1,549 subordinate current pins hang off 50 references, so the reference is
/// searched once per build and each pin only reduces — the engine's own
/// `reduce` and `speed(at:along:)`, so the math has one owner. The engine
/// extracts reference events per UTC day (`eventsByDay`), so the held list
/// and the one the detail view's `speeds` searches are the same events, and
/// the pin's colour is the detail's speed at that instant.
private func subordinateCurrentPinSpeed(_ station: CurrentStationRecord, at now: Date) -> Double {
    guard let ref = station.referenceRecord,
          case let sub as SubordinateStation = station.engineStation else { return 0 }
    return SubordinateStation.speed(at: now, along: sub.reduce(ReferenceCurrentEvents.shared.events(of: ref, at: now)))
}

/// Lock-protected like `PinFeaturesCache`, and keyed on its 30-minute bucket,
/// because a style build asks for each pin with its own `appNow()`.
final class ReferenceCurrentEvents: @unchecked Sendable {
    static let shared = ReferenceCurrentEvents()
    /// 8 h brackets any current's window (the engine's own pad) and 9 h clears
    /// the largest subordinate offset.
    private static let pad: TimeInterval = 17 * 3600
    private let lock = NSLock()
    private var bucket = Int.min
    private var events: [String: [CurrentEvent]] = [:]

    func events(of reference: CurrentStationRecord, at now: Date) -> [CurrentEvent] {
        lock.lock(); defer { lock.unlock() }
        let b = Int(now.timeIntervalSince1970 / PIN_TIDE_DIFF_DT)
        if b != bucket { bucket = b; events = [:] }
        if let cached = events[reference.id] { return cached }
        let start = Date(timeIntervalSince1970: Double(b) * PIN_TIDE_DIFF_DT)
        let found = reference.harmonicStation.eventsByDay(from: start.addingTimeInterval(-Self.pad),
                                                          to: start.addingTimeInterval(PIN_TIDE_DIFF_DT + Self.pad))
        events[reference.id] = found
        return found
    }
}

/// The units the readouts format with — read where the features build, and
/// part of the cache key so a settings change doesn't serve stale strings.
private func readoutUnits() -> (imperial: Bool, speedUnit: String) {
    ((AppGroup.defaults.string(forKey: unitsKey) ?? "imperial") == "imperial",
     AppGroup.defaults.string(forKey: speedUnitKey) ?? "kn")
}

/// A station's pin state (tone + readout).
///
/// Synchronous only: every CHS-provenance item resolves through
/// `ChsFitService`'s async fit cache, so at style-build time all three read
/// from `chsStates` — what `chsPinStates` resolved from what the offline
/// sync has already stored, pushed in after paint (`MapStyler.applyChsStates`).
/// Absent means unsynced, and the pin honestly draws neutral.
private func pinState(_ item: StationItem, at now: Date, chsStates: [String: PinState],
                      imperial: Bool, speedUnit: String) -> PinState {
    switch item {
    // The map is not the first frame, so resolving both records here is
    // fair game — a state is a prediction and needs the constituents (#317).
    case .tide(let info):
        return info.tideRecord.map { tidePinState($0, at: now, imperial: imperial) }
            ?? PinState(state: "unknown")
    case .current(let info):
        return info.currentRecord.map { currentPinState($0, at: now, speedUnit: speedUnit) }
            ?? PinState(state: "unknown")
    case .chs, .chsGate, .chsCurrent:
        return chsStates[item.id] ?? PinState(state: "unknown")
    }
}

/// CHS states from what the offline sync has ALREADY stored. The caller hands
/// in the fitted records as plain dictionaries, so this cannot fetch — a
/// station the sync has not reached is simply absent and stays neutral
/// (issue #12; the web port learned the fetch-on-open version is a request
/// storm against IWLS). A derived gate has no model of its own: it resolves
/// exactly when its reference port — itself a CHS port — is fitted, and it
/// carries no readout: no speed exists to show (ChsGate.swift), and its
/// water height belongs to the port, not the pass.
func chsPinStates(at now: Date,
                  tideRecords: [String: TideStationRecord],
                  currentRecords: [String: CurrentStationRecord]) -> [String: PinState] {
    let units = readoutUnits()
    var states: [String: PinState] = [:]
    for item in StationItem.all {
        switch item {
        case .tide, .current:
            continue
        case .chs(let info):
            guard let record = tideRecords[info.id] else { continue }
            states[item.id] = tidePinState(record, at: now, imperial: units.imperial)
        case .chsCurrent(let gate):
            guard let record = currentRecords[gate.id] else { continue }
            states[item.id] = currentPinState(record, at: now, speedUnit: units.speedUnit)
        case .chsGate(let gate):
            guard let port = tideRecords[gate.reference] else { continue }
            let phase = DerivedGateRecord(gate: gate, port: port).cardState(at: now).phase
            states[item.id] = PinState(state: phase == .flood ? "flood" : phase == .ebb ? "ebb" : "slack")
        }
    }
    return states
}

/// Every bundled station as a GeoJSON pin: identity, tone, and the
/// high-zoom readout attributes when the state resolved one.
private func pinFeatures(chsStates: [String: PinState] = [:]) -> [String: Any] {
    let units = readoutUnits()
    return [
        "type": "FeatureCollection",
        "features": StationItem.all.map { s in
            let state = pinState(s, at: appNow(), chsStates: chsStates,
                                 imperial: units.imperial, speedUnit: units.speedUnit)
            var properties: [String: Any] = ["id": s.id, "name": s.name, "kind": s.pinKind,
                                             "state": state.state]
            if let reading = state.reading { properties["reading"] = reading }
            if let bearing = state.bearing { properties["bearing"] = bearing }
            // The full image name, not the bucket — `icon-image` reads it
            // straight off the feature, no string building in the style.
            if let gauge = state.gauge { properties["gauge"] = "pin-gauge-\(gauge)" }
            return [
                "type": "Feature",
                "geometry": ["type": "Point", "coordinates": [s.longitude, s.latitude]],
                "properties": properties,
            ] as [String: Any]
        },
    ]
}

/// Caches `pinFeatures`' output across `MapStyler` instantiations.
///
/// `StationListView.mapPane` remounts `MapViewRepresentable` via
/// `.id(mapFocusToken)` on every pin focus, so without this cache
/// `MapStyler.init` rebuilds the whole world bundle's tide/current tones from
/// scratch on every single tap — the ~0.5s `testPinLayerBuildsInsideAFrame`
/// measures, paid again and again in one map session, not once per session.
///
/// Keyed on the inputs that actually change the answer: `chsStates` (busts
/// the instant a real dict arrives via `update`, called from
/// `MapStyler.applyChsStates` after a CHS fit lands — a stale CHS tone would
/// be a worse bug than the rebuild cost this exists to avoid), the readout
/// units, and a 30-minute time bucket, `PIN_TIDE_DIFF_DT` — the same resolution
/// `tidePinRisingHybrid`'s own hybrid check already uses, so rebuilding more
/// often than that buys nothing and rebuilding less often would show a tide
/// pin that never turns. The readouts inherit that bucket, so a displayed
/// height can lag the curve by up to half an hour — the trend arrow stays
/// honest, the number is "recently". ponytail: 30-minute readings; shrink
/// the bucket (or split readings from tones) if that lag ever reads as a
/// wrong number rather than an old one.
///
/// Internal, not `private`, and its cache is lock-protected rather than
/// actor-isolated: `stationSource()` runs on whatever thread builds a style,
/// and `applyChsStates` writes from its own
/// detached task, so real cross-thread access exists; a lock around a few
/// dictionary reads is the smaller fix than moving every caller onto an
/// actor. Internal (not private) so `NationalScaleTests` can exercise the
/// cache/invalidate contract directly and reset it between measurements.
final class PinFeaturesCache: @unchecked Sendable {
    static let shared = PinFeaturesCache()
    private let lock = NSLock()
    private var bucket: Int?
    private var slackThreshold: Double?
    private var units: String?
    private var states: [String: PinState] = [:]
    private var geojson: [String: Any] = [:]

    private func currentBucket(_ now: Date) -> Int { Int(now.timeIntervalSince1970 / PIN_TIDE_DIFF_DT) }

    /// What a style build should source its pins from: whatever's cached,
    /// rebuilt only when the time bucket has moved. Serves the last-known
    /// `chsStates` (not blank) so a remount reuses whatever `update` last
    /// resolved instead of flashing every CHS pin back to "unknown".
    func snapshot(now: Date = appNow()) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return rebuilt(states, now)  // re-pushing what's cached IS "keep what we have"
    }

    /// `applyChsStates`'s entry point: the real, resolved CHS states. Rebuilds
    /// when they differ from what's cached, or the time bucket moved — a
    /// same-value push (a style reload that synced nothing new) is a no-op.
    @discardableResult
    func update(states newStates: [String: PinState], now: Date = appNow()) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return rebuilt(newStates, now)
    }

    /// The one cache rule both entry points share. CALLER HOLDS `lock` —
    /// `NSLock` is not recursive, so this must never be called from outside
    /// one of the two methods above.
    private func rebuilt(_ newStates: [String: PinState], _ now: Date) -> [String: Any] {
        let b = currentBucket(now)
        let threshold = slackThresholdKn
        let u = readoutUnits()
        let signature = "\(u.imperial)-\(u.speedUnit)"
        if states != newStates || bucket != b || slackThreshold != threshold
            || units != signature || geojson.isEmpty {
            states = newStates
            geojson = pinFeatures(chsStates: newStates)
            bucket = b
            slackThreshold = threshold
            units = signature
        }
        return geojson
    }

    /// Test-only: forces the next `snapshot`/`update` to rebuild from
    /// scratch. Without this, whichever test happens to touch the (process-
    /// lifetime) shared cache first "warms" it for every test after —
    /// including `testPinLayerBuildsInsideAFrame`, which needs a genuinely
    /// cold build or it stops measuring the cost it exists to catch.
    func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        bucket = nil
        slackThreshold = nil
        units = nil
        states = [:]
        geojson = [:]
    }
}
