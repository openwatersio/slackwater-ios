// Slackwater — GPL v3. The discovery map: its camera, the MapLibre delegate
// that loads the basemap style and re-registers the app's own runtime
// layers, and the tap-to-detail view hosting it.
import SwiftUI
import MapLibre

// Discovery-map camera: frames the bundled-station core (Puget Sound through
// the Gulf Islands / Strait of Georgia) so it opens reading as the Salish Sea.
// The UI pin-tap test derives screen points from these same constants.
let SALISH_CENTER = CLLocationCoordinate2D(latitude: 48.35, longitude: -123.05)
let SALISH_ZOOM = 7.35

/// Per-station framing (prototype DATA() z: 12.2–13.2). The detail header's
/// title tap (issue #32) jumps to the discovery map at this zoom, so a focused
/// jump lands framed on one station rather than on the whole Salish Sea.
let stationZoom = 12.5

/// Where the locate FAB lands: past `LABEL_MIN_ZOOM` so "where am I" comes
/// answered with named stations, wider than `stationZoom`'s single-station
/// frame — a harbor, not a dot.
let locateZoom = 10.5

/// How much of the map's height the preview panel covers, for the selection
/// camera: handle + card + paddings + margin over the home indicator.
/// ponytail: a constant, not a measured layout — retune if the card grows.
let previewPanelCover: CGFloat = 240

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

