// Slackwater — GPL v3. M4 simple pin map, mirroring slackwater-web
// (MapScreen.tsx + mapStyle.ts): the bundled OSM land-polygons PMTiles under
// everything (offline floor), Seascape's style composed in when it can be
// fetched, every bundled station as a pin, tap → detail. MapLibre Native
// reads the same land.pmtiles artifact the web serves, via its built-in
// pmtiles:// support — one artifact, two renderers.
import SwiftUI
import MapLibre

// Discovery-map camera: frames the bundled-station core (Puget Sound through
// the Gulf Islands / Strait of Georgia) so it opens reading as the Salish Sea.
// The UI pin-tap test derives screen points from these same constants.
let SALISH_CENTER = CLLocationCoordinate2D(latitude: 48.35, longitude: -123.05)
let SALISH_ZOOM = 7.35

/// UI-test hook, like `-openMap`: `-mapZoom 3.2` (UserDefaults argument
/// domain) opens the discovery map at a stated zoom. Synthesised pinches are
/// not a camera — five of them land somewhere the test cannot name. Zoom 0
/// (whole earth) is never a real request, so it doubles as "unset".
let discoveryZoom: Double = {
    let zoom = UserDefaults.standard.double(forKey: "mapZoom")
    return zoom == 0 ? SALISH_ZOOM : zoom
}()

/// `-mapCenter 48.86,-123.31` (UserDefaults argument domain): opens the
/// discovery map centered there — same reasoning as `-mapZoom`, added for the
/// #57 spike recording, which has to frame a named gate deterministically.
let mapCenterOverride: CLLocationCoordinate2D? = {
    let parts = (UserDefaults.standard.string(forKey: "mapCenter") ?? "").split(separator: ",")
    guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
}()

// The MapScreen full-screen-cover wrapper (header + X) is gone — M4.5 shows
// the map in place behind the list ⇄ map toggle FAB (StationListView.mapPane).

// MARK: - Style building (mirrors web mapStyle.ts)

private let LAND_TONE = "#f5ecd7"   // paper-chart cream
/// Seascape's own `background-color` — the flat tone its depth ramp settles
/// to past 50 m, not a hand-picked blue.
private let WATER_TONE = "#e9f7ff"
/// Pin fills fail WCAG's 3:1 on pale water, so the contrast lives on the
/// stroke — every pin carries this ink outline (asserted in
/// `testEveryPinOutlineClearsTheContrastFloorOnBothGrounds`).
private let CHART_INK = "#0b1a2b"
// A pin's COLOUR is the water's state, never the station's kind — kind is the
// pin's SHAPE: circle for current, square for tide. `chs` is provenance, not
// kind — it draws the same square a NOAA tide station does.
/// MapLibre style dicts hold strings, so the palette crosses over as
/// "#rrggbb" — always derived from the `SN` hex, never hand-copied (a copy is
/// silent drift no test catches).
func mapHex(_ hex: UInt32) -> String { String(format: "#%06x", hex) }

/// Map-only darker variants of the three state colours (issue #13): the raw
/// tokens fall below WCAG 1.4.11's 3:1 over the cream land polygons (flood
/// 2.47, ebb 1.83, go 1.96), washing the fill out exactly where a pin sits
/// on land. Derived from the `SN` hexes by one factor — the blend-toward-
/// black mirror of `Color.hex(_:lightenedBy:)` — never hand-picked:
/// hand-picked variants are how the chart labels ended up inverted. 0.28 is
/// the smallest even step that puts the worst state (ebb, 3.4:1) over the
/// floor with margin while keeping the three hues apart; the floor is pinned
/// by `testEveryPinStateFillClearsTheContrastFloorOnLand`. `SN.steel`
/// already clears it (3.25:1) and stays undarkened, token-equal to the card
/// glyph's unknown.
let PIN_STATE_DARKEN = 0.28
func mapHex(_ hex: UInt32, darkenedBy t: Double) -> String {
    let d = { (c: UInt32) -> UInt32 in UInt32((Double(c) * (1 - t)).rounded()) }
    return mapHex(d((hex >> 16) & 0xFF) << 16 | d((hex >> 8) & 0xFF) << 8 | d(hex & 0xFF))
}

