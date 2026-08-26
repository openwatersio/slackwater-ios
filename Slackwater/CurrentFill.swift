// Slackwater — GPL v3. The current fill layer (#57 channel 1, graduation
// spec docs/superpowers/specs/2026-08-22-fill-graduation-design.md §2): the
// speed-only current fill. FillField's certified triangles, each coloured by
// the #97 speed ramp at its own evaluated speed, drawn under the land — the
// colour raster half of the two-channel render the composite spec adopted
// (2026-08-20-current-field-composite-design.md §1). Cells are drawn blocky,
// unsmoothed, per that spec: smoothing would repaint colour across the
// certification-mask edge.
//
// Mechanism mirrors the #57 particle spike: the style build gets an EMPTY
// GeoJSON source + one layer dict; everything live happens post-load on a
// timer. The ramp is SN.speedRampStops via Timeline.rampT — the strip's own
// transfer function, one meaning one value; no green by construction (#97
// ruling, spec §1 status block). Flag off, nothing is added anywhere.
import CoreLocation
import Foundation
import MapLibre

let currentFillKey = "showCurrentFill"

/// On by default (graduation spec §2). The stored toggle is the user's map
/// switch; `-currentFillOff` is the UI-test override, same pattern as
/// `-networkKillSwitch` — it wins over the stored value so a test's style
/// baseline can never depend on simulator state.
var currentFillEnabled: Bool {
    if CommandLine.arguments.contains("-currentFillOff") { return false }
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: currentFillKey) != nil else { return true }
    // bool(forKey:), not object as? Bool: a launch-argument value ("-showCurrentFill
    // NO") arrives as a STRING, which the cast rejects while AppStorage coerces —
    // the toggle read "off" and the layer still drew. bool(forKey:) coerces both.
    return defaults.bool(forKey: currentFillKey)
}

/// Re-evaluation cadence. Tidal speed moves at most ~a knot per half hour;
/// a minute keeps every cell's colour well inside one ramp step of truth.
let FILL_REFRESH_S: TimeInterval = 60.0

/// Opacity carries "how much is happening" on the pale chart: the #97 ramp
/// was tuned against the strip's dark ground, and at 55% flat its dark floor
/// made SLACK water the loudest thing on the map. Slow → whisper (but never
/// zero: certified coverage must stay visible against true no-data, spec §1),
/// fast → solid. Anchored on the ramp's own kn anchors.
let FILL_OPACITY_FLOOR = 0.18
let FILL_OPACITY_TOP = 0.65

/// The ramp colour for a speed, as a style-dict hex string. Composition of
/// the two shipped #97 pieces (Timeline.rampT → SN.speedRGB) — never a third
/// ramp implementation.
func fillColourHex(forSpeedKn kn: Double) -> String {
    let c = SN.speedRGB(Timeline.rampT(forSpeedKn: kn))
    return String(format: "#%02x%02x%02x", Int(c.r.rounded()), Int(c.g.rounded()), Int(c.b.rounded()))
}

/// The runtime layers for both fill providers and the streak channel,
/// coloured per feature, added under the pin layers so stations always draw
/// over the wash.
/// Patches draw DIRECTLY ABOVE the fill: "patch outranks backdrop" at the
/// mouth fringe is draw order and nothing else (grown-patches spec §5), and
/// feature order within one source does not guarantee paint order — layer
/// order does. Identical paint: one ramp, one opacity law, one no-green rule
/// for both providers. The streaks ride above both.
func fillStyleLayers(fill: MLNShapeSource, patch: MLNShapeSource, streaks: MLNShapeSource)
        -> (fill: MLNFillStyleLayer, patch: MLNFillStyleLayer,
            streakTail: MLNLineStyleLayer, streakHead: MLNCircleStyleLayer) {
    func configure(_ layer: MLNFillStyleLayer) {
        layer.fillColor = NSExpression(mglJSONObject: ["get", "colour"])
        // antialias false: adjacent triangles' antialiased half-covered edge
        // pixels sum under translucency and redraw the whole mesh as seams.
        // Off, interiors fuse; the outer certified/uncertified edge stays a
        // hard step (which the spec wants visible).
        layer.fillAntialiased = NSExpression(forConstantValue: false)
        layer.fillOpacity = NSExpression(mglJSONObject:
            ["interpolate", ["linear"], ["get", "kn"],
             0.5, FILL_OPACITY_FLOOR, 6, FILL_OPACITY_TOP])
    }
    let fillLayer = MLNFillStyleLayer(identifier: CurrentFillRenderer.sourceID, source: fill)
    let patchLayer = MLNFillStyleLayer(identifier: CurrentFillRenderer.patchSourceID, source: patch)
    configure(fillLayer)
    configure(patchLayer)

    // Tails and heads share one source, so each layer takes the geometry it
    // draws: a circle layer given a tail would dot every vertex of it.
    let tail = MLNLineStyleLayer(identifier: CurrentStreakAnimator.tailLayerID, source: streaks)
    tail.predicate = NSPredicate(mglJSONObject: ["==", ["geometry-type"], "LineString"])
    tail.minimumZoomLevel = Float(STREAK_MIN_ZOOM)
    tail.lineCap = NSExpression(forConstantValue: "round")
    tail.lineJoin = NSExpression(forConstantValue: "round")
    tail.lineColor = NSExpression(forConstantValue: hexColor(mapHex(SN.foamHex)))
    tail.lineWidth = NSExpression(forConstantValue: 2.0)
    tail.lineOpacity = NSExpression(forConstantValue: 0.8)

    let head = MLNCircleStyleLayer(identifier: CurrentStreakAnimator.headLayerID, source: streaks)
    head.predicate = NSPredicate(mglJSONObject: ["==", ["geometry-type"], "Point"])
    head.minimumZoomLevel = Float(STREAK_MIN_ZOOM)
    head.circleRadius = NSExpression(forConstantValue: 2.0)
    head.circleColor = NSExpression(mglJSONObject: ["get", "colour"])
    head.circleOpacity = NSExpression(forConstantValue: 0.9)

    return (fillLayer, patchLayer, tail, head)
}

