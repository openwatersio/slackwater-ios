// Slackwater — GPL v3. Static current speed and direction renderer. FillField
// and PatchField each populate one existing GeoJSON source with unchanged
// certified speed polygons plus centroid direction points. MapLibre draws the
// fill and map-aligned, collision-managed arrow symbols under the pins.
//
// Both fields are evaluated off-main on the existing one-minute cadence; the
// main thread assigns each completed shape collection once. Pan, zoom, and
// frame rendering perform no current-data computation or source replacement.
// The speed ramp remains Timeline.rampT → SN.speedRGB, with no green by
// construction. `-currentFillOff` omits the sources and layers in tests.
import CoreLocation
import Foundation
import MapLibre

/// On by default. `-currentFillOff` is a UI-test override.
func currentFillEnabled(arguments: [String] = CommandLine.arguments) -> Bool {
    !arguments.contains("-currentFillOff")
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

/// The runtime layers for both fill providers, coloured per feature, added
/// under the pin layers so stations always draw over the wash.
/// Patches draw DIRECTLY ABOVE the fill: "patch outranks backdrop" at the
/// mouth fringe is draw order and nothing else (grown-patches spec §5), and
/// feature order within one source does not guarantee paint order — layer
/// order does. Identical paint: one ramp, one opacity law, one no-green rule
/// for both providers. Each source also carries centroid direction points; a
/// symbol layer per source draws them as map-aligned, collision-managed
/// arrows above the wash.
func fillStyleLayers(fill: MLNShapeSource, patch: MLNShapeSource)
        -> (fill: MLNFillStyleLayer, patch: MLNFillStyleLayer,
            direction: MLNSymbolStyleLayer, patchDirection: MLNSymbolStyleLayer) {
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

    // Fills and direction points share one source, so each layer takes the
    // geometry it draws.
    func directionLayer(_ id: String, source: MLNShapeSource) -> MLNSymbolStyleLayer {
        let layer = MLNSymbolStyleLayer(identifier: id, source: source)
        layer.predicate = NSPredicate(mglJSONObject: ["==", ["geometry-type"], "Point"])
        layer.minimumZoomLevel = Float(CURRENT_DIRECTION_MIN_ZOOM)
        layer.iconImageName = NSExpression(forConstantValue: CurrentFillRenderer.directionImageID)
        layer.iconRotation = NSExpression(mglJSONObject: ["get", "bearing"])
        layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
        layer.iconPitchAlignment = NSExpression(forConstantValue: "map")
        layer.iconAllowsOverlap = NSExpression(forConstantValue: false)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: false)
        layer.iconPadding = NSExpression(forConstantValue: 8)
        layer.iconColor = NSExpression(forConstantValue: hexColor(CHART_INK))
        return layer
    }
    return (fillLayer, patchLayer,
            directionLayer(CurrentFillRenderer.directionLayerID, source: fill),
            directionLayer(CurrentFillRenderer.patchDirectionLayerID, source: patch))
}

/// Owns the fill bundle and the refresh timer. One instance per `MapStyler`;
/// `attach` re-runs on every style load because the
/// source object belongs to the style that loaded it.
final class CurrentFillRenderer {
    static let sourceID = "current-fill"
    static let patchSourceID = "current-fill-patches"
    static let directionLayerID = "current-directions"
    static let patchDirectionLayerID = "current-directions-patches"
    static let directionImageID = "current-direction-arrow"

    private weak var map: MLNMapView?
    private var source: MLNShapeSource?
    private var patchSource: MLNShapeSource?
    /// Both providers vend the same FillCell shape (the frozen seam); the
    /// grown patches simply land in their own source/layer. A pass whose
    /// certification collapsed (Deception) vends zero cells and costs nothing.
    private var field: FillField?
    private var patches: PatchField?
    private let dodd = DoddMapFlowProvider()
    private var timer: Timer?
    private var evaluating = false
    deinit {
        timer?.invalidate()
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
            style.addSource(fill)
            style.addSource(patch)
            let layers = fillStyleLayers(fill: fill, patch: patch)
            style.addLayer(layers.fill)
            style.addLayer(layers.patch)
            style.addLayer(layers.direction)
            style.addLayer(layers.patchDirection)
            source = fill
            patchSource = patch
        }
        if field == nil { field = FillField() }
        if patches == nil { patches = PatchField() }
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
        let dodd = self.dodd
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fillCells = field?.cells(at: when) ?? []
            let patchCells = patches?.cells(at: when) ?? []
            let fillFeatures = currentCellFeatures(
                fillCells, excludingDirectionsIn: patchCells)
            var patchFeatures = currentCellFeatures(patchCells)
            if let flow = dodd.flow(at: when) {
                patchFeatures.append(currentDirectionFeature(
                    at: flow.center, bearingDeg: flow.bearingDeg))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.evaluating = false
                self.source?.shape = MLNShapeCollectionFeature(shapes: fillFeatures)
                self.patchSource?.shape = MLNShapeCollectionFeature(shapes: patchFeatures)
            }
        }
    }
}