/// The unknown-state pin: `SN.steel`, the same token the card glyph draws for
/// `.unknown` — one meaning, one value.
let PIN_NEUTRAL = mapHex(SN.steelHex)
// The circle radius and the square's equal-area radius share this constant so
// the two literals cannot drift apart again.
private let PIN_RADIUS: Double = 5
/// One outline width for both pin kinds — the circle's `circle-stroke-width`
/// and the square's `icon-halo-width`, which is also the transparent margin
/// `squarePinImage` has to leave for that halo to have anywhere to draw. Three
/// literals that must agree or the two kinds stop reading as one system.
private let PIN_HALO: Double = 1.5

// A pin's colour by state — literally the same expression on both pin layers
// (Task 5), so kind (which layer a pin lands in) cannot influence colour.
//
// #13: a speed-bearing current pin's state IS a colour literal — the #97 ramp
// darkened for land contrast, or go inside the slack window — which the
// to-color head renders as itself. Named states (tide rising/falling, and
// flood/ebb/slack for the one speed-less kind, derived gates — "No speed
// exists to show", ChsGate.swift) fall through to the match. Anything else
// is neutral.
let PIN_STATE_COLOUR: [Any] = [
    "to-color", ["get", "state"],
    ["match", ["get", "state"],
     "rising", mapHex(SN.floodHex, darkenedBy: PIN_STATE_DARKEN),
     "flood", mapHex(SN.floodHex, darkenedBy: PIN_STATE_DARKEN),
     "falling", mapHex(SN.ebbHex, darkenedBy: PIN_STATE_DARKEN),
     "ebb", mapHex(SN.ebbHex, darkenedBy: PIN_STATE_DARKEN),
     "slack", mapHex(SN.goHex, darkenedBy: PIN_STATE_DARKEN),
     PIN_NEUTRAL] as [Any],   // unknown — SN.steel, already 3.25:1 on land
]

/// The pin ramp's own land-contrast factor. Deeper than the named states'
/// `PIN_STATE_DARKEN` (0.28) because the ramp's top end is the palest colour
/// any pin can take — at 0.28 it bottoms out at 2.55:1 on the land tone;
/// 0.36 clears the 3:1 floor across the whole sweep with margin (worst
/// 3.16:1, measured), pinned by `testPinRampClearsContrastAndNeverGreen`.
/// Uniform, not speed-dependent: inferno's monotone luminance is what lets
/// the ramp rank speeds at a glance, and a nonuniform darken would bend it.
let PIN_RAMP_DARKEN = 0.36

/// The map's ramp fill for a speed-bearing current pin: the #97 transfer
/// (the strip's own composition) under the pin ramp's land-contrast darken.
func pinRampHex(forSpeedKn kn: Double) -> String {
    let c = SN.speedRGB(Timeline.rampT(forSpeedKn: kn))
    let d = { (v: Double) -> Int in Int((v * (1 - PIN_RAMP_DARKEN)).rounded()) }
    return String(format: "#%02x%02x%02x", d(c.r), d(c.g), d(c.b))
}

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
/// `SlackwaterApp.mapPane` remounts `MapViewRepresentable` via
/// `.id(mapFocusToken)` on every pin focus, so `MapStyler.init` used to
/// rebuild the whole world bundle's tide/current tones from scratch on every
/// single tap — the ~0.5s `testPinLayerBuildsInsideAFrame` measures, paid
/// again and again in one map session, not once per session.
///
/// Keyed on two things that actually change the answer: `chsTones` (busts
/// the instant a real dict arrives via `update`, called from
/// `MapStyler.applyChsTones` after a CHS fit lands — a stale CHS tone would
/// be a worse bug than the rebuild cost this exists to avoid) and a 30-minute
/// time bucket, `PIN_TIDE_DIFF_DT` — the same resolution
/// `tidePinRisingHybrid`'s own hybrid check already uses, so rebuilding more
/// often than that buys nothing and rebuilding less often would show a tide
/// pin that never turns.
///
/// Internal, not `private`, and its cache is lock-protected rather than
/// actor-isolated: `stationSource()` runs on whatever thread builds a style —
/// main for the fallback, a `URLSession` callback thread for Seascape
/// (`fetchSeascape`/`composeStyle`) — and `applyChsTones` writes from its own
/// detached task, so real cross-thread access exists; a lock around a few
/// dictionary reads is the smaller fix than moving every caller onto an
/// actor. Internal (not private) so `NationalScaleTests` can exercise the
/// cache/invalidate contract directly and reset it between measurements.
final class PinFeaturesCache: @unchecked Sendable {
    static let shared = PinFeaturesCache()
    private let lock = NSLock()
    private var bucket: Int?
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
        if tones != newTones || bucket != b || geojson.isEmpty {
            tones = newTones
            geojson = pinFeatures(chsTones: newTones)
            bucket = b
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
        tones = [:]
        geojson = [:]
    }
}

