// Slackwater — GPL v3. What colour a station's map pin takes: the tide and
// current tone derivations, and the cache the pin source is built from.
import Foundation

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

/// A fitted tide record's tone. Not `cardState(at:)` — that computes 30h
/// searches the pin discards; the hybrid is the load-bearing shortcut
/// (`testPinLayerBuildsInsideAFrame` budgets the whole source build at 0.3s).
func tidePinTone(_ record: TideStationRecord, at now: Date) -> String {
    guard let rising = tidePinRisingHybrid(record, at: now) else { return "unknown" }
    return rising ? "rising" : "falling"
}

/// A speed-bearing current pin's tone IS its colour (#13): green exactly when
/// the instant sits inside the slack window — |v| under the same
/// `slackThresholdKn` that defines the strip's green column — and the
/// darkened #97 ramp at the current speed otherwise. Hue no longer says
/// flood-versus-ebb here; the detail card's arrow + cardinal carries
/// direction (#97's own argument for taking it off hue).
func currentPinColour(_ station: CurrentStationRecord, at now: Date) -> String {
    let signed = station.engineStation.speeds(from: now, to: now.addingTimeInterval(1), step: 1)
        .first?.speed ?? 0
    return abs(signed) <= slackThresholdKn
        ? mapHex(SN.goHex, darkenedBy: PIN_STATE_DARKEN)
        : pinRampHex(forSpeedKn: abs(signed))
}

/// A station's state as a tone name, for the pin's colour.
///
/// Synchronous only: every CHS-provenance item resolves through
/// `ChsFitService`'s async fit cache, so at style-build time all three read
/// from `chsTones` — the tones `chsPinTones` resolved from what the offline
/// sync has already stored, pushed in after paint (`MapStyler.applyChsTones`).
/// Absent means unsynced, and the pin honestly draws neutral.
private func pinTone(_ item: StationItem, at now: Date, chsTones: [String: String]) -> String {
    switch item {
    case .tide(let record):
        return tidePinTone(record, at: now)
    case .current(let station):
        return currentPinColour(station, at: now)
    case .chs, .chsGate, .chsCurrent:
        return chsTones[item.id] ?? "unknown"
    }
}

/// CHS tones from what the offline sync has ALREADY stored. The caller hands
/// in the fitted records as plain dictionaries, so this cannot fetch — a
/// station the sync has not reached is simply absent and stays neutral
/// (issue #12; the web port learned the fetch-on-open version is a request
/// storm against IWLS). A derived gate has no model of its own: it resolves
/// exactly when its reference port — itself a CHS port — is fitted.
func chsPinTones(at now: Date,
                 tideRecords: [String: TideStationRecord],
                 currentRecords: [String: CurrentStationRecord]) -> [String: String] {
    var tones: [String: String] = [:]
    for item in StationItem.all {
        switch item {
        case .tide, .current:
            continue
        case .chs(let info):
            guard let record = tideRecords[info.id] else { continue }
            tones[item.id] = tidePinTone(record, at: now)
        case .chsCurrent(let gate):
            guard let record = currentRecords[gate.id] else { continue }
            tones[item.id] = currentPinColour(record, at: now)
        case .chsGate(let gate):
            guard let port = tideRecords[gate.reference] else { continue }
            let phase = DerivedGateRecord(gate: gate, port: port).cardState(at: now).phase
            tones[item.id] = phase == .flood ? "flood" : phase == .ebb ? "ebb" : "slack"
        }
    }
    return tones
}

/// Every bundled station as a GeoJSON pin. Identity only — no readings.
private func pinFeatures(chsTones: [String: String] = [:]) -> [String: Any] {
    [
        "type": "FeatureCollection",
        "features": StationItem.all.map { s in
            [
                "type": "Feature",
                "geometry": ["type": "Point", "coordinates": [s.longitude, s.latitude]],
                "properties": ["id": s.id, "name": s.name, "kind": s.pinKind,
                               "state": pinTone(s, at: appNow(), chsTones: chsTones)],
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
/// Keyed on the inputs that actually change the answer: `chsTones` (busts
/// the instant a real dict arrives via `update`, called from
/// `MapStyler.applyChsTones` after a CHS fit lands — a stale CHS tone would
/// be a worse bug than the rebuild cost this exists to avoid) and a 30-minute
/// time bucket, `PIN_TIDE_DIFF_DT` — the same resolution
/// `tidePinRisingHybrid`'s own hybrid check already uses, so rebuilding more
/// often than that buys nothing and rebuilding less often would show a tide
/// pin that never turns.
///
/// Internal, not `private`, and its cache is lock-protected rather than
/// actor-isolated: `stationSource()` runs on whatever thread builds a style,
/// and `applyChsTones` writes from its own
/// detached task, so real cross-thread access exists; a lock around a few
/// dictionary reads is the smaller fix than moving every caller onto an
/// actor. Internal (not private) so `NationalScaleTests` can exercise the
/// cache/invalidate contract directly and reset it between measurements.
final class PinFeaturesCache: @unchecked Sendable {
    static let shared = PinFeaturesCache()
    private let lock = NSLock()
    private var bucket: Int?
    private var slackThreshold: Double?
    private var tones: [String: String] = [:]
    private var geojson: [String: Any] = [:]

    private func currentBucket(_ now: Date) -> Int { Int(now.timeIntervalSince1970 / PIN_TIDE_DIFF_DT) }

    /// What a style build should source its pins from: whatever's cached,
    /// rebuilt only when the time bucket has moved. Serves the last-known
    /// `chsTones` (not blank) so a remount reuses whatever `update` last
    /// resolved instead of flashing every CHS pin back to "unknown".
    func snapshot(now: Date = appNow()) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return rebuilt(tones, now)  // re-pushing what's cached IS "keep what we have"
    }

    /// `applyChsTones`'s entry point: the real, resolved CHS tones. Rebuilds
    /// when they differ from what's cached, or the time bucket moved — a
    /// same-value push (a style reload that synced nothing new) is a no-op.
    @discardableResult
    func update(tones newTones: [String: String], now: Date = appNow()) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return rebuilt(newTones, now)
    }

    /// The one cache rule both entry points share. CALLER HOLDS `lock` —
    /// `NSLock` is not recursive, so this must never be called from outside
    /// one of the two methods above.
    private func rebuilt(_ newTones: [String: String], _ now: Date) -> [String: Any] {
        let b = currentBucket(now)
        let threshold = slackThresholdKn
        if tones != newTones || bucket != b || slackThreshold != threshold || geojson.isEmpty {
            tones = newTones
            geojson = pinFeatures(chsTones: newTones)
            bucket = b
            slackThreshold = threshold
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
        tones = [:]
        geojson = [:]
    }
}