/// Owns the fill bundle and the refresh timer. One instance per `MapStyler`;
/// `attach` re-runs on every style load because the
/// source object belongs to the style that loaded it.
final class CurrentFillRenderer {
    static let sourceID = "current-fill"
    static let patchSourceID = "current-fill-patches"

    private weak var map: MLNMapView?
    private var source: MLNShapeSource?
    private var patchSource: MLNShapeSource?
    /// Both providers vend the same FillCell shape (the frozen seam); the
    /// grown patches simply land in their own source/layer. A pass whose
    /// certification collapsed (Deception) vends zero cells and costs nothing.
    private var field: FillField?
    private var patches: PatchField?
    private var timer: Timer?
    private var evaluating = false
    private let streaks = CurrentStreakAnimator()

    deinit {
        timer?.invalidate()
        streaks.stop()
    }

    func attach(to style: MLNStyle, map: MLNMapView) {
        self.map = map
        // The basemap is a style URL this app does not own — the fill's
        // sources and layers go in through the runtime API, per style load.
        if let existing = style.source(withIdentifier: Self.sourceID) as? MLNShapeSource {
            source = existing
            patchSource = style.source(withIdentifier: Self.patchSourceID) as? MLNShapeSource
        } else {
            let fill = MLNShapeSource(identifier: Self.sourceID, shape: nil, options: nil)
            let patch = MLNShapeSource(identifier: Self.patchSourceID, shape: nil, options: nil)
            let streakSource = MLNShapeSource(identifier: CurrentStreakAnimator.sourceID,
                                              shape: nil, options: nil)
            style.addSource(fill)
            style.addSource(patch)
            style.addSource(streakSource)
            let layers = fillStyleLayers(fill: fill, patch: patch, streaks: streakSource)
            style.addLayer(layers.fill)
            style.addLayer(layers.patch)
            style.addLayer(layers.streakTail)
            style.addLayer(layers.streakHead)
            source = fill
            patchSource = patch
        }
        if field == nil { field = FillField() }
        if patches == nil { patches = PatchField() }
        streaks.attach(to: style, map: map, fillField: field, patchField: patches)
        refresh()
        guard timer == nil, field != nil || patches != nil else { return }
        let t = Timer(timeInterval: FILL_REFRESH_S, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Evaluate every shipped cell at the app clock and push one shape
    /// collection. No visibility cull — 13k triangles are nothing to the GL
    /// side, and evaluating them all means pan/zoom never needs a re-push.
    /// ponytail: full-region evaluate off-main; cull to bbox if profiling
    /// ever says the minute tick is felt.
    private func refresh() {
        guard field != nil || patches != nil, !evaluating else { return }
        evaluating = true
        let when = appNow()
        let field = self.field
        let patches = self.patches
        func features(_ cells: [FillCell]) -> [MLNPolygonFeature] {
            cells.map { cell in
                var coords = cell.polygon
                let f = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
                f.attributes = ["colour": fillColourHex(forSpeedKn: cell.speedKn),
                                "kn": cell.speedKn]
                return f
            }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fillFeatures = features(field?.cells(at: when) ?? [])
            let patchFeatures = features(patches?.cells(at: when) ?? [])
            DispatchQueue.main.async {
                guard let self else { return }
                self.evaluating = false
                self.source?.shape = MLNShapeCollectionFeature(shapes: fillFeatures)
                self.patchSource?.shape = MLNShapeCollectionFeature(shapes: patchFeatures)
            }
        }
    }
}