private func landSource(_ landUrl: String) -> [String: Any] {
    ["type": "vector", "url": landUrl, "attribution": "© OpenStreetMap contributors"]
}

/// Two land tilesets, and the split is the M53 basemap decision (see
/// tools/build-land.sh). `land-usca` is US+Canada z0-9 — the floor, so no
/// bundled station can ever open onto blank water. `land` is the Salish Sea at
/// z0-14, drawn OVER it: home water keeps its detail, and outside its bounds
/// the source simply has no tiles and the coarse floor shows through.
private func landSources(_ landUrl: String, _ uscaUrl: String) -> [String: Any] {
    ["land": landSource(landUrl), "land-usca": landSource(uscaUrl)]
}

/// The stroked outline carries the coast: land fill on pale water is 1.08:1 —
/// no coast at all. Full opacity from z0 (seamap's own ramps in too late for
/// a discovery map opening at 7.35).
private let COASTLINE: [String: Any] = [
    "line-color": CHART_INK,
    "line-opacity": 0.55,
    "line-width": ["interpolate", ["linear"], ["zoom"], 3, 0.4, 9, 0.8, 14, 1.4] as [Any],
]

private let landLayers: [[String: Any]] = [
    ["id": "land-usca", "type": "fill", "source": "land-usca", "source-layer": "land",
     "paint": ["fill-color": LAND_TONE]],
    ["id": "land", "type": "fill", "source": "land", "source-layer": "land",
     "paint": ["fill-color": LAND_TONE]],
    ["id": "land-usca-coast", "type": "line", "source": "land-usca", "source-layer": "land",
     "paint": COASTLINE],
    ["id": "land-coast", "type": "line", "source": "land", "source-layer": "land",
     "paint": COASTLINE],
]

/// Cluster below this zoom, individual dots at and above it.
///
/// 6, not the default (maxzoom − 1), and the number is the whole point: the
/// discovery map opens at 7.35, so the Salish view every existing user knows
/// still shows individual, tappable stations. Clustering only takes over at
/// the regional-and-wider zooms where 3,125 separate dots are a grey smear
/// nobody can aim at (M53).
private let CLUSTER_MAX_ZOOM = 6

/// Every bundled station as a clustered GeoJSON source.
private func stationSource() -> [String: Any] {
    [
        "type": "geojson", "data": PinFeaturesCache.shared.snapshot(),
        "cluster": true, "clusterMaxZoom": CLUSTER_MAX_ZOOM, "clusterRadius": 46,
    ]
}

