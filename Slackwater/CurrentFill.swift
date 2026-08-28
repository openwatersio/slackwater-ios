// Slackwater — GPL v3. Static current speed and direction renderer. FillField
// and PatchField each populate one existing GeoJSON source with unchanged
// certified speed polygons plus centroid direction points. MapLibre draws the
// fill and map-aligned, collision-managed arrow symbols below land.
//
// Both fields are evaluated off-main on the existing one-minute cadence; the
// main thread assigns each completed shape collection once. Pan, zoom, and
// frame rendering perform no current-data computation or source replacement.
// The speed ramp remains Timeline.rampT → SN.speedRGB, with no green by
// construction. `-currentFillOff` omits the sources and layers in tests.
import CoreLocation
import Foundation
import MapLibre

/// On by default (graduation spec §2). `-currentFillOff` is a UI-test override.
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

/// Style-build side: two empty GeoJSON sources with fill and direction layers
/// below land. Outline matches the fill so a cell's own triangulation seams
/// vanish while the outer certified/uncertified edge stays a hard step.
func addFillStyle(_ style: inout [String: Any]) {
    var sources = style["sources"] as? [String: Any] ?? [:]
    let empty: [String: Any] = [
        "type": "geojson",
        "data": ["type": "FeatureCollection", "features": [] as [Any]],
    ]
    sources[CurrentFillRenderer.sourceID] = empty
    sources[CurrentFillRenderer.patchSourceID] = empty
    style["sources"] = sources
    let layer: [String: Any] = [
        "id": CurrentFillRenderer.sourceID, "type": "fill",
        "source": CurrentFillRenderer.sourceID,
        // antialias false: adjacent triangles' antialiased half-covered edge
        // pixels sum under translucency and redraw the whole mesh as seams.
        // Off, interiors fuse; the outer certified/uncertified edge stays a
        // hard step (which the spec wants visible).
        "paint": ["fill-color": ["get", "colour"],
                  "fill-antialias": false,
                  "fill-opacity": ["interpolate", ["linear"], ["get", "kn"],
                                   0.5, FILL_OPACITY_FLOOR,
                                   6, FILL_OPACITY_TOP]],
    ]
    var layers = style["layers"] as? [[String: Any]] ?? []
    // Under the LAND, not just under the pins: SSCOFS elements legitimately
    // cross the shoreline, and land drawn over the fill clips them to water
    // for free — no geometry clipping. ponytail: if the depth relief above
    // proves opaque enough to bury the fill, this anchor moves back up.
    // Patches draw DIRECTLY ABOVE the fill: "patch outranks backdrop" at the
    // mouth fringe is draw order and nothing else (grown-patches spec §5),
    // and feature order within one source does not guarantee paint order —
    // layer order does. Same paint dict: one ramp, one opacity law, one
    // no-green rule for both providers.
    var patch = layer
    patch["id"] = CurrentFillRenderer.patchSourceID
    patch["source"] = CurrentFillRenderer.patchSourceID
    let direction: [String: Any] = [
        "id": CurrentFillRenderer.directionLayerID,
        "type": "symbol",
        "source": CurrentFillRenderer.sourceID,
        "minzoom": CURRENT_DIRECTION_MIN_ZOOM,
        "filter": ["==", ["geometry-type"], "Point"],
        "layout": [
            "icon-image": CurrentFillRenderer.directionImageID,
            "icon-rotate": ["get", "bearing"],
            "icon-rotation-alignment": "map",
            "icon-pitch-alignment": "map",
            "icon-allow-overlap": false,
            "icon-ignore-placement": false,
            "icon-padding": 8,
        ],
        "paint": [
            "icon-color": mapHex(SN.foamHex),
        ],
    ]
    var patchDirection = direction
    patchDirection["id"] = CurrentFillRenderer.patchDirectionLayerID
    patchDirection["source"] = CurrentFillRenderer.patchSourceID
    let landIdx = layers.firstIndex { ["land-usca", "land"].contains($0["id"] as? String ?? "") }
    let anchor = landIdx
        ?? layers.firstIndex { ($0["id"] as? String) == "station-clusters" }
        ?? layers.count
    layers.insert(contentsOf: [layer, patch, direction, patchDirection], at: anchor)
    style["layers"] = layers
}

/// Owns the fill bundle and the refresh timer. One instance per `MapStyler`;
/// `attach` re-runs on every style load (fallback, then Seascape) because the
/// source object belongs to the style that loaded it.
final class CurrentFillRenderer {
    static let sourceID = "current-fill"
    static let patchSourceID = "current-fill-patches"
    static let directionLayerID = "current-directions"
    static let patchDirectionLayerID = "current-directions-patches"
    static let directionImageID = "current-direction-arrow"

    private weak var map: MLNMapView?
    /// Strong on purpose — same MapLibre gotcha the particle spike hit: a
    /// source looked up out of a JSON-declared style is a fresh wrapper the
    /// style does NOT retain.
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
        source = style.source(withIdentifier: Self.sourceID) as? MLNShapeSource
        patchSource = style.source(withIdentifier: Self.patchSourceID) as? MLNShapeSource
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
