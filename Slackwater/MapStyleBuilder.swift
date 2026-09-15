// Slackwater — GPL v3. The map's palette, and the runtime source and layers
// the app adds on top of the basemap: every bundled station as a
// pin, its colour the water's state. The paint expressions come from the same
// JSON specs slackwater-web's mapStyle.ts uses, so the two renderers cannot
// drift.
import MapLibre

// MARK: - Style building (mirrors web mapStyle.ts)

/// The style's constant ground — fiord's water fill, what the fill
/// contrast floor is measured against
/// (`testEveryPinFillClearsTheContrastFloorOnTheWaterTone`).
private let WATER_TONE = "#38435c"
/// The pin rim: fiord's own label-halo navy, so pins cast the same shadow
/// the basemap's text does. On this dark ground the rim is a SHADOW, not
/// the legibility guarantee — the fills are bright and carry the contrast
/// floor themselves (the test above), which is the inverse of the pale
/// satellite ground this map used to sit on.
let CHART_INK = "#152256"
// A pin's SHAPE is the state's grammar, its COLOUR the state's value — and
// neither is the station's kind. An arrow is water flowing toward its
// bearing (S-57 B-407.4's tidal-stream symbol), coloured by the #97 speed
// ramp — go-green at slack, still pointing its set, because the colour is
// what says "slack". A gauge is a tide: a bar filled to the height's place
// in the local cycle, coloured rising/falling by the flood/ebb tokens. A
// dot is a pin with nothing to draw: a derived gate's phase, or unknown
// (steel). `chs` is provenance, not kind — it draws whatever its state
// earns, same as NOAA.
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
/// The dot pin's radius, and the base every glyph is sized against.
let PIN_RADIUS: Double = 5
/// One rim width for every pin form — the dot's stroke, and the inflate
/// `pinGlyphImage` strokes each glyph's plate wider by.
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

/// The pin ramp's lift toward white — `SN.speedLabelColour`'s move for the
/// same dark ground, but 0.3 where the text uses a quarter: the red end
/// measures 2.89:1 on the water at 0.25 and 3.17:1 here, and the fill IS
/// the contrast now that the rim is a shadow. Uniform, so the ramp still
/// ranks speeds at a glance.
let PIN_RAMP_LIFT = 0.3

/// The map's ramp fill for a speed-bearing current pin: the #97 transfer
/// (the strip's own composition) lifted for the dark ground.
func pinRampHex(forSpeedKn kn: Double) -> String {
    let c = SN.speedRGB(Timeline.rampT(forSpeedKn: kn))
    let l = { (v: Double) -> Int in Int((v + (255 - v) * PIN_RAMP_LIFT).rounded()) }
    return String(format: "#%02x%02x%02x", l(c.r), l(c.g), l(c.b))
}

/// The pin shrink ramp's floor: below here every pin sits at its smallest,
/// and the data layer's decimation is what keeps the wide zooms legible.
let PIN_SHRINK_FROM = 6.0

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
private let LABEL_HALO = CHART_INK   // one shadow tone: pins' rim and text's halo

/// Below this zoom station names are noise: hundreds collide with each other
/// and with the basemap's own place labels, which they crowd off the map.
/// Until here the pins carry the story alone; the basemap's geography labels
/// get the ink back.
let LABEL_MIN_ZOOM = 9.5

/// Where station names join the readings — `locateZoom`, so the locate FAB
/// lands on a named harbor. (Readings start earlier, at `LABEL_MIN_ZOOM`,
/// and place ahead of names.)
let READOUT_MIN_ZOOM = locateZoom

/// The pin size ramp's two ends, as factors of the glyphs' drawn size. One
/// ramp for the dot radius, every icon scale, and the stroke, so the forms
/// keep reading as one system at every zoom. Two stops only; the
/// exponential base is what keeps pins lean through the label band and
/// saves the growth for the detail zooms.
let PIN_ZOOM_SHRINK = 0.4
let PIN_ZOOM_GROWTH = 1.8
let PIN_GROWTH_TO = stationZoom

