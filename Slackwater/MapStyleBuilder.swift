// Slackwater — GPL v3. The map's palette, and the runtime source and layers
// the app adds on top of the satellite basemap: every bundled station as a
// pin, its colour the water's state. The paint expressions come from the same
// JSON specs slackwater-web's mapStyle.ts uses, so the two renderers cannot
// drift.
import MapLibre

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
let PIN_RADIUS: Double = 5
/// One outline width for both pin kinds — the circle's `circle-stroke-width`
/// and the square's `icon-halo-width`, which is also the transparent margin
/// `squarePinImage` has to leave for that halo to have anywhere to draw. Three
/// literals that must agree or the two kinds stop reading as one system.
let PIN_HALO: Double = 1.5

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

/// Cluster below this zoom, individual dots at and above it.
///
/// 6, not the default (maxzoom − 1), and the number is the whole point: the
/// discovery map opens at 7.35, so the Salish view every existing user knows
/// still shows individual, tappable stations. Clustering only takes over at
/// the regional-and-wider zooms where 3,125 separate dots are a grey smear
/// nobody can aim at.
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
