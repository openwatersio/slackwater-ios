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

/// UI-test hook, like `-openMap`: `-mapZoom 3.2` opens the discovery map at a
/// stated zoom. Synthesised pinches are not a camera — five of them land
/// somewhere the test cannot name, which is no way to screenshot "continental".
let discoveryZoom: Double = {
    guard let at = CommandLine.arguments.firstIndex(of: "-mapZoom"),
          CommandLine.arguments.indices.contains(at + 1),
          let zoom = Double(CommandLine.arguments[at + 1]) else { return SALISH_ZOOM }
    return zoom
}()

// The MapScreen full-screen-cover wrapper (header + X) is gone — M4.5 shows
// the map in place behind the list ⇄ map toggle FAB (StationListView.mapPane).

// MARK: - Style building (mirrors web mapStyle.ts)

private let LAND_TONE = "#f5ecd7"   // paper-chart cream
/// Seascape's own `background-color`, which is also the flat end of its depth
/// ramp — the tone it paints once the water is deeper than 50 m and there is no
/// longer any depth to shade. So this is not "a light blue we picked": it is
/// literally the colour Seascape's chart settles to where depth stops being
/// information, which is exactly the light water we want without the shading
/// that came with it.
private let WATER_TONE = "#e9f7ff"
/// Was WATER_TONE, back when water was navy and "the tone under everything"
/// and "the tone that outlines a mark" happened to be the same value. On pale
/// water they are not, and the coincidence was load-bearing: pin fills clear
/// WCAG's 3:1 for a non-text mark on navy (flood 6.05, ebb 8.14, slack 7.61)
/// and fail it on #e9f7ff (2.65, 1.97, 2.11). A bounded mark may carry that
/// contrast on its boundary, so the ink moves to the stroke — 16.05:1 on the
/// water, 14.92:1 on the land, i.e. the pin reads on either ground in every
/// state, which the fill alone never did.
private let CHART_INK = "#0b1a2b"
// A pin's COLOUR is the water's state, never the station's kind — kind is the
// pin's SHAPE: a circle for a current station, a square for a tide one. One
// shape per feature class, the oldest convention on any chart, and a silhouette
// difference reads where an interior one does not.
//
// `chs` is a Canadian tide port. That is provenance, not kind — it draws the
// same square a NOAA tide station does.
/// MapLibre style dicts hold strings and cannot read a Swift `Color`, so the
/// palette crosses over as "#rrggbb" — but derived from the same `SN` hex the
/// token is built from, never hand-copied. A hand-maintained copy is silent
/// drift: retarget `SN.flood` and the map would keep the old blue, leaving two
/// blues that both mean flood and no test anywhere that fails.
func mapHex(_ hex: UInt32) -> String { String(format: "#%06x", hex) }

/// The unknown-state pin. `SN.steel`, the same token the card glyph draws for
/// `.unknown` — one meaning, one value. It replaced a lighter map-only grey
/// (#7d9cb8) which, besides being a second value for the same idea, sat at
/// 2.44:1 against the map's cream land polygons — under WCAG's 3:1 for a
/// non-text mark. Steel clears both grounds on its own: 3.49:1 on the pale
/// water, 3.25:1 on the land. It is the only state that still does, which is
/// why every pin now also carries the `CHART_INK` stroke.
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
let PIN_STATE_COLOUR: [Any] = [
    "match", ["get", "state"],
    "rising", mapHex(SN.floodHex), "flood", mapHex(SN.floodHex),
    "falling", mapHex(SN.ebbHex), "ebb", mapHex(SN.ebbHex),
    "slack", mapHex(SN.goHex),
    PIN_NEUTRAL,   // unknown
]

private func phaseName(_ phase: CurrentPhase) -> String {
    switch phase {
    case .flood: "flood"
    case .ebb: "ebb"
    case .slack: "slack"
    }
}

