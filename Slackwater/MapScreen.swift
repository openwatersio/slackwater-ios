// Slackwater — GPL v3. The discovery map: one satellite style (offline via
// ChartPackManager's tile packs — offline-chart-packs spec §1), every bundled
// station as a pin, tap → detail.
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

/// Under the satellite raster while tiles load or are absent offline —
/// Seascape's flat deep-water tone, not a hand-picked blue.
private let WATER_TONE = "#e9f7ff"
/// Pin fills fail WCAG's 3:1 on pale water, so the contrast lives on the
/// stroke — every pin carries this ink outline (asserted in
/// `testEveryPinOutlineClearsTheContrastFloorOnBothGrounds`).
let CHART_INK = "#0b1a2b"
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

/// Cluster below this zoom, individual dots at and above it.
///
/// 6, not the default (maxzoom − 1), and the number is the whole point: the
/// discovery map opens at 7.35, so the Salish view every existing user knows
/// still shows individual, tappable stations. Clustering only takes over at
/// the regional-and-wider zooms where 3,125 separate dots are a grey smear
/// nobody can aim at (M53).
let CLUSTER_MAX_ZOOM = 6

/// The station labels' fontstack — the same one the basemap style's own
/// labels use, so offline packs cache its glyph ranges as part of the
/// basemap's needs and runtime labels ride along.
private let LABEL_FONT = ["noto_sans_bold"]

func hexColor(_ hex: String) -> UIColor {
    let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// Every bundled station as a clustered runtime source. Added by `MapStyler`
/// per style load — the basemap is a style URL this app does not own, so the
/// app's channels go in through the runtime API, never into the style JSON.
func stationShapeSource() -> MLNShapeSource {
    let data = try? JSONSerialization.data(withJSONObject: PinFeaturesCache.shared.snapshot())
    let shape = data.flatMap { try? MLNShape(data: $0, encoding: String.Encoding.utf8.rawValue) }
    return MLNShapeSource(identifier: "stations", shape: shape, options: [
        .clustered: true,
        .clusterRadius: 46,
        .maximumZoomLevelForClustering: Double(CLUSTER_MAX_ZOOM),
    ])
}

/// The pin layers, bottom to top. Expressions come from the same JSON specs
/// the web uses, converted via `mglJSONObject` so the two renderers cannot
/// drift on paint.
func stationPinLayers(source: MLNShapeSource) -> [MLNStyleLayer] {
    func e(_ json: Any) -> NSExpression { NSExpression(mglJSONObject: json) }
    let notACluster = NSPredicate(mglJSONObject: ["!", ["has", "point_count"]])
    let isCluster = NSPredicate(mglJSONObject: ["has", "point_count"] as [Any])
    let notCurrent = NSPredicate(mglJSONObject:
        ["all", ["!", ["has", "point_count"]], ["!=", ["get", "kind"], "current"]])
    let ink = NSExpression(forConstantValue: hexColor(CHART_INK))
    let halo = NSExpression(forConstantValue: PIN_HALO)
    let font = NSExpression(forConstantValue: LABEL_FONT)

    let clusters = MLNCircleStyleLayer(identifier: "station-clusters", source: source)
    clusters.predicate = isCluster
    // Area, roughly, with the count — so a 400-station cluster reads as
    // bigger than a 5-station one without swallowing the coast.
    clusters.circleRadius = e(["interpolate", ["linear"], ["get", "point_count"],
                               2, 11, 25, 16, 150, 22, 600, 30])
    clusters.circleColor = NSExpression(forConstantValue: hexColor(PIN_NEUTRAL))
    clusters.circleOpacity = NSExpression(forConstantValue: 0.82)
    clusters.circleStrokeWidth = halo
    clusters.circleStrokeColor = ink

    let counts = MLNSymbolStyleLayer(identifier: "station-cluster-count", source: source)
    counts.predicate = isCluster
    counts.text = e(["get", "point_count_abbreviated"])
    counts.textFontNames = font
    counts.textFontSize = NSExpression(forConstantValue: 12)
    counts.textAllowsOverlap = NSExpression(forConstantValue: true)
    counts.textColor = ink

    let currentPins = MLNCircleStyleLayer(identifier: "station-pins-current", source: source)
    currentPins.predicate = NSPredicate(mglJSONObject:
        ["all", ["!", ["has", "point_count"]], ["==", ["get", "kind"], "current"]])
    currentPins.circleRadius = NSExpression(forConstantValue: PIN_RADIUS)
    currentPins.circleColor = e(PIN_STATE_COLOUR)
    currentPins.circleStrokeWidth = halo
    currentPins.circleStrokeColor = ink

    // The tide square's outline (see `squarePinImage`): a larger ink square
    // under the state-coloured one, because `icon-halo-*` does not render on
    // this image. Not in the tap layers — `handleTap` hit-tests
    // `station-pins-tide`, and a plate that answered too would return the
    // same feature twice.
    let tidePinPlate = MLNSymbolStyleLayer(identifier: "station-pins-tide-plate", source: source)
    tidePinPlate.predicate = notCurrent
    tidePinPlate.iconImageName = NSExpression(forConstantValue: "pin-square-plate")
    tidePinPlate.iconAllowsOverlap = NSExpression(forConstantValue: true)
    tidePinPlate.iconIgnoresPlacement = NSExpression(forConstantValue: true)
    tidePinPlate.iconColor = ink

    // tide and chs are both tide stations — provenance is not kind.
    let tidePins = MLNSymbolStyleLayer(identifier: "station-pins-tide", source: source)
    tidePins.predicate = notCurrent
    tidePins.iconImageName = NSExpression(forConstantValue: "pin-square")
    tidePins.iconAllowsOverlap = NSExpression(forConstantValue: true)
    tidePins.iconIgnoresPlacement = NSExpression(forConstantValue: true)
    tidePins.iconColor = e(PIN_STATE_COLOUR)

    let labels = MLNSymbolStyleLayer(identifier: "station-labels", source: source)
    labels.predicate = notACluster
    labels.text = e(["get", "name"])
    labels.textFontNames = font
    labels.textFontSize = NSExpression(forConstantValue: 11)
    labels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.1)))
    labels.textAnchor = NSExpression(forConstantValue: "top")
    labels.textOptional = NSExpression(forConstantValue: true)
    labels.textColor = ink
    labels.textHaloColor = NSExpression(forConstantValue: hexColor(WATER_TONE))
    labels.textHaloWidth = NSExpression(forConstantValue: 1)

    return [clusters, counts, currentPins, tidePinPlate, tidePins, labels]
}

