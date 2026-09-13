// Slackwater — GPL v3. The map's palette, and the runtime source and layers
// the app adds on top of the basemap: every bundled station as a
// pin, its colour the water's state. The paint expressions come from the same
// JSON specs slackwater-web's mapStyle.ts uses, so the two renderers cannot
// drift.
import MapLibre

// MARK: - Style building (mirrors web mapStyle.ts)

/// The style's constant ground — fiord's water fill, what the outline
/// contrast floor is measured against
/// (`testEveryPinOutlineClearsTheContrastFloorOnTheWaterTone`).
private let WATER_TONE = "#38435c"
/// Pin fills answer "what is the water doing", not "can you see me" — the
/// contrast lives on the stroke: every pin carries this outline (circles as
/// a stroke, glyphs as a backing plate), asserted against `WATER_TONE`
/// above. Light, because fiord's ground is dark — on this chart the ink is
/// white.
let CHART_INK = "#ffffff"
// A pin's SHAPE is the state's grammar, its COLOUR the state's value — and
// neither is the station's kind. An arrow is water flowing toward its
// bearing (S-57 B-407.4's tidal-stream symbol), coloured by the #97 speed
// ramp. A triangle is a tide trend — up rising, down falling — coloured by
// the flood/ebb tokens. A dot is a pin with no direction to draw: slack
// (go-green), a derived gate's phase, or unknown (steel). `chs` is
// provenance, not kind — it draws whatever its state earns, same as NOAA.
/// MapLibre style dicts hold strings, so the palette crosses over as
/// "#rrggbb" — always derived from the `SN` hex, never hand-copied (a copy is
/// silent drift no test catches).
func mapHex(_ hex: UInt32) -> String { String(format: "#%06x", hex) }

/// Zero: the map draws the SAME hues the app's own cards and strip do —
/// darkened map-only variants read as a muddy third palette next to them.
/// Legibility on any ground is the ink outline/plate's job (the water-tone
/// floor test), not the fill's; the knob stays because it is the first thing
/// to reach for if a real device says otherwise.
let PIN_STATE_DARKEN = 0.0
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

/// Zero, same argument as `PIN_STATE_DARKEN`: the arrow's fill is the #97
/// ramp exactly as the strip composes it, so a speed on the map and the same
/// speed on the strip are one colour; the arrow's ink plate carries the
/// ground contrast.
let PIN_RAMP_DARKEN = 0.0

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
/// labels use (fiord ships exactly one), so offline packs cache its glyph
/// ranges as part of the basemap's needs and runtime labels ride along.
private let LABEL_FONT = ["Noto Sans Regular"]

/// Station label and readout paint: the basemap's own label treatment
/// (fiord: pale text on a navy hsl(228,60%,21%) halo, width 1), so names
/// read as part of the style rather than stickers on it — white where
/// fiord's places are pale blue-grey, because the stations are the content
/// here.
private let LABEL_TEXT = "#ffffff"
private let LABEL_HALO = "#152256"

/// Below this zoom station names are noise: hundreds collide with each other
/// and with the basemap's own place labels, which they crowd off the map.
/// Until here the pins carry the story alone; the basemap's geography labels
/// get the ink back.
let LABEL_MIN_ZOOM = 9.5

/// Where the readouts (height + trend, speed + flow arrow) join the names —
/// `locateZoom`, so the locate FAB lands on a stateful harbor, and past
/// `LABEL_MIN_ZOOM`, so a reading never floats without its name.
let READOUT_MIN_ZOOM = locateZoom