private func pinLayers(hasGlyphs: Bool, labelFont: [String]) -> [[String: Any]] {
    let notACluster: [Any] = ["!", ["has", "point_count"]]
    let clusters: [String: Any] = [
        "id": "station-clusters", "type": "circle", "source": "stations",
        "filter": ["has", "point_count"] as [Any],
        "paint": [
            // Area, roughly, with the count — so a 400-station cluster reads
            // as bigger than a 5-station one without swallowing the coast.
            "circle-radius": ["interpolate", ["linear"], ["get", "point_count"],
                              2, 11, 25, 16, 150, 22, 600, 30] as [Any],
            "circle-color": PIN_NEUTRAL,
            "circle-opacity": 0.82,
            "circle-stroke-width": PIN_HALO,
            "circle-stroke-color": CHART_INK,
        ],
    ]
    let currentPins: [String: Any] = [
        "id": "station-pins-current", "type": "circle", "source": "stations",
        "filter": ["all", notACluster, ["==", ["get", "kind"], "current"]] as [Any],
        "paint": [
            "circle-radius": PIN_RADIUS,
            "circle-color": PIN_STATE_COLOUR,
            "circle-stroke-width": PIN_HALO,
            "circle-stroke-color": CHART_INK,
        ],
    ]
    let tideIconLayout: [String: Any] = [
        "icon-allow-overlap": true,
        "icon-ignore-placement": true,
    ]
    /// The tide square's outline (see `squarePinImage`): a larger ink square
    /// under the state-coloured one, because `icon-halo-*` does not render on
    /// this image. Not in the tap layers — `handleTap` hit-tests
    /// `station-pins-tide`, and a plate that answered too would return the
    /// same feature twice.
    let tidePinPlate: [String: Any] = [
        "id": "station-pins-tide-plate", "type": "symbol", "source": "stations",
        "filter": ["all", notACluster, ["!=", ["get", "kind"], "current"]] as [Any],
        "layout": tideIconLayout.merging(["icon-image": "pin-square-plate"]) { _, new in new },
        "paint": ["icon-color": CHART_INK],
    ]
    // tide and chs are both tide stations — provenance is not kind.
    let tidePins: [String: Any] = [
        "id": "station-pins-tide", "type": "symbol", "source": "stations",
        "filter": ["all", notACluster, ["!=", ["get", "kind"], "current"]] as [Any],
        "layout": tideIconLayout.merging(["icon-image": "pin-square"]) { _, new in new },
        "paint": ["icon-color": PIN_STATE_COLOUR],
    ]
    // Labels need glyphs — the local fallback declares none, so it's pins only
    // (same decisive signal as the web). A cluster with no number on it is a
    // blob, so the cluster layer is glyphless-safe by the same rule.
    guard hasGlyphs else { return [clusters, currentPins, tidePinPlate, tidePins] }
    let counts: [String: Any] = [
        "id": "station-cluster-count", "type": "symbol", "source": "stations",
        "filter": ["has", "point_count"] as [Any],
        "layout": [
            "text-field": ["get", "point_count_abbreviated"] as [Any],
            "text-font": labelFont,
            "text-size": 12,
            "text-allow-overlap": true,
        ],
        "paint": ["text-color": CHART_INK],
    ]
    let labels: [String: Any] = [
        "id": "station-labels", "type": "symbol", "source": "stations",
        "filter": notACluster,
        "layout": [
            "text-field": ["get", "name"] as [Any],
            "text-font": labelFont,
            "text-size": 11,
            "text-offset": [0, 1.1],
            "text-anchor": "top",
            "text-optional": true,
        ],
        "paint": ["text-color": CHART_INK, "text-halo-color": WATER_TONE, "text-halo-width": 1],
    ]
    return [clusters, counts, currentPins, tidePinPlate, tidePins, labels]
}

/// Seamap layers this app does not draw (TSS routeing lanes and the
/// `radio_station` ring dominate the chart and answer questions Slackwater is
/// not in). A filter, not a pruned artifact, so `seamap-layers.json` stays a
/// verbatim slice of style.json — to put either back, delete its line.
///
/// The two `land` layers go for a different reason: the app draws land from its
/// own two tilesets, `land.pmtiles` covering the same water as seamap at z0-14
/// against seamap's z12. Seamap's copy was a second, coarser one painted on top
/// in a slightly different cream (#f5e6bd over LAND_TONE's #f5ecd7). Neither
/// seamap artifact carries the `land` source-layer now (tools/build-seamap.sh),
/// so these would draw nothing anyway.
private func SEAMAP_OMIT(_ id: String) -> Bool {
    id.hasPrefix("TSS-")
        || id == "radio_station"
        || id == "land_area" || id == "land_outline"
}