/// Fix round 1 shrank the pin's direction search from `cardState(at:)`'s
/// 30h window to a short one — fast, but only 838/5,700 (station, moment)
/// checks in `testShortWindowDirectionMatchesThirtyHourBaseline` actually
/// resolved a tone; the rest silently drew neutral. That traded correctness
/// for coverage nobody asked to give up (fix round 2). This is the exact
/// search a *fallback* uses instead, once round 2's cheap check below has
/// already flagged that this one station needs it — so it runs for a small
/// minority of stations, not all 1,425, and can afford a window wide enough
/// to always find the next turn (13h clears a diurnal station's ~12.4h
/// half-period; semidiurnal turns roughly every 6.2h).
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

/// How far apart the cheap two-sample check looks, and how big a height
/// change counts as a trustworthy signal rather than turn-adjacent noise.
///
/// `cardState(at:)`'s doc comment warns against differencing two height
/// samples: near a turn the curve is flat, so a naive diff can point the
/// wrong way. That is real — measured directly, a raw (unnormalised) diff
/// disagreed with the 30h baseline in 62/5,700 checks — but the failure
/// announces itself: every wrong sign showed up on a small |Δh|. So rather
/// than discard the cheap path, only distrust it near that floor and fall
/// back to the exact search for that one station.
///
/// The threshold weights each constituent's amplitude by its known
/// astronomical SPEED (degrees/hour — Doodson/NOAA constants, fixed and not
/// something that can drift the way a display colour hex can), not just
/// amplitude. Amplitude alone under-flags fast (semidiurnal) stations and
/// over-flags slow (diurnal) ones at the same amplitude, because a diurnal
/// wave's peak slope is roughly half a semidiurnal one's — proportional to
/// A·ω, not A. Weighting by speed cut the fallback population from 15% to
/// 7% of checks at zero mismatches (see the sweep this shipped with in
/// `testHybridDirectionHasFullCoverageAndMatchesBaseline`'s doc comment: an
/// amplitude-only proxy needed 0.008 for zero wrong-signed trusted samples;
/// speed-weighted needed only 0.0004, for less than half the fallback rate).
let PIN_TIDE_DIFF_DT: TimeInterval = 30 * 60
let PIN_TIDE_DIFF_THRESHOLD: Double = 0.0004
private let constituentSpeed: [String: Double] = [   // degrees/hour
    "M2": 28.9841, "S2": 30.0, "N2": 28.4397, "K2": 30.0821,
    "K1": 15.0411, "O1": 13.9430, "P1": 14.9589, "Q1": 13.3987,
]

/// Direction for one tide station: cheap almost everywhere, exact always.
/// One `heights()` call (same fixed setup cost as any other engine call,
/// amortised over its two samples) gives a height difference; if that's
/// comfortably above the noise floor its sign IS the direction — the curve
/// is steep there, unambiguous. Only near a turn, where the difference is
/// small relative to the station's own speed-weighted range, does this fall
/// back to `tidePinRising`'s exact search, and only for that station.
///
/// The pair is a 30-minute window *around* `now`, not forward from it: the
/// engine's `makeTimeline` floors the start and ceils the end to the `step`
/// grid, so asking for `now … now+30min` at a 30-minute step returns the grid
/// points bracketing `now` — at 12:29 that is 12:00 and 12:30, almost entirely
/// behind the clock. That is fine and is what the sweep measured: the slope of
/// a 30-minute window straddling `now` is the direction at `now` everywhere
/// the threshold trusts it, and the near-turn cases where it would not be are
/// exactly the ones handed to the exact search.
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

/// A station's state as a tone name, for the pin's colour.
///
/// Synchronous only. Bundled NOAA stations predict on device from their own
/// harmonics. Every CHS-provenance item — a CHS tide port, a derived gate
/// (its slack derives from a CHS reference port's fitted tide), or a
/// validated CHS current gate — resolves through `ChsFitService`'s async fit
/// cache, so all three report "unknown" and draw neutral: an honest
/// admission, not a guess. On a boat a wrong slack is worse than an admitted
/// grey. Wiring the async CHS cache in is a follow-on, deliberately not done
/// here.
///
/// Neither bundled case calls `cardState(at:)`: it computes a 30h "next"
/// event neither branch displays, and for a current station that's TWO
/// 30h searches (slack roots + max roots) for a value the pin discards.
/// `pinFeatures()` runs this for all ~3,125 bundled stations on every style
/// build (`testPinLayerBuildsInsideAFrame` budgets the whole thing at 0.3s),
/// so the shortcuts here are load-bearing, not stylistic.
private func pinTone(_ item: StationItem, at now: Date) -> String {
    switch item {
    case .tide(let record):
        guard let rising = tidePinRisingHybrid(record, at: now) else { return "unknown" }
        return rising ? "rising" : "falling"
    case .current(let station):
        let signed = station.engineStation.speeds(from: now, to: now.addingTimeInterval(1), step: 1)
            .first?.speed ?? 0
        return phaseName(currentPhase(signed: signed))
    case .chs, .chsGate, .chsCurrent:
        return "unknown"   // async CHS fit cache — see the doc comment above
    }
}