func hexColor(_ hex: String) -> UIColor {
    let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// The pins' runtime source, EMPTY at style load. There is no world build
/// any more: `MapStyler` fills this from the camera's own visible set and
/// refills it as the camera moves, so the app never predicts tides for
/// stations nobody is looking at. Added per style load because the basemap
/// is a style URL this app does not own — the app's channels go in through
/// the runtime API, never into the style JSON.
func stationShapeSource() -> MLNShapeSource {
    MLNShapeSource(identifier: "stations", shape: nil, options: nil)
}

/// The pin layers, bottom to top. Expressions come from the same JSON specs
/// the web uses, converted via `mglJSONObject` so the two renderers cannot
/// drift on paint.
func stationPinLayers(source: MLNShapeSource) -> [MLNStyleLayer] {
    func e(_ json: Any) -> NSExpression { NSExpression(mglJSONObject: json) }
    let ink = NSExpression(forConstantValue: hexColor(CHART_INK))
    let font = NSExpression(forConstantValue: LABEL_FONT)
    // The zoom ramp, once per unit it applies to: radius and stroke in
    // points, icon scale as a factor of the image's own drawn size. Begin
    // and end state only; the 1.7 exponential holds marks near the small
    // end through the label band (≈0.65× at 9.5, ≈0.85× at 10.5) and
    // spends the growth approaching `stationZoom`.
    func grown(_ base: Double) -> NSExpression {
        e(["interpolate", ["exponential", 1.7], ["zoom"],
           PIN_SHRINK_FROM, base * PIN_ZOOM_SHRINK,
           PIN_GROWTH_TO, base * PIN_ZOOM_GROWTH])
    }

    // The selected pin's halo: a soft ring under every pin layer, revealed
    // by `MapViewRepresentable` swapping this layer's predicate to the
    // picked station's id while the preview panel is up. Default: nothing.
    let selected = MLNCircleStyleLayer(identifier: "station-selected", source: source)
    // Matches nothing — no station has an empty id. NOT NSPredicate(value:):
    // MapLibre's predicate converter throws on constant predicates.
    selected.predicate = NSPredicate(mglJSONObject: ["==", ["get", "id"], ""])
    // The Nearby map's focus-ring language: a leaf stroke, nothing filled —
    // a disc of any tone reads as a blob on the dark ground.
    selected.circleRadius = grown(PIN_RADIUS * 2.6)
    selected.circleOpacity = NSExpression(forConstantValue: 0)
    selected.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
    selected.circleStrokeColor = NSExpression(forConstantValue: UIColor(SN.leaf))

    // Each glyph's outline (see `pinGlyphImage`): the same glyph stroked
    // wider in ink, drawn underneath, because `icon-halo-*` does not render
    // on these images. Plates are not in the tap layers — `handleTap`
    // hit-tests the glyph layers, and a plate that answered too would return
    // the same feature twice.
    // The near band's placement contract, tier one of three (see the return
    // below): allow-overlap TRUE so a glyph is never hidden, ignore-placement
    // FALSE so every glyph REGISTERS its space — that registration is what
    // makes it impossible for any text, placed later, to sit on a glyph.
    func glyph(_ id: String, image: NSExpression, rotation: NSExpression,
               colour: NSExpression, predicate: NSPredicate,
               scale: NSExpression? = nil) -> MLNSymbolStyleLayer {
        let layer = MLNSymbolStyleLayer(identifier: id, source: source)
        layer.predicate = predicate
        layer.iconImageName = image
        layer.iconScale = scale ?? grown(1)
        layer.iconRotation = rotation
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: false)
        layer.iconColor = colour
        return layer
    }
    let upright = NSExpression(forConstantValue: 0)
    let dotted = NSPredicate(mglJSONObject:
        ["all", ["!", ["has", "bearing"]], ["!", ["has", "gauge"]]])
    let flowing = NSPredicate(mglJSONObject: ["has", "bearing"] as [Any])
    let gauged = NSPredicate(mglJSONObject: ["has", "gauge"] as [Any])
    let setRotation = e(["get", "bearing"])

    // The near band (labels and up): plate + glyph, everything drawn. The
    // stateless dot — a derived gate's phase words, unknown steel — is a
    // glyph like the rest, so the far band below can collide it.
    let dotPlate = glyph("station-pins-dot-plate",
                         image: NSExpression(forConstantValue: "pin-dot-plate"),
                         rotation: upright, colour: ink, predicate: dotted)
    let dots = glyph("station-pins-dot",
                     image: NSExpression(forConstantValue: "pin-dot"),
                     rotation: upright, colour: e(PIN_STATE_COLOUR), predicate: dotted)

    // A flowing current IS an arrow toward its set (S-57 B-407.4), filled
    // with the ramp at its speed. Map-aligned: the bearing is geographic.
    let currentPinPlate = glyph("station-pins-current-plate",
                                image: NSExpression(forConstantValue: "pin-arrow-plate"),
                                rotation: setRotation, colour: ink, predicate: flowing)
    let currentPins = glyph("station-pins-current",
                            image: NSExpression(forConstantValue: "pin-arrow"),
                            rotation: setRotation, colour: e(PIN_STATE_COLOUR), predicate: flowing)

    // A resolved tide IS a gauge: the plate draws the barrel (its rim and
    // its dark empty band), the fill layer stacks the per-bucket level on
    // top, coloured rising/falling by the same state the reading arrows
    // carry. tide and chs both land here — provenance is not kind.
    // The plate matches the fill's trend so barrel and caret share one
    // silhouette; the fill layer's image name carries its trend already.
    let tidePinPlate = glyph("station-pins-tide-plate",
                             image: e(["match", ["get", "state"],
                                       "rising", "pin-gauge-plate-up", "pin-gauge-plate-down"]),
                             rotation: upright, colour: ink, predicate: gauged)
    let tidePins = glyph("station-pins-tide", image: e(["get", "gauge"]),
                         rotation: upright, colour: e(PIN_STATE_COLOUR), predicate: gauged)
    // One band, every zoom. Density is settled in the DATA now — the source
    // only ever holds the camera's own decimated set (`visibleStations`), so
    // there is no longer a wide-zoom band that needs its own plate-less,
    // collision-thinned copy of every layer.
    for layer in [currentPins, currentPinPlate] {
        layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
    }

    // The glyphs keep growing toward the station zoom while an em offset
    // One caption dressing for both text tiers — basemap label paint,
    // priority sort, and a shared size ramp — so the two cannot drift.
    func caption(_ id: String, text: NSExpression) -> MLNSymbolStyleLayer {
        let layer = MLNSymbolStyleLayer(identifier: id, source: source)
        layer.symbolSortKey = e(["get", "sort"])
        layer.text = text
        layer.textFontNames = font
        layer.textFontSize = e(["interpolate", ["linear"], ["zoom"],
                                LABEL_MIN_ZOOM, 11, PIN_GROWTH_TO, 13])
        layer.textColor = NSExpression(forConstantValue: hexColor(LABEL_TEXT))
        layer.textHaloColor = NSExpression(forConstantValue: hexColor(LABEL_HALO))
        layer.textHaloWidth = NSExpression(forConstantValue: 1)
        return layer
    }

    // Tier three, strictly space-permitting AND a zoom later than the
    // readings: names place last, under full collision with generous
    // padding — a name appears only where it crowds nothing, and yields
    // everywhere else. The offset grows with the glyphs (a constant had
    // names creeping onto the gauges as zoom rose), and its 1.4em base is
    // what clears the name's own glyph box plus both paddings — tighter
    // and every name self-collides and vanishes.
    let labels = caption("station-labels", text: e(["get", "name"]))
    labels.minimumZoomLevel = Float(READOUT_MIN_ZOOM)
    labels.textOffset = e(["interpolate", ["linear"], ["zoom"],
                           LABEL_MIN_ZOOM, ["literal", [0, 1]],
                           PIN_GROWTH_TO, ["literal", [0, 2.4]]])
    labels.textAnchor = NSExpression(forConstantValue: "top")
    labels.textPadding = NSExpression(forConstantValue: 4)

    // The station's reading ("3.2 ft" / "1.8 kn") — tier two, and the ONLY
    // text in the 9.5–10.5 band. Several candidate slots per station, tried
    // in order, so a reading blocked on one side takes another before
    // giving up; readings place before names, so a reading that needs a
    // slot takes it FROM the name.
    //
    // One layer per glyph shape, because `textRadialOffset` spends a SINGLE
    // distance in whichever direction the chosen anchor points: a radius
    // that clears the gauge's height would stand an arrow's reading a
    // glyph-height out in open water, and one that hugs the arrow drops
    // the gauge's reading into its own bar. Each layer's radius tracks its
    // own glyph's growth.
    func readingLayer(_ id: String, anchors: [String],
                      from: Double, to: Double) -> MLNSymbolStyleLayer {
        let layer = caption(id, text: e(["get", "reading"]))
        layer.minimumZoomLevel = Float(LABEL_MIN_ZOOM)
        layer.textVariableAnchor = NSExpression(forConstantValue: anchors)
        layer.textRadialOffset = e(["interpolate", ["linear"], ["zoom"],
                                    LABEL_MIN_ZOOM, from, PIN_GROWTH_TO, to])
        layer.textJustification = NSExpression(forConstantValue: "auto")
        return layer
    }
    // A gauge is three times taller than it is wide, so its reading sits
    // BESIDE the bar (the Navionics idiom) — close in, on whichever flank
    // is free.
    let tideReadings = readingLayer("station-readings-tide", anchors: ["left", "right"],
                                    from: 0.7, to: 1.0)
    tideReadings.predicate = gauged
    // An arrow is nearly square: all four slots cost about the same, so it
    // keeps them all and takes the first that is free.
    let flowReadings = readingLayer("station-readings", anchors: ["bottom", "top", "left", "right"],
                                    from: 0.9, to: 1.5)
    flowReadings.predicate = NSPredicate(mglJSONObject:
        ["all", ["has", "reading"], ["!", ["has", "gauge"]]])

    // The placement hierarchy. MapLibre places symbols in REVERSE style
    // order — the LAST layer claims space first — so the priority runs from
    // the end of this array backwards: glyphs claim first (always drawn,
    // always registered), readings route around them, names take whatever
    // is left. The same order stacks glyphs above any text in draw order,
    // so even a stray overlap keeps the symbol on top.
    return [selected, labels, flowReadings, tideReadings,
            dotPlate, dots, currentPinPlate, currentPins,
            tidePinPlate, tidePins]
}