/// SPIKE (research/seamap-offline, openwatersio/seascape#121): a bundled
/// offline PMTiles layer-set — "seamap" (Open Waters Seamap chart marks +
/// freenauticalchart sprite) or "seascape" (bathymetry). `<name>.pmtiles` is a
/// `pmtiles extract` clipped to the Salish box; `<slice ?? name>-layers.json` is
/// a verbatim slice of the published style.json. The seamap slice keeps its
/// `text-*` keys and draws them with the bundled glyphs (#29); the seascape
/// slice still ships text-stripped (its text bakes in a unit — see
/// tools/build-seascape.sh). Returns nil when the resources aren't in the
/// bundle, so main stays on the land-only fallback.
///
/// `slice` names a slice belonging to a different tileset: `seamap-natl` is the
/// same chart at national scale, so it reads `seamap`'s slice rather than
/// bundling a byte-identical second copy of it.
func offlineLayers(_ name: String, slice: String? = nil, sprite: String? = nil, attribution: String)
        -> (sprite: String?, layers: [[String: Any]], source: [String: Any])? {
    guard let tiles = Bundle.main.url(forResource: name, withExtension: "pmtiles"),
          let layersUrl = Bundle.main.url(forResource: "\(slice ?? name)-layers", withExtension: "json"),
          let data = try? Data(contentsOf: layersUrl),
          let layers = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return nil }
    var spriteBase: String?
    if let sprite {
        guard let url = Bundle.main.url(forResource: sprite, withExtension: "json") else { return nil }
        // The style spec's multi-sprite form: layers reference "freenauticalchart:foo".
        spriteBase = url.deletingPathExtension().absoluteString
    }
    return (spriteBase,
            layers.filter { nativeLayerTypes.contains($0["type"] as? String ?? "") }
                  .filter { !SEAMAP_OMIT(($0["id"] as? String) ?? "") },
            ["type": "vector", "url": "pmtiles://\(tiles.absoluteString)",
             "attribution": attribution])
}

/// A slice aimed at its national tileset (#30): same layers, each id suffixed
/// and each `source` repointed, so the coarse wide set and the detailed home
/// one can live in the same style.
private func national(_ layers: [[String: Any]], source: String) -> [[String: Any]] {
    layers.map { layer in
        var natl = layer
        natl["id"] = "\(layer["id"] as? String ?? "")-natl"
        natl["source"] = source
        return natl
    }
}

/// The fontstack the offline style's own labels use — the same one most of
/// the seamap slice asks for, so one set of bundled PBFs serves both.
private let OFFLINE_LABEL_FONT = ["noto_sans_regular"]

/// #29: glyphs from the bundle. tools/build-seamap.sh downloads the latin
/// ranges of the two stacks the seamap slice references, flat-named
/// `<fontstack>-<range>.pbf` (a folder reference would need project.yml
/// surgery; the template tokens don't care). nil when they aren't bundled —
/// the style then declares no glyphs and keeps the old label-free shape.
private func bundledGlyphs() -> String? {
    guard let probe = Bundle.main.url(forResource: "\(OFFLINE_LABEL_FONT[0])-0-255",
                                      withExtension: "pbf")
    else { return nil }
    return probe.deletingLastPathComponent().absoluteString + "{fontstack}-{range}.pbf"
}