/// Every bundled station as a GeoJSON pin. Identity only — no readings.
private func pinFeatures() -> [String: Any] {
    [
        "type": "FeatureCollection",
        "features": StationItem.all.map { s in
            [
                "type": "Feature",
                "geometry": ["type": "Point", "coordinates": [s.longitude, s.latitude]],
                "properties": ["id": s.id, "name": s.name, "kind": s.pinKind,
                               "state": pinTone(s, at: appNow())],
            ] as [String: Any]
        },
    ]
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

/// On navy water a cream fill was the whole coastline — 14.4:1, no outline
/// needed. On #e9f7ff the same fill is 1.08:1 against the water, which is not a
/// faint coast but no coast at all: two near-white planes meeting invisibly. So
/// the fills keep the land tone and a stroked outline carries the shape, which
/// is what a paper chart does and why seamap ships its own `land_outline`.
/// Ours is drawn at full opacity from z0 — seamap's ramps in from nothing at z4
/// and only reaches solid at z12, and the discovery map opens at 7.35.
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
        "type": "geojson", "data": pinFeatures(),
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

/// Seamap layers this app does not draw. Traffic separation schemes are a
/// routeing instrument — they tell a ship under way which side of a strait to
/// be on, which is a question Slackwater is not in. They also dominate: the
/// lanes and their boundaries are the widest, highest-contrast marks in the
/// whole tileset, so at Salish zooms the TSS *is* the map and the pins read as
/// an overlay on someone else's chart.
///
/// `radio_station` is the same complaint arriving as one mark: a magenta ring
/// whose radius interpolates to 40 px by z12, marking an AIS/radio station.
/// With the TSS gone it became the loudest thing on an otherwise empty stretch
/// of Haro Strait — a large unexplained circle in open water, drawn for a
/// facility that has no bearing on when the water turns.
///
/// Kept as a filter over the published upstream layer list rather than pruned
/// out of the bundled artifact, so `seamap-layers.json` stays a verbatim slice
/// of `style.json` and this stays a decision someone can read and reverse: to
/// put either back, delete its line.
private func SEAMAP_OMIT(_ id: String) -> Bool {
    id.hasPrefix("TSS-")
        || id == "radio_station"
}

/// SPIKE (research/seamap-offline): the Open Waters Seamap chart, offline.
/// `seamap.pmtiles` is a `pmtiles extract` of the weekly planet archive clipped
/// to the Salish box, `seamap-layers.json` the 44 seamap-source layers lifted
/// from the published style.json with every `text-*` key stripped (no bundled
/// glyphs yet — icons render, labels don't), and the freenauticalchart sprite
/// is bundled beside them. Returns nil when the resources aren't in the bundle,
/// so main stays on the land-only fallback.
func seamapOfflineLayers() -> (sprite: String, layers: [[String: Any]], source: [String: Any])? {
    guard let tiles = Bundle.main.url(forResource: "seamap", withExtension: "pmtiles"),
          let layersUrl = Bundle.main.url(forResource: "seamap-layers", withExtension: "json"),
          let data = try? Data(contentsOf: layersUrl),
          let layers = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let sprite = Bundle.main.url(forResource: "freenauticalchart", withExtension: "json")
    else { return nil }
    // The style spec's multi-sprite form: layers reference "freenauticalchart:foo".
    let spriteBase = sprite.deletingPathExtension().absoluteString
    return (spriteBase,
            layers.filter { nativeLayerTypes.contains($0["type"] as? String ?? "") }
                  .filter { !SEAMAP_OMIT(($0["id"] as? String) ?? "") },
            ["type": "vector", "url": "pmtiles://\(tiles.absoluteString)",
             "attribution": "© Open Waters: Seamap © OpenStreetMap contributors"])
}

/// The Open Waters Seascape bathymetry, offline (openwatersio/seascape#121):
/// `seascape.pmtiles` is a `pmtiles extract` of the planet vector archive
/// clipped to the same Salish box as seamap, `seascape-layers.json` the four
/// `seascape-vector` layers from the published style.json with every `text-*`
/// key stripped. Same shape as `seamapOfflineLayers`, same nil-means-absent
/// contract, and the same open follow-on: two of those four (`soundings`,
/// `contour-labels`) are text-only symbol layers, so they ship inert and light
/// up the day a fontstack does. Depth areas and contours draw today.
func seascapeOfflineLayers() -> (layers: [[String: Any]], source: [String: Any])? {
    guard let tiles = Bundle.main.url(forResource: "seascape", withExtension: "pmtiles"),
          let layersUrl = Bundle.main.url(forResource: "seascape-layers", withExtension: "json"),
          let data = try? Data(contentsOf: layersUrl),
          let layers = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return nil }
    return (layers.filter { nativeLayerTypes.contains($0["type"] as? String ?? "") },
            ["type": "vector", "url": "pmtiles://\(tiles.absoluteString)",
             "attribution": "© Open Waters: Seascape"])
}

