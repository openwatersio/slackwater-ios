// Slackwater — GPL v3. What a station's map pin says: the tide and current
// state derivations, and the VISIBLE SET the pin source is built from — the
// stations inside the camera's box, thinned to one per grid cell, so the
// app predicts water for what is on screen and nothing else.
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
    /// "3.2 ft" / "1.8 kn" — formatted at build time with the app's units,
    /// so a unit change has to rebuild the source (`MapStyler.refreshPins`
    /// watches for it) rather than restyle it.
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
/// `detailed` is the zoom's answer to "is a gauge or a reading drawn here":
/// below `LABEL_MIN_ZOOM` neither is, so the height sample and the extremes
/// search behind them are skipped outright — not narrowed, not cached, just
/// not computed. Only the direction (the pin's colour) is always needed.
func tidePinState(_ record: TideStationRecord, at now: Date,
                  imperial: Bool, detailed: Bool) -> PinState {
    guard let rising = tidePinRisingHybrid(record, at: now) else {
        return PinState(state: "unknown")
    }
    let state = rising ? "rising" : "falling"
    let station = record.engineStation
    guard detailed, let height = station
        .heights(from: now, to: now.addingTimeInterval(1), step: 1).first?.height
    else { return PinState(state: state) }
    // The gauge: where the height sits between the surrounding extremes.
    // ±15h brackets any station's cycle.
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
    // No trend arrow in the text — the gauge's caret carries it.
    return PinState(state: state,
                    reading: "\(formatHeight(height, imperial: imperial)) \(heightUnit(imperial: imperial))",
                    gauge: gauge)
}

/// The thinning rank, from IDENTITY alone — no engine call, because
/// decimation has to choose which stations are worth computing before any
/// state exists. Reference/harmonic stations before subordinates, bigger
/// signals before smaller within each; "the mouth before upstream" falls
/// out of that, because upstream stations are the subordinates pointing
/// their offsets at the mouth. One rank step outweighs any signal
/// difference: harmonics land in 0...9, subordinates in 10...19.
func pinSortRank(_ item: StationItem) -> Double {
    func rank(_ subordinate: Bool, _ signal: Double) -> Double {
        (subordinate ? 10 : 0) + max(0, 9 - signal)
    }
    switch item {
    case .tide(let info):
        guard let r = info.tideRecord else { return 25 }
        return rank(r.isSubordinate, r.constituents.reduce(0) { $0 + $1.amplitude })
    case .current(let info):
        guard let r = info.currentRecord else { return 25 }
        return rank(r.isSubordinate, r.constituents.reduce(abs(r.meanFlow)) { $0 + $1.amplitude })
    // A CHS port or gate ships identity only until it is fitted, so there is
    // no signal to rank by — they sit mid-table, ahead of the unknown
    // default. A derived gate is real but speed-less: last of the ranked.
    case .chs, .chsCurrent: return 5
    case .chsGate: return 19
    }
}