/// Offline / style-fetch-failed: land + pins, honestly bare (web localFallbackStyle).
func localFallbackStyle(landUrl: String, uscaUrl: String) -> [String: Any] {
    var sources = landSources(landUrl, uscaUrl)
    sources["stations"] = stationSource()
    let glyphs = bundledGlyphs()
    var style: [String: Any] = [
        "version": 8,
        "sources": sources,
        "layers": [
            ["id": "land-bg", "type": "background", "paint": ["background-color": WATER_TONE]],
        ] + landLayers + pinLayers(hasGlyphs: glyphs != nil,
                                   labelFont: glyphs != nil ? OFFLINE_LABEL_FONT : []),
    ]
    if let glyphs { style["glyphs"] = glyphs }
    // Everything slots in above the land floor and below the pins, and depth
    // goes in before the chart marks so the marks draw over it — a buoy behind
    // a depth-area fill is a chart that lies about what is there.
    func insertAboveLand(_ slice: [[String: Any]]) {
        var layers = style["layers"] as! [[String: Any]]
        let anchor = layers.firstIndex { ($0["id"] as? String) == "station-clusters" } ?? layers.count
        layers.insert(contentsOf: slice, at: anchor)
        style["layers"] = layers
    }
    // Bathymetry, national first and Salish over it — the same two-tileset shape
    // as the chart below, and the same reason (#30). The national cut stops at
    // z6 where the chart's stops at z9: `depth-areas` IS that archive, so there
    // is no undrawn layer to strip and the curve runs 13 MB at z6 to 276 at z8.
    // Shaded water under a station anywhere, not contours you would navigate on.
    if let natl = offlineLayers("seascape-natl", slice: "seascape",
                                attribution: "© Open Waters: Seascape") {
        sources["seascape-natl"] = natl.source
        style["sources"] = sources
        insertAboveLand(national(natl.layers, source: "seascape-natl"))
    }
    if let seascape = offlineLayers("seascape", attribution: "© Open Waters: Seascape") {
        sources["seascape-vector"] = seascape.source
        style["sources"] = sources
        insertAboveLand(seascape.layers)
    }
    // #30, and the same split as the two land tilesets: `seamap-natl` is the
    // whole country at z9, `seamap` the Salish Sea at z12 drawn OVER it. Open a
    // station in San Francisco and the chart marks are there; home water keeps
    // the detail. Inside the Salish box both sources have the mark, and the
    // detailed one wins the collision because it is inserted last.
    if let natl = offlineLayers("seamap-natl",
                                slice: "seamap",
                                attribution: "© Open Waters: Seamap © OpenStreetMap contributors") {
        sources["seamap-natl"] = natl.source
        style["sources"] = sources
        insertAboveLand(national(natl.layers, source: "seamap-natl"))
    }
    if let seamap = offlineLayers("seamap", sprite: "freenauticalchart",
                                  attribution: "© Open Waters: Seamap © OpenStreetMap contributors"),
       let spriteUrl = seamap.sprite {
        sources["seamap"] = seamap.source
        style["sources"] = sources
        style["sprite"] = [["id": "freenauticalchart", "url": spriteUrl]]
        insertAboveLand(seamap.layers)
    }
    if currentFillEnabled { addFillStyle(&style) }
    return style
}

// Layer types this MapLibre Native release renders. Seascape's style leans on
// GL-JS-v5 `color-relief` (depth shading), which native rejects — filtered
// out, so online adds contours/soundings/labels but not the shaded relief.
private let nativeLayerTypes: Set<String> = [
    "background", "fill", "line", "symbol", "circle", "raster",
    "fill-extrusion", "heatmap", "hillshade",
]

/// Seascape, made ours (web composeStyle): OSM raster out (licence), our land
/// in above the relief, pins on top. Missing anchors degrade to appending.
func composeStyle(_ seascape: [String: Any], landUrl: String, uscaUrl: String) -> [String: Any] {
    var style = seascape
    var layers = (seascape["layers"] as? [[String: Any]] ?? [])
        .filter { ($0["id"] as? String) != "osm-base" }
        .filter { nativeLayerTypes.contains($0["type"] as? String ?? "") }
    let anchor = layers.firstIndex { ($0["id"] as? String) == "contour-lines" } ?? layers.count
    layers.insert(contentsOf: landLayers, at: anchor)
    // Seascape's water tone comes from its color-relief layers, which the
    // filter above removed — put our navy under everything so water isn't the
    // renderer's default black.
    layers.insert(["id": "water-bg", "type": "background",
                   "paint": ["background-color": WATER_TONE]], at: 0)

    var sources = seascape["sources"] as? [String: Any] ?? [:]
    for (key, value) in landSources(landUrl, uscaUrl) { sources[key] = value }
    sources["stations"] = stationSource()
    style["sources"] = sources

    let hasGlyphs = seascape["glyphs"] is String
    // Prefer the host style's own font stack, like the web.
    let sample = layers.first {
        ($0["type"] as? String) == "symbol" &&
        (($0["layout"] as? [String: Any])?["text-font"] as? [String]) != nil
    }
    let font = (sample?["layout"] as? [String: Any])?["text-font"] as? [String]
        ?? ["Open Sans Regular", "Arial Unicode MS Regular"]
    style["layers"] = layers + pinLayers(hasGlyphs: hasGlyphs, labelFont: font)
    if currentFillEnabled { addFillStyle(&style) }
    return style
}