/// Offline / style-fetch-failed: land + pins, honestly bare (web localFallbackStyle).
func localFallbackStyle(landUrl: String, uscaUrl: String) -> [String: Any] {
    var sources = landSources(landUrl, uscaUrl)
    sources["stations"] = stationSource()
    var style: [String: Any] = [
        "version": 8,
        "sources": sources,
        "layers": [
            ["id": "land-bg", "type": "background", "paint": ["background-color": WATER_TONE]],
        ] + landLayers + pinLayers(hasGlyphs: false, labelFont: []),
    ]
    // Everything slots in above the land floor and below the pins, and depth
    // goes in before the chart marks so the marks draw over it — a buoy behind
    // a depth-area fill is a chart that lies about what is there.
    func insertAboveLand(_ slice: [[String: Any]]) {
        var layers = style["layers"] as! [[String: Any]]
        let anchor = layers.firstIndex { ($0["id"] as? String) == "station-clusters" } ?? layers.count
        layers.insert(contentsOf: slice, at: anchor)
        style["layers"] = layers
    }
    if let seascape = seascapeOfflineLayers() {
        sources["seascape-vector"] = seascape.source
        style["sources"] = sources
        insertAboveLand(seascape.layers)
    }
    if let seamap = seamapOfflineLayers() {
        sources["seamap"] = seamap.source
        style["sources"] = sources
        style["sprite"] = [["id": "freenauticalchart", "url": seamap.sprite]]
        insertAboveLand(seamap.layers)
    }
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
    private let killSwitch = CommandLine.arguments.contains("-networkKillSwitch")

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
        guard !killSwitch else { return }
        let imperial = UserDefaults.standard.string(forKey: unitsKey) != "metric"
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

    /// A filled square, drawn to equal AREA with the 5pt circle pins: for
    /// radius r the side is r·√π. A same-width square always reads heavier.
    /// Registered as a template image so `icon-color` can tint it — that is
    /// MapLibre Native's SDF path, and without it the pin ignores state.
    ///
    /// `inflate` grows the square on every side — how the tide pin gets the
    /// outline the circle gets from `circle-stroke-width`. MapLibre Native
    /// draws no `icon-halo-*` on this image at all: not a clipping problem
    /// (padding the canvas by the halo width changed nothing), the halo simply
    /// does not render here. So the outline is a second, larger square drawn
    /// underneath in `CHART_INK` — a backing plate, which a template image can
    /// express because the tint is per-layer.
    ///
    /// It only started mattering on pale water. An ink halo on ink-navy water
    /// was invisible either way, so the square has always drawn without one;
    /// on #e9f7ff it meant circles got a 16:1 outline and squares got none,
    /// leaving tide pins on fill contrast alone — the 2.65/1.97/2.11 that the
    /// stroke exists to fix.
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
