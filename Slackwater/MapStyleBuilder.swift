// Slackwater — GPL v3. The map's palette and its style JSON, mirroring
// slackwater-web's mapStyle.ts: the bundled OSM land-polygons PMTiles under
// everything (offline floor), the bundled chart and bathymetry slices, every
// bundled station as a pin, and Seascape composed in when it can be fetched.
// MapLibre Native reads the same land.pmtiles artifact the web serves, via its
// built-in pmtiles:// support — one artifact, two renderers.
import Foundation

// MARK: - Style building (mirrors web mapStyle.ts)

private let LAND_TONE = "#f5ecd7"   // paper-chart cream
/// Seascape's own `background-color` — the flat tone its depth ramp settles
/// to past 50 m, not a hand-picked blue.
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
let PIN_RADIUS: Double = 5
/// One outline width for both pin kinds — the circle's `circle-stroke-width`
/// and the square's `icon-halo-width`, which is also the transparent margin
/// `squarePinImage` has to leave for that halo to have anywhere to draw. Three
/// literals that must agree or the two kinds stop reading as one system.
let PIN_HALO: Double = 1.5

// A pin's colour by state — literally the same expression on both pin
// layers, so kind (which layer a pin lands in) cannot influence colour.
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

private func landSource(_ landUrl: String) -> [String: Any] {
    ["type": "vector", "url": landUrl, "attribution": "© OpenStreetMap contributors"]
}

/// Two land tilesets, and the split is deliberate (see tools/build-land.sh).
/// `land-usca` is US+Canada z0-9 — the floor, so no bundled station can ever
/// open onto blank water. `land` is the Salish Sea at z0-14, drawn OVER it:
/// home water keeps its detail, and outside its bounds the source simply has
/// no tiles and the coarse floor shows through.
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
    ["id": "land-usca-coast", "type": "line", "source": "land-usca", "source-layer": "coast",
     "paint": COASTLINE],
    ["id": "land-coast", "type": "line", "source": "land", "source-layer": "coast",
     "paint": COASTLINE],
]

/// Cluster below this zoom, individual dots at and above it.
///
/// 6, not the default (maxzoom − 1), and the number is the whole point: the
/// discovery map opens at 7.35, so the Salish view every existing user knows
/// still shows individual, tappable stations. Clustering only takes over at
/// the regional-and-wider zooms where 3,125 separate dots are a grey smear
/// nobody can aim at.
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

/// SPIKE (openwatersio/seascape#121): a bundled offline PMTiles layer-set —
/// "seamap" (Open Waters Seamap chart marks + freenauticalchart sprite) or
/// "seascape" (bathymetry). `<name>.pmtiles` is a `pmtiles extract` clipped to
/// the Salish box; `<slice ?? name>-layers.json` is a verbatim slice of the
/// published style.json. The seamap slice keeps its `text-*` keys and draws
/// them with the bundled glyphs (#29); the seascape slice still ships
/// text-stripped (its text bakes in a unit — see tools/build-seascape.sh).
/// Returns nil when the resources aren't in the bundle, so main stays on the
/// land-only fallback.
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
    if currentFillEnabled() { addFillStyle(&style) }
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
func composeStyle(_ seascape: [String: Any], landUrl: String, uscaUrl: String,
                  arguments: [String] = CommandLine.arguments) -> [String: Any] {
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
    if currentFillEnabled(arguments: arguments) { addFillStyle(&style) }
    return style
}