// MARK: - Shared style loading + camera assertion

/// Loads the fallback style immediately and Seascape when its fetch lands
/// (web MapScreen, Open Waters offline.md: no error banner — the map renders
/// what it can reach), and re-asserts the camera after each style load. The
/// camera must be asserted post-layout: a zoomLevel set on a zero-frame view
/// converts through a degenerate altitude and the map opened continent-wide.
final class MapStyler: NSObject, MLNMapViewDelegate {
    private weak var map: MLNMapView?
    private let cacheName: String
    private let center: CLLocationCoordinate2D
    private let zoom: Double
    private let fill = currentFillEnabled ? CurrentFillRenderer() : nil

    init(map: MLNMapView, cacheName: String, center: CLLocationCoordinate2D, zoom: Double) {
        self.map = map
        self.cacheName = cacheName
        self.center = center
        self.zoom = zoom
        super.init()
        map.delegate = self
        setStyle(localFallbackStyle(landUrl: landUrl, uscaUrl: uscaUrl), name: "\(cacheName)-fallback")
        fetchSeascape()
    }

    private func pmtilesUrl(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pmtiles") else { return "" }
        return "pmtiles://\(url.absoluteString)"  // pmtiles://file:///…/land.pmtiles
    }

    private var landUrl: String { pmtilesUrl("land") }
    private var uscaUrl: String { pmtilesUrl("land-usca") }

    /// MLN loads styles by URL — write the composed JSON next to the caches.
    private func setStyle(_ style: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: style),
              let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        let url = dir.appendingPathComponent("map-style-\(name).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        DispatchQueue.main.async { self.map?.styleURL = url }
    }

    private func fetchSeascape() {
        guard !networkKillSwitch else { return }
        // Not .standard: Settings' unit toggle now writes to the App Group
        // (H2), so a plain .standard read here would freeze at whatever the
        // one-time migration copied and never see a later change.
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"
        guard let url = URL(string: "https://tiles.openwaters.io/seascape/style.json?unit=\(imperial ? "ft" : "m")")
        else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self, let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }  // offline or upstream down: the fallback style is already up
            self.setStyle(composeStyle(json, landUrl: self.landUrl, uscaUrl: self.uscaUrl),
                          name: "\(self.cacheName)-seascape")
        }.resume()
    }

    /// A filled square at equal AREA with the 5pt circle pins (side r·√π —
    /// same-width reads heavier). Template image so `icon-color` can tint it
    /// (MapLibre Native's SDF path; without it the pin ignores state).
    /// GOTCHA: Native draws no `icon-halo-*` on this image at all, so the
    /// outline is `inflate` — a larger backing square drawn underneath in
    /// `CHART_INK`.
    private func squarePinImage(radius: CGFloat = CGFloat(PIN_RADIUS),
                                inflate: CGFloat = 0, scale: CGFloat = 3) -> UIImage {
        let side = radius * CGFloat(Double.pi.squareRoot()) + inflate * 2
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    // ponytail: re-asserts on every style load, so a Seascape arriving late
    // recenters a user who already panned; track interaction if it annoys.
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        mapView.setCenter(center, zoomLevel: zoom, animated: false)
        // Fires on every style load (local fallback, then Seascape) — the
        // tide-pin icon must be re-registered each time or the swap loses it.
        style.setImage(squarePinImage(), forName: "pin-square")
        style.setImage(squarePinImage(inflate: CGFloat(PIN_HALO)), forName: "pin-square-plate")
        applyChsTones(to: style)
        fill?.attach(to: style, map: mapView)
    }

    /// Issue #12: colour the CHS pins from what the offline sync has ALREADY
    /// stored. Runs here, per style load, because that is the only place it
    /// can survive: setting a style rebuilds every source, discarding anything
    /// pushed into the old one — and this map styles twice (fallback, then
    /// Seascape). After paint by construction, so the style-construction path
    /// `testPinLayerBuildsInsideAFrame` budgets pays nothing; the 3,125-pin
    /// source rebuild runs off the main thread. Cache only, never a fetch —
    /// `chsPinTones` takes the stored records and nothing else.
    private func applyChsTones(to style: MLNStyle) {
        Task { @MainActor [weak style] in
            let service = ChsFitService.shared
            let tides = service.tideRecords
            let currents = service.currentRecords
            let geojson = await Task.detached(priority: .utility) { () -> Data? in
                let tones = chsPinTones(at: appNow(), tideRecords: tides, currentRecords: currents)
                guard !tones.isEmpty else { return nil }   // nothing synced — neutral is honest
                let geojson = PinFeaturesCache.shared.update(tones: tones)
                return try? JSONSerialization.data(withJSONObject: geojson)
            }.value
            guard let geojson, let style,
                  let source = style.source(withIdentifier: "stations") as? MLNShapeSource,
                  let shape = try? MLNShape(data: geojson, encoding: String.Encoding.utf8.rawValue)
            else { return }
            source.shape = shape
        }
    }
}

