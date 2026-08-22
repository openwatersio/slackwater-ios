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

/// Style-build side: an empty GeoJSON source and one fill layer coloured per
/// feature, inserted UNDER the first pin layer so stations always draw over
/// the wash. Outline matches the fill so a cell's own triangulation seams
/// vanish while the outer certified/uncertified edge stays a hard step.
func addFillStyle(_ style: inout [String: Any]) {
    var sources = style["sources"] as? [String: Any] ?? [:]
    sources[CurrentFillRenderer.sourceID] = [
        "type": "geojson",
        "data": ["type": "FeatureCollection", "features": [] as [Any]],
    ]
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
    let landIdx = layers.firstIndex { ["land-usca", "land"].contains($0["id"] as? String ?? "") }
    let anchor = landIdx
        ?? layers.firstIndex { ($0["id"] as? String) == "station-clusters" }
        ?? layers.count
    layers.insert(layer, at: anchor)
    style["layers"] = layers
}

/// Owns the fill bundle and the refresh timer. One instance per `MapStyler`;
/// `attach` re-runs on every style load (fallback, then Seascape) because the
/// source object belongs to the style that loaded it.
final class CurrentFillRenderer {
    static let sourceID = "current-fill"

    private weak var map: MLNMapView?
    /// Strong on purpose — same MapLibre gotcha the particle spike hit: a
    /// source looked up out of a JSON-declared style is a fresh wrapper the
    /// style does NOT retain.
    private var source: MLNShapeSource?
    private var field: FillField?
    private var timer: Timer?
    private var evaluating = false

    deinit { timer?.invalidate() }

    func attach(to style: MLNStyle, map: MLNMapView) {
        self.map = map
        source = style.source(withIdentifier: Self.sourceID) as? MLNShapeSource
        if field == nil { field = FillField() }
        refresh()
        guard timer == nil, field != nil else { return }
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
        guard let field, !evaluating else { return }
        evaluating = true
        let when = appNow()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cells = field.cells(at: when)
            let features: [MLNPolygonFeature] = cells.map { cell in
                var coords = cell.polygon
                let f = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
                f.attributes = ["colour": fillColourHex(forSpeedKn: cell.speedKn),
                                "kn": cell.speedKn]
                return f
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.evaluating = false
                self.source?.shape = MLNShapeCollectionFeature(shapes: features)
            }
        }
    }
}