// The map draws in place behind the list ⇄ map toggle FAB
// (StationListView.mapPane), not in a full-screen cover of its own.

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
    private let framing: [CLLocationCoordinate2D]?
    private let fill = currentFillEnabled() ? CurrentFillRenderer() : nil
    private var refreshTimer: Timer?
    deinit { refreshTimer?.invalidate() }

    init(map: MLNMapView, center: CLLocationCoordinate2D, zoom: Double,
         framing: [CLLocationCoordinate2D]? = nil) {
        self.map = map
        self.center = center
        self.zoom = zoom
        self.framing = framing
        super.init()
        map.delegate = self
        map.styleURL = BASEMAP_STYLE_URL
    }

    /// A pin glyph as a white template image, so `icon-color` can tint it per
    /// feature (MapLibre Native's SDF path; without it the pin ignores state).
    /// GOTCHA: Native draws no `icon-halo-*` on these images at all, so the
    /// ink outline is a PLATE — the same path stroked `inflate` wider, drawn
    /// underneath by its own layer in `CHART_INK`.
    /// `rounding` strokes the filled path that much wider with round joins —
    /// the cheap way to round a silhouette's corners (the gauge caret's
    /// tips) without re-deriving the path.
    private func pinGlyphImage(_ path: UIBezierPath, bounds: CGSize,
                               inflate: CGFloat = 0, rounding: CGFloat = 0,
                               scale: CGFloat = 3) -> UIImage {
        let pad = inflate + rounding / 2
        let size = CGSize(width: bounds.width + pad * 2, height: bounds.height + pad * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: pad, y: pad)
            UIColor.white.setFill()
            UIColor.white.setStroke()
            path.fill()
            let strokeWidth = rounding + inflate * 2
            guard strokeWidth > 0 else { return }
            path.lineWidth = strokeWidth
            path.lineJoinStyle = .round
            path.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// A glyph drawn as a stroke rather than a fill (the arrow): the plate
    /// is the same stroke `inflate` wider on each side, so the shadow rim
    /// hugs the line work.
    private func strokedGlyphImage(_ path: UIBezierPath, bounds: CGSize,
                                   lineWidth: CGFloat, inflate: CGFloat = 0,
                                   scale: CGFloat = 3) -> UIImage {
        let size = CGSize(width: bounds.width + inflate * 2, height: bounds.height + inflate * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: inflate, y: inflate)
            UIColor.white.setStroke()
            path.lineWidth = lineWidth + inflate * 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// The stateless dot, drawn as a glyph like the other two forms.
    private func dotPinImage(inflate: CGFloat = 0) -> UIImage {
        let d = CGFloat(PIN_RADIUS) * 2
        let path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: d, height: d))
        return pinGlyphImage(path, bounds: CGSize(width: d, height: d), inflate: inflate)
    }

    /// The tide gauge glyph: a slim barrel with a trend caret — above the
    /// bar pointing up when rising, below it pointing down when falling
    /// (the Navionics tide-bar idiom), gapped off the barrel so it reads as
    /// a pointer rather than an arched cap. Every variant shares one canvas
    /// so the icons center-align; the bar hugs the far end from the caret.
    private static let gaugeBar = CGSize(width: 5.5, height: 15)
    /// The caret matches the colored level's width — which IS the bar's,
    /// now that the level is drawn full width — so pointer and level read
    /// as one element.
    private static let gaugeCaretWidth: CGFloat = gaugeBar.width
    private static let gaugeCaretHeight: CGFloat = 3.2
    /// Sized so the two COLOURED shapes end up exactly one rim apart — the
    /// dark band between bar and caret reads as the same shadow that wraps
    /// the rest of the glyph. (Their plates do overlap at this distance, so
    /// the shadow is one continuous column; that is what it should be, and
    /// with the caret as wide as the bar there is no notch where they
    /// meet. Pushing them far enough apart for open background between the
    /// plates costs two rims of dark and reads as a chasm.)
    private static let gaugeCaretGap: CGFloat = gaugeRim + gaugeRounding / 2
    private static let gaugeCanvas = CGSize(
        width: gaugeBar.width, height: gaugeBar.height + gaugeCaretGap + gaugeCaretHeight)
    private static let gaugeCorner: CGFloat = 1.2
    /// The corner-softening stroke both gauge images share (see
    /// `pinGlyphImage`'s `rounding`) — the caret's tips round like the
    /// barrel's ends.
    private static let gaugeRounding: CGFloat = 0.6
    /// The shadow rim's visible thickness, uniform around the whole glyph:
    /// the plate is the silhouette grown by this much, and the fill is the
    /// silhouette at nominal size, so bar and caret wear the SAME rim.
    /// (Insetting the level inside the bar instead left a 2pt rim there
    /// against the caret's 1pt.) `inflate` is a stroke, so it spends half
    /// its width outward — hence the doubling, less what `rounding` already
    /// grows the silhouette by.
    private static let gaugeRim: CGFloat = 1.6
    private static let gaugeRimInflate: CGFloat = gaugeRim - gaugeRounding / 2

    private func gaugeBarFrame(rising: Bool) -> CGRect {
        CGRect(x: (Self.gaugeCanvas.width - Self.gaugeBar.width) / 2,
               y: rising ? Self.gaugeCanvas.height - Self.gaugeBar.height : 0,
               width: Self.gaugeBar.width, height: Self.gaugeBar.height)
    }

    private func gaugeCaretPath(rising: Bool) -> UIBezierPath {
        let mid = Self.gaugeCanvas.width / 2
        let left = mid - Self.gaugeCaretWidth / 2
        let right = mid + Self.gaugeCaretWidth / 2
        let h = Self.gaugeCaretHeight
        let path = UIBezierPath()
        if rising {
            path.move(to: CGPoint(x: mid, y: 0))
            path.addLine(to: CGPoint(x: right, y: h))
            path.addLine(to: CGPoint(x: left, y: h))
        } else {
            let top = Self.gaugeCanvas.height - h
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: mid, y: Self.gaugeCanvas.height))
        }
        path.close()
        return path
    }

    /// The gauge barrel and its caret as ONE silhouette, registered inflated
    /// in the shadow ink as the plate — the filled interior doubles as the
    /// empty portion of the barrel, so low water reads as a dark bar, not a
    /// hole.
    private func gaugeBarrelImage(rising: Bool, inflate: CGFloat = 0) -> UIImage {
        let path = UIBezierPath(roundedRect: gaugeBarFrame(rising: rising),
                                cornerRadius: Self.gaugeCorner)
        path.append(gaugeCaretPath(rising: rising))
        return pinGlyphImage(path, bounds: Self.gaugeCanvas, inflate: inflate,
                             rounding: Self.gaugeRounding)
    }

    /// One fill level per bucket, anchored at the barrel's bottom, plus the
    /// trend caret so both tint together in the state colour. A 2pt floor
    /// keeps low water visible as a sliver rather than an empty bar. Drawn
    /// at the barrel's OWN width — the rim comes from the plate underneath
    /// (see `gaugeRim`), never from insetting the level.
    private func gaugeFillImage(bucket: Int, rising: Bool) -> UIImage {
        let bar = gaugeBarFrame(rising: rising)
        let fraction = Double(bucket) / Double(PIN_GAUGE_BUCKETS)
        let height = max(2, bar.height * fraction)
        let path = UIBezierPath(
            roundedRect: CGRect(x: bar.minX, y: bar.maxY - height,
                                width: bar.width, height: height),
            cornerRadius: Self.gaugeCorner)
        path.append(gaugeCaretPath(rising: rising))
        return pinGlyphImage(path, bounds: Self.gaugeCanvas,
                             rounding: Self.gaugeRounding)
    }

    /// The flowing-current glyph, per S-57's tidal-stream arrow (B-407.4):
    /// a stroked shaft with a chevron head — round caps, and a head kept
    /// smaller than the system symbol's, which read all head at pin sizes.
    /// The layer rotates it to the set.
    private func arrowPinImage(inflate: CGFloat = 0) -> UIImage {
        let w: CGFloat = 10, h: CGFloat = 13, head: CGFloat = 3.6, cap: CGFloat = 1.2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w / 2, y: h - cap))
        path.addLine(to: CGPoint(x: w / 2, y: cap))
        path.move(to: CGPoint(x: w / 2 - head, y: cap + head))
        path.addLine(to: CGPoint(x: w / 2, y: cap))
        path.addLine(to: CGPoint(x: w / 2 + head, y: cap + head))
        return strokedGlyphImage(path, bounds: CGSize(width: w, height: h),
                                 lineWidth: 2.3, inflate: inflate)
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        if let framing {
            mapView.setVisibleCoordinateBounds(centeredBounds(around: center, fitting: framing),
                                               edgePadding: UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32),
                                               animated: false, completionHandler: nil)
        } else {
            mapView.setCenter(center, zoomLevel: zoom, animated: false)
        }
        // Fires on every style load — everything runtime-added (images,
        // sources, layers) belongs to the style that loaded, so it all
        // re-registers here or a style swap loses it.
        style.setImage(dotPinImage(), forName: "pin-dot")
        style.setImage(dotPinImage(inflate: CGFloat(PIN_HALO)), forName: "pin-dot-plate")
        // The gauge's rim is its own constant (`gaugeRim`): the barrel is a
        // filled slab already, and the dot's and arrow's full rim reads fat
        // on one.
        for (trend, rising) in [("up", true), ("down", false)] {
            style.setImage(gaugeBarrelImage(rising: rising, inflate: Self.gaugeRimInflate),
                           forName: "pin-gauge-plate-\(trend)")
            for bucket in 0...PIN_GAUGE_BUCKETS {
                style.setImage(gaugeFillImage(bucket: bucket, rising: rising),
                               forName: "pin-gauge-\(bucket)-\(trend)")
            }
        }
        style.setImage(arrowPinImage(), forName: "pin-arrow")
        style.setImage(arrowPinImage(inflate: CGFloat(PIN_HALO)), forName: "pin-arrow-plate")
        style.setImage(currentDirectionImage(),
                       forName: CurrentFillRenderer.directionImageID)
        // Fill under the pins: added first, so the pin layers appended below
        // land on top of it.
        fill?.attach(to: style, map: mapView)
        // The framed map's own station, ringed under its pin.
        if framing != nil, style.source(withIdentifier: "focus") == nil {
            let point = MLNPointFeature()
            point.coordinate = center
            let source = MLNShapeSource(identifier: "focus", shape: point, options: nil)
            style.addSource(source)
            let ring = MLNCircleStyleLayer(identifier: "focus-ring", source: source)
            ring.circleRadius = NSExpression(forConstantValue: 13)
            ring.circleOpacity = NSExpression(forConstantValue: 0)
            ring.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            ring.circleStrokeColor = NSExpression(forConstantValue: UIColor(SN.leaf))
            style.addLayer(ring)
        }
        if style.source(withIdentifier: "stations") == nil {
            let source = stationShapeSource()
            style.addSource(source)
            for layer in stationPinLayers(source: source) { style.addLayer(layer) }
        }
        refreshPins(force: true)
        // A mounted map outlives many state buckets, and a camera that never
        // moves never asks for a rebuild — without this, a map left open
        // wears the states it mounted with (a card saying "Flooding" beside
        // a pin still green from the morning's slack).
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: PIN_REFRESH_S, repeats: true) { [weak self] _ in
            self?.refreshPins(force: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// The camera settled: rebuild the pins if it has left what was built
    /// for. Fires on idle, never mid-gesture.
    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        refreshPins()
    }

    /// What the last build covered, so a pan inside it costs nothing.
    private var builtBox: PinBox?
    private var builtZoom: Double?
    private var building = false

    /// Rebuild the visible set when the camera has moved off what is built —
    /// out of the padded box, or far enough in zoom to change which stations
    /// survive decimation (or which of them draw a gauge).
    private func refreshPins(force: Bool = false) {
        guard let map, let style = map.style else { return }
        let bounds = map.visibleCoordinateBounds
        let view = PinBox(south: bounds.sw.latitude, west: bounds.sw.longitude,
                          north: bounds.ne.latitude, east: bounds.ne.longitude)
        let zoom = map.zoomLevel
        if !force, !building, let built = builtBox, let builtZoom,
           built.covers(view), abs(builtZoom - zoom) < PIN_ZOOM_SLACK,
           (builtZoom >= LABEL_MIN_ZOOM) == (zoom >= LABEL_MIN_ZOOM) { return }
        guard !building else { return }
        building = true

        let box = view.padded(by: PIN_VIEWPORT_PAD)
        Task { @MainActor [weak self, weak style] in
            let service = ChsFitService.shared
            let tides = service.tideRecords
            let currents = service.currentRecords
            let geojson = await Task.detached(priority: .utility) { () -> Data? in
                let items = visibleStations(in: box, zoom: zoom)
                let now = appNow()
                // CHS pins take their state from what the offline sync has
                // ALREADY stored — cache only, never a fetch (issue #12; the
                // web port learned the fetch-on-open version is a request
                // storm against IWLS).
                let states = chsPinStates(at: now, items: items, detailed: zoom >= LABEL_MIN_ZOOM,
                                          tideRecords: tides, currentRecords: currents)
                let geojson = pinFeatures(for: items, zoom: zoom, chsStates: states, now: now)
                return try? JSONSerialization.data(withJSONObject: geojson)
            }.value
            self?.building = false
            guard let geojson, let style,
                  let source = style.source(withIdentifier: "stations") as? MLNShapeSource,
                  let shape = try? MLNShape(data: geojson, encoding: String.Encoding.utf8.rawValue)
            else { return }
            source.shape = shape
            self?.builtBox = box
            self?.builtZoom = zoom
        }
    }

}