// MARK: - The map view

struct MapViewRepresentable: UIViewRepresentable {
    /// Where the discovery map opens. A real fix when there is one — a user in
    /// Boston must not open the map on the Salish Sea (M53) — and the Salish
    /// camera when there isn't, which is also what the UI tests see.
    let center: CLLocationCoordinate2D
    /// Discovery zoom by default; the map-header title tap (issue #32) passes
    /// `stationZoom` instead so a focused jump lands framed on one station,
    /// not the whole Salish Sea.
    var zoom: Double = discoveryZoom
    let onSelect: (StationItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.attributionButtonPosition = .bottomLeft
        map.logoViewPosition = .bottomLeft
        map.showsUserLocation = LocationService.shared.authorized
        context.coordinator.install(on: map, center: center, zoom: zoom)
        return map
    }

    /// Camera changes arrive as remounts — `mapPane` sets `.id(mapFocusToken)`
    /// so a header-title focus rebuilds the view and `makeUIView` frames it.
    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject {
        let onSelect: (StationItem) -> Void
        private weak var map: MLNMapView?
        private var styler: MapStyler?

        init(onSelect: @escaping (StationItem) -> Void) { self.onSelect = onSelect }

        func install(on map: MLNMapView, center: CLLocationCoordinate2D, zoom: Double) {
            self.map = map
            styler = MapStyler(map: map, cacheName: "discovery",
                               center: center, zoom: zoom)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            map.addGestureRecognizer(tap)
        }

        /// Tap → nearest station dot within a finger-sized box → detail. A
        /// CLUSTER instead means "there are more stations here than pixels":
        /// zoom into it rather than guessing which one was meant.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map else { return }
            let point = gesture.location(in: map)
            let box = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            func nearest(_ layers: Set<String>) -> MLNFeature? {
                map.visibleFeatures(in: box, styleLayerIdentifiers: layers).min { a, b in
                    let pa = map.convert(a.coordinate, toPointTo: map)
                    let pb = map.convert(b.coordinate, toPointTo: map)
                    return hypot(pa.x - point.x, pa.y - point.y) < hypot(pb.x - point.x, pb.y - point.y)
                }
            }
            if let id = nearest(["station-pins-current", "station-pins-tide"])?.attribute(forKey: "id") as? String,
               let item = StationItem.byId[id] {
                onSelect(item)
                return
            }
            guard let cluster = nearest(["station-clusters"]) else { return }
            // +2 levels lands past CLUSTER_MAX_ZOOM from any clustered zoom, so
            // one tap on a cluster always breaks it into something tappable.
            map.setCenter(cluster.coordinate, zoomLevel: min(map.zoomLevel + 2, 12), animated: true)
        }
    }
}