/// The pin size ramp's two ends, as factors of `PIN_RADIUS`. One ramp for
/// the circle radius, the square's icon scale, and the stroke, so the two
/// kinds keep reading as one system at every zoom.
///
/// Shrunk at the cluster handoff (`CLUSTER_MAX_ZOOM`): the discovery zooms
/// show whole coastlines, where full-sized pins fuse into a quilt of
/// touching squares — a dense shore has to read as dots. Full size where
/// the labels arrive (`LABEL_MIN_ZOOM`), and growing past it to
/// `stationZoom`, where a pin is the subject of the frame and earns
/// dot-marker weight.
let PIN_ZOOM_SHRINK = 0.4
let PIN_ZOOM_GROWTH = 1.8
let PIN_GROWTH_TO = stationZoom

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
    let ink = NSExpression(forConstantValue: hexColor(CHART_INK))
    let halo = NSExpression(forConstantValue: PIN_HALO)
    let font = NSExpression(forConstantValue: LABEL_FONT)
    // The zoom ramp, once per unit it applies to: radius and stroke in
    // points, icon scale as a factor of the image's own PIN_RADIUS sizing.
    func grown(_ base: Double) -> NSExpression {
        e(["interpolate", ["linear"], ["zoom"],
           Double(CLUSTER_MAX_ZOOM), base * PIN_ZOOM_SHRINK,
           LABEL_MIN_ZOOM, base,
           PIN_GROWTH_TO, base * PIN_ZOOM_GROWTH])
    }

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

    // The selected pin's halo: a soft ring under every pin layer, revealed
    // by `MapViewRepresentable` swapping this layer's predicate to the
    // picked station's id while the preview panel is up. Default: nothing.
    let selected = MLNCircleStyleLayer(identifier: "station-selected", source: source)
    // Matches nothing — no station has an empty id. NOT NSPredicate(value:):
    // MapLibre's predicate converter throws on constant predicates.
    selected.predicate = NSPredicate(mglJSONObject: ["==", ["get", "id"], ""])
    selected.circleRadius = grown(PIN_RADIUS * 2.4)
    selected.circleColor = ink
    selected.circleOpacity = NSExpression(forConstantValue: 0.3)
    selected.circleStrokeWidth = NSExpression(forConstantValue: 2)
    selected.circleStrokeColor = ink

    // The stateless pin: no bearing to point, no trend to show — slack
    // currents (go-green), a derived gate's phase words, and unknown (steel).
    let dots = MLNCircleStyleLayer(identifier: "station-pins-dot", source: source)
    dots.predicate = NSPredicate(mglJSONObject:
        ["all", ["!", ["has", "point_count"]], ["!", ["has", "bearing"]],
         ["!=", ["get", "state"], "rising"], ["!=", ["get", "state"], "falling"]])
    dots.circleRadius = grown(PIN_RADIUS)
    dots.circleColor = e(PIN_STATE_COLOUR)
    dots.circleStrokeWidth = grown(PIN_HALO)
    dots.circleStrokeColor = ink

    // Each glyph's outline (see `pinGlyphImage`): the same glyph stroked
    // wider in ink, drawn underneath, because `icon-halo-*` does not render
    // on these images. Plates are not in the tap layers — `handleTap`
    // hit-tests the glyph layers, and a plate that answered too would return
    // the same feature twice.
    func glyph(_ id: String, image: String, rotation: NSExpression,
               colour: NSExpression, predicate: NSPredicate) -> MLNSymbolStyleLayer {
        let layer = MLNSymbolStyleLayer(identifier: id, source: source)
        layer.predicate = predicate
        layer.iconImageName = NSExpression(forConstantValue: image)
        layer.iconScale = grown(1)
        layer.iconRotation = rotation
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        layer.iconColor = colour
        return layer
    }

    // A flowing current IS an arrow toward its set (S-57 B-407.4), filled
    // with the ramp at its speed. Map-aligned: the bearing is geographic.
    let flowing = NSPredicate(mglJSONObject:
        ["all", ["!", ["has", "point_count"]], ["has", "bearing"]])
    let setRotation = e(["get", "bearing"])
    let currentPinPlate = glyph("station-pins-current-plate", image: "pin-arrow-plate",
                                rotation: setRotation, colour: ink, predicate: flowing)
    let currentPins = glyph("station-pins-current", image: "pin-arrow",
                            rotation: setRotation, colour: e(PIN_STATE_COLOUR), predicate: flowing)
    for layer in [currentPinPlate, currentPins] {
        layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
    }

    // A resolved tide IS a trend triangle: up rising, down falling — the
    // rotation reads the same state the colour does, so the two cannot
    // disagree. tide and chs both land here — provenance is not kind.
    let trending = NSPredicate(mglJSONObject:
        ["all", ["!", ["has", "point_count"]],
         ["any", ["==", ["get", "state"], "rising"], ["==", ["get", "state"], "falling"]]])
    let trendRotation = e(["match", ["get", "state"], "falling", 180, 0])
    let tidePinPlate = glyph("station-pins-tide-plate", image: "pin-triangle-plate",
                             rotation: trendRotation, colour: ink, predicate: trending)
    let tidePins = glyph("station-pins-tide", image: "pin-triangle",
                         rotation: trendRotation, colour: e(PIN_STATE_COLOUR), predicate: trending)

    let labels = MLNSymbolStyleLayer(identifier: "station-labels", source: source)
    labels.predicate = notACluster
    labels.minimumZoomLevel = Float(LABEL_MIN_ZOOM)
    labels.text = e(["get", "name"])
    labels.textFontNames = font
    labels.textFontSize = e(["interpolate", ["linear"], ["zoom"],
                             LABEL_MIN_ZOOM, 11, 13, 13])
    labels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.1)))
    labels.textAnchor = NSExpression(forConstantValue: "top")
    labels.textOptional = NSExpression(forConstantValue: true)
    labels.textColor = NSExpression(forConstantValue: hexColor(LABEL_TEXT))
    labels.textHaloColor = NSExpression(forConstantValue: hexColor(LABEL_HALO))
    labels.textHaloWidth = NSExpression(forConstantValue: 1)

    // The station's reading ("3.2 ft ↑" / "1.8 kn"), above the pin where the
    // name sits below — same basemap label paint. Only pins whose state
    // resolved one carry the attribute; unknown stays a bare pin.
    let readings = MLNSymbolStyleLayer(identifier: "station-readings", source: source)
    readings.predicate = NSPredicate(mglJSONObject:
        ["all", ["!", ["has", "point_count"]], ["has", "reading"]])
    readings.minimumZoomLevel = Float(READOUT_MIN_ZOOM)
    readings.text = e(["get", "reading"])
    readings.textFontNames = font
    readings.textFontSize = NSExpression(forConstantValue: 11)
    readings.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -1.1)))
    readings.textAnchor = NSExpression(forConstantValue: "bottom")
    readings.textColor = NSExpression(forConstantValue: hexColor(LABEL_TEXT))
    readings.textHaloColor = NSExpression(forConstantValue: hexColor(LABEL_HALO))
    readings.textHaloWidth = NSExpression(forConstantValue: 1)

    return [clusters, counts, selected, dots, currentPinPlate, currentPins,
            tidePinPlate, tidePins, labels, readings]
}