/// The smallest bounds centred on `center` that hold every point, so fitting
/// them keeps the station mid-frame.
private func centeredBounds(around center: CLLocationCoordinate2D,
                            fitting points: [CLLocationCoordinate2D]) -> MLNCoordinateBounds {
    // ponytail: plain longitude differences, so a neighbour across the
    // antimeridian (western Aleutians) over-widens the frame; wrap if it shows.
    let dLat = points.map { abs($0.latitude - center.latitude) }.max() ?? 0
    let dLon = points.map { abs($0.longitude - center.longitude) }.max() ?? 0
    return MLNCoordinateBounds(
        sw: CLLocationCoordinate2D(latitude: center.latitude - dLat, longitude: center.longitude - dLon),
        ne: CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude + dLon))
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
    /// A detail's Nearby preview: frame these stations around a ringed
    /// `center` instead of using `zoom`, with pan and zoom off so the page
    /// around it still scrolls.
    var framing: [CLLocationCoordinate2D]? = nil
    /// A tap on no pin, handed the zoom on screen.
    var onMiss: ((Double) -> Void)? = nil
    /// The previewed station: its pin wears the `station-selected` halo and
    /// the camera centers it in the strip the panel leaves visible.
    var selected: StationItem?
    let onSelect: (StationItem) -> Void
    /// A tap that hit open water instead of a pin — the preview card's
    /// dismissal path.
    var onDeselect: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onMiss: onMiss, onDeselect: onDeselect)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        // Top-right, clear of the FAB row and the locate button; white so it
        // reads on the dark basemap. Margins match the FAB row's 16pt edge
        // inset so the ⓘ sits on the same gutter line as the buttons below.
        map.attributionButtonPosition = .topRight
        map.attributionButton.tintColor = .white
        map.attributionButtonMargins = CGPoint(x: 16, y: 16)
        // The MapLibre wordmark is optional under its BSD license; the ⓘ
        // button stays — it is where the tile attribution lives.
        map.showsLogoView = false
        // North-up, top-down only: the discovery map is a chart, not a fly-
        // through, and every readout is placed for that camera.
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = LocationService.shared.authorized
        if framing != nil {
            map.isScrollEnabled = false
            map.isZoomEnabled = false
            map.isRotateEnabled = false
            map.isPitchEnabled = false
        }
        context.coordinator.install(on: map, center: center, zoom: zoom, framing: framing)
        return map
    }

    /// Camera changes arrive as remounts — `mapPane` sets `.id(mapFocusToken)`
    /// so a header-title focus rebuilds the view and `makeUIView` frames it.
    /// Selection is the exception: it must move the LIVE camera (a remount
    /// would rebuild the whole style under the preview panel).
    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.apply(selection: selected)
    }

    final class Coordinator: NSObject {
        let onSelect: (StationItem) -> Void
        let onMiss: ((Double) -> Void)?
        let onDeselect: () -> Void
        private weak var map: MLNMapView?
        private var styler: MapStyler?

        init(onSelect: @escaping (StationItem) -> Void, onMiss: ((Double) -> Void)?,
             onDeselect: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onMiss = onMiss
            self.onDeselect = onDeselect
        }

        func install(on map: MLNMapView, center: CLLocationCoordinate2D, zoom: Double,
                     framing: [CLLocationCoordinate2D]?) {
            self.map = map
            styler = MapStyler(map: map, center: center, zoom: zoom, framing: framing)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            map.addGestureRecognizer(tap)
        }

        /// The preview selection: light the picked pin's halo, and pan it to
        /// the center of the strip the panel leaves visible. The pan offsets
        /// `setCenter` by half the panel's coverage rather than setting
        /// `contentInset` — an inset shifts the ornaments and goes stale when
        /// the panel is swiped away without the map hearing about it.
        private var selectedId: String?
        func apply(selection item: StationItem?) {
            guard item?.id != selectedId, let map else { return }
            selectedId = item?.id
            if let halo = map.style?.layer(withIdentifier: "station-selected") as? MLNVectorStyleLayer {
                // Empty id matches nothing; see the layer's default predicate.
                halo.predicate = NSPredicate(mglJSONObject: ["==", ["get", "id"], item?.id ?? ""])
            }
            guard let item else { return }
            let pin = map.convert(CLLocationCoordinate2D(latitude: item.latitude,
                                                         longitude: item.longitude),
                                  toPointTo: map)
            let target = CGPoint(x: pin.x, y: pin.y + previewPanelCover / 2)
            map.setCenter(map.convert(target, toCoordinateFrom: map), animated: true)
        }

        /// Tap → nearest station pin within a finger-sized box → preview.
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
            if let id = nearest(["station-pins-current", "station-pins-tide",
                                 "station-pins-dot"])?.attribute(forKey: "id") as? String,
               let item = StationItem.byId[id] {
                onSelect(item)
                return
            }
            onDeselect()
            // Before the style loads nothing framed the camera, so its zoom means nothing.
            onMiss?(map.style == nil ? stationZoom : map.zoomLevel)
        }
    }
}