/// A speed-bearing current pin's state IS a colour (#13): green exactly when
/// the instant sits inside the slack window — |v| under the same
/// `slackThresholdKn` that defines the strip's green column — and the
/// darkened #97 ramp at the current speed otherwise. Hue no longer says
/// flood-versus-ebb here; at readout zooms the flow arrow (and the detail
/// card's arrow + cardinal) carries direction.
func currentPinState(_ station: CurrentStationRecord, at now: Date,
                     speedUnit: String, detailed: Bool = true) -> PinState {
    let signed = station.isSubordinate
        ? subordinateCurrentPinSpeed(station, at: now)
        : station.engineStation.speeds(from: now, to: now.addingTimeInterval(1), step: 1).first?.speed ?? 0
    let slack = abs(signed) <= slackThresholdKn
    return PinState(
        state: slack ? mapHex(SN.goHex, darkenedBy: PIN_STATE_DARKEN)
                     : pinRampHex(forSpeedKn: abs(signed)),
        reading: detailed ? "\(formatSpeed(abs(signed), unit: speedUnit)) \(speedUnitLabel(speedUnit))" : nil,
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

/// Keyed on a 30-minute bucket, because one build asks for every subordinate
/// off the same reference with its own `appNow()`.
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
/// The units as one comparable token, for callers deciding whether a built
/// source's readings are still in the right unit.
func readoutUnitSignature() -> String {
    let u = readoutUnits()
    return "\(u.imperial)-\(u.speedUnit)"
}

private func readoutUnits() -> (imperial: Bool, speedUnit: String) {
    ((AppGroup.defaults.string(forKey: unitsKey) ?? "imperial") == "imperial",
     AppGroup.defaults.string(forKey: speedUnitKey) ?? "kn")
}

/// A station's pin state (tone + readout).
///
/// Synchronous only: every CHS-provenance item resolves through
/// `ChsFitService`'s async fit cache, so at style-build time all three read
/// from `chsStates` — what `chsPinStates` resolved from what the offline
/// sync has already stored, resolved alongside the visible set
/// (`MapStyler.refreshPins`).
/// Absent means unsynced, and the pin honestly draws neutral.
private func pinState(_ item: StationItem, at now: Date, chsStates: [String: PinState],
                      imperial: Bool, speedUnit: String, detailed: Bool) -> PinState {
    switch item {
    // The map is not the first frame, so resolving both records here is
    // fair game — a state is a prediction and needs the constituents (#317).
    case .tide(let info):
        return info.tideRecord.map { tidePinState($0, at: now, imperial: imperial, detailed: detailed) }
            ?? PinState(state: "unknown")
    case .current(let info):
        return info.currentRecord.map {
            currentPinState($0, at: now, speedUnit: speedUnit, detailed: detailed)
        } ?? PinState(state: "unknown")
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
/// Scoped to the visible set for the same reason everything else is: a
/// Canadian port the camera is nowhere near has no pin to colour.
func chsPinStates(at now: Date, items: [StationItem], detailed: Bool,
                  tideRecords: [String: TideStationRecord],
                  currentRecords: [String: CurrentStationRecord]) -> [String: PinState] {
    let units = readoutUnits()
    var states: [String: PinState] = [:]
    for item in items {
        switch item {
        case .tide, .current:
            continue
        case .chs(let info):
            guard let record = tideRecords[info.id] else { continue }
            states[item.id] = tidePinState(record, at: now, imperial: units.imperial,
                                           detailed: detailed)
        case .chsCurrent(let gate):
            guard let record = currentRecords[gate.id] else { continue }
            states[item.id] = currentPinState(record, at: now, speedUnit: units.speedUnit,
                                              detailed: detailed)
        case .chsGate(let gate):
            guard let port = tideRecords[gate.reference] else { continue }
            let phase = DerivedGateRecord(gate: gate, port: port).cardState(at: now).phase
            states[item.id] = PinState(state: phase == .flood ? "flood" : phase == .ebb ? "ebb" : "slack")
        }
    }
    return states
}

/// The camera's own box, so the visible-set math stays testable without a
/// MapLibre view. `west > east` means the box wraps the antimeridian.
struct PinBox: Equatable {
    var south, west, north, east: Double

    func contains(lat: Double, lon: Double) -> Bool {
        guard lat >= south, lat <= north else { return false }
        return west <= east ? (lon >= west && lon <= east) : (lon >= west || lon <= east)
    }

    /// Longitude span, always positive, wrapping the antimeridian.
    var lonSpan: Double { east - west < 0 ? east - west + 360 : east - west }

    /// Grown by `fraction` of its own span on every side — the slack that
    /// lets a small pan reuse the set already built. Longitudes rewrap into
    /// -180...180, so a box growing across the dateline stays a box the
    /// `contains` test can answer (21 stations sit beyond |178°|, and
    /// `ChartPacks.stationSpecs` splits its packs there for the same
    /// reason).
    func padded(by fraction: Double) -> PinBox {
        let dLat = (north - south) * fraction
        let dLon = lonSpan * fraction
        // A pad that swallows the globe has no seam left to wrap around.
        guard lonSpan + dLon * 2 < 360 else {
            return PinBox(south: max(-90, south - dLat), west: -180,
                          north: min(90, north + dLat), east: 180)
        }
        return PinBox(south: max(-90, south - dLat), west: PinBox.wrap(west - dLon),
                      north: min(90, north + dLat), east: PinBox.wrap(east + dLon))
    }

    static func wrap(_ lon: Double) -> Double {
        var l = lon.truncatingRemainder(dividingBy: 360)
        if l > 180 { l -= 360 }
        if l < -180 { l += 360 }
        return l
    }

    /// True when this box already holds everything `inner` needs. Tests the
    /// spans rather than two corners: a wrapped box's corners can both be
    /// inside while the middle is not.
    func covers(_ inner: PinBox) -> Bool {
        guard inner.south >= south, inner.north <= north else { return false }
        guard lonSpan >= inner.lonSpan else { return false }
        return contains(lat: inner.south, lon: inner.west)
            && contains(lat: inner.south, lon: inner.east)
    }
}

/// The decimation grid's cell, in points — a touch target. One station
/// survives per cell, so the pin work is bounded by SCREEN AREA (a phone
/// holds a couple of hundred cells) rather than by how much world the camera
/// happens to cover. At the detail zooms the cells are small enough that
/// nearly every station survives anyway.
let PIN_CELL_POINTS = 44.0
/// How far past the viewport to build, as a fraction of its span.
let PIN_VIEWPORT_PAD = 0.5
/// Zoom drift tolerated before a rebuild: decimation cells scale with zoom,
/// so a real zoom change means a different set of survivors.
let PIN_ZOOM_SLACK = 0.5
/// How often a mounted map re-resolves state for the set it already has.
/// The states themselves only move on `PIN_TIDE_DIFF_DT` boundaries, but a
/// viewport build is cheap enough now that the tick can be honest about the
/// clock rather than clever about buckets.
let PIN_REFRESH_S: TimeInterval = 60

/// The stations a camera actually needs: inside the box, then thinned to the
/// best-ranked one per grid cell.
///
/// This is where the map stopped computing the planet. Thinning here rather
/// than in the collision engine also makes the choice deterministic — the
/// highest-ranked station in a patch of water wins every time, instead of
/// whichever symbol the placer happened to reach first.
/// A station reduced to what decimation needs — coordinates and rank, with
/// neither re-derived per camera move. Both are fixed for the life of the
/// process; the rank in particular costs a record lookup and a constituent
/// sum, which has no business running on every pan.
struct PinCandidate {
    let lat: Double, lon: Double, rank: Double
    let item: StationItem
}

func pinCandidates(_ items: [StationItem]) -> [PinCandidate] {
    items.map { PinCandidate(lat: $0.latitude, lon: $0.longitude, rank: pinSortRank($0), item: $0) }
}

/// Built once, on first use, off the main thread (the first build already
/// runs in a detached task).
let allPinCandidates: [PinCandidate] = pinCandidates(StationItem.all)

/// `pinned` always survives, whatever its cell holds: the station a detail
/// page is about must appear on that page's own map, and the pin a preview
/// panel is describing must not vanish under the panel.
/// `decimate: false` keeps every station in the box — a detail page's
/// Nearby map lists its stations as rows directly above itself, so thinning
/// them would draw fewer pins than the list claims, and the ones dropped
/// would be the NEAREST (the frame's zoom is set by the farthest station,
/// which makes the cells coarse). That set is already bounded by the
/// nearby radius, so there is nothing to bound.
func visibleStations(in box: PinBox, zoom: Double,
                     candidates: [PinCandidate] = allPinCandidates,
                     pinned: String? = nil, decimate: Bool = true) -> [StationItem] {
    // Web-mercator degrees per point at this zoom (MapLibre's tile size is
    // 512). Latitude cells shrink with the mercator scale so a cell stays
    // square on screen at any latitude.
    let degPerPoint = 360 / (512 * pow(2, zoom))
    let cellLon = PIN_CELL_POINTS * degPerPoint
    let midLat = (box.south + box.north) / 2
    let cellLat = max(cellLon * cos(midLat * .pi / 180), 1e-9)
    guard decimate else {
        let kept = candidates.filter { box.contains(lat: $0.lat, lon: $0.lon) }.map(\.item)
        return kept
    }
    var best: [Int64: PinCandidate] = [:]
    best.reserveCapacity(256)
    for c in candidates where box.contains(lat: c.lat, lon: c.lon) {
        let cell = Int64((c.lon / cellLon).rounded(.down)) &* 1_000_003
            &+ Int64((c.lat / cellLat).rounded(.down))
        if let held = best[cell], held.rank <= c.rank { continue }
        best[cell] = c
    }
    var kept = best.values.map(\.item)
    if let pinned, !kept.contains(where: { $0.id == pinned }),
       let item = StationItem.byId[pinned] {
        kept.append(item)
    }
    return kept
}

/// The visible set as GeoJSON: identity, tone, and — only where the zoom
/// draws them — the gauge and readout attributes.
/// `selectedID` marks the picked pin, which the style reads to scale the
/// symbol up and repaint its plate as a translucent halo — selection is a
/// property of the symbol rather than a ring drawn beneath it.
func pinFeatures(for items: [StationItem], zoom: Double,
                 chsStates: [String: PinState] = [:], now: Date = appNow(),
                 selectedID: String? = nil) -> [String: Any] {
    let units = readoutUnits()
    let detailed = zoom >= LABEL_MIN_ZOOM
    return [
        "type": "FeatureCollection",
        "features": items.map { s in
            let state = pinState(s, at: now, chsStates: chsStates, imperial: units.imperial,
                                 speedUnit: units.speedUnit, detailed: detailed)
            var properties: [String: Any] = ["id": s.id, "name": s.name, "kind": s.pinKind,
                                             "state": state.state, "sort": pinSortRank(s)]
            if let reading = state.reading { properties["reading"] = reading }
            if let bearing = state.bearing { properties["bearing"] = bearing }
            // The full image name, not the bucket — `icon-image` reads it
            // straight off the feature, no string building in the style.
            // The trend rides the name too: each variant bakes its caret.
            if s.id == selectedID { properties["selected"] = true }
            if let gauge = state.gauge {
                properties["gauge"] = "pin-gauge-\(gauge)-\(state.state == "rising" ? "up" : "down")"
            }
            return [
                "type": "Feature",
                "geometry": ["type": "Point", "coordinates": [s.longitude, s.latitude]],
                "properties": properties,
            ] as [String: Any]
        },
    ]
}