// MARK: - Shared style loading + camera assertion

/// Points the map at the chart style (no error banner — the map renders what
/// the packs and the network can reach) and re-asserts the camera after each
/// style load. The camera must be asserted post-layout: a zoomLevel set on a
/// zero-frame view converts through a degenerate altitude and the map opened
/// continent-wide.
final class MapStyler: NSObject, MLNMapViewDelegate {
    private weak var map: MLNMapView?
    private let center: CLLocationCoordinate2D
    private let zoom: Double
    private let fill = currentFillEnabled() ? CurrentFillRenderer() : nil

    init(map: MLNMapView, center: CLLocationCoordinate2D, zoom: Double) {
        self.map = map
        self.center = center
        self.zoom = zoom
        super.init()
        map.delegate = self
        map.styleURL = BASEMAP_STYLE_URL
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

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        mapView.setCenter(center, zoomLevel: zoom, animated: false)
        // Fires on every style load — everything runtime-added (images,
        // sources, layers) belongs to the style that loaded, so it all
        // re-registers here or a style swap loses it.
        style.setImage(squarePinImage(), forName: "pin-square")
        style.setImage(squarePinImage(inflate: CGFloat(PIN_HALO)), forName: "pin-square-plate")
        style.setImage(currentDirectionImage(),
                       forName: CurrentFillRenderer.directionImageID)
        // Fill under the pins: added first, so the pin layers appended below
        // land on top of it.
        fill?.attach(to: style, map: mapView)
        if style.source(withIdentifier: "stations") == nil {
            let source = stationShapeSource()
            style.addSource(source)
            for layer in stationPinLayers(source: source) { style.addLayer(layer) }
        }
        applyChsTones(to: style)
    }

    /// Issue #12: colour the CHS pins from what the offline sync has ALREADY
    /// stored. Runs here, per style load, because that is the only place it
    /// can survive: setting a style rebuilds every source, discarding anything
    /// pushed into the old one. After paint by construction, so the style-construction path
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
            styler = MapStyler(map: map, center: center, zoom: zoom)
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
