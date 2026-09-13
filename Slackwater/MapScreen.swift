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
    private func pinGlyphImage(_ path: UIBezierPath, bounds: CGSize,
                               inflate: CGFloat = 0, scale: CGFloat = 3) -> UIImage {
        let size = CGSize(width: bounds.width + inflate * 2, height: bounds.height + inflate * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: inflate, y: inflate)
            UIColor.white.setFill()
            UIColor.white.setStroke()
            path.fill()
            guard inflate > 0 else { return }
            path.lineWidth = inflate * 2
            path.lineJoinStyle = .round
            path.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// The tide trend glyph: a triangle pointing up, at equal AREA with the
    /// r=`PIN_RADIUS` dot; the falling state rotates it 180°.
    private func trianglePinImage(inflate: CGFloat = 0) -> UIImage {
        let side = CGFloat(PIN_RADIUS) * 2 * (CGFloat.pi / sqrt(3)).squareRoot()
        let height = side * sqrt(3) / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: side / 2, y: 0))
        path.addLine(to: CGPoint(x: side, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.close()
        return pinGlyphImage(path, bounds: CGSize(width: side, height: height), inflate: inflate)
    }

    /// The flowing-current glyph: a chunky north-pointing arrow (S-57 draws a
    /// tidal stream as an arrow in the direction of flow — B-407.4); the
    /// layer rotates it to the set. Head-heavy on purpose: at dot sizes the
    /// head is what survives.
    private func arrowPinImage(inflate: CGFloat = 0) -> UIImage {
        let w: CGFloat = 12, h: CGFloat = 17, shaft: CGFloat = 5, head: CGFloat = 9
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w, y: head))
        path.addLine(to: CGPoint(x: (w + shaft) / 2, y: head))
        path.addLine(to: CGPoint(x: (w + shaft) / 2, y: h))
        path.addLine(to: CGPoint(x: (w - shaft) / 2, y: h))
        path.addLine(to: CGPoint(x: (w - shaft) / 2, y: head))
        path.addLine(to: CGPoint(x: 0, y: head))
        path.close()
        return pinGlyphImage(path, bounds: CGSize(width: w, height: h), inflate: inflate)
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
        style.setImage(trianglePinImage(), forName: "pin-triangle")
        style.setImage(trianglePinImage(inflate: CGFloat(PIN_HALO)), forName: "pin-triangle-plate")
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
        applyChsStates(to: style)
    }

    /// Issue #12: colour the CHS pins from what the offline sync has ALREADY
    /// stored. Runs here, per style load, because that is the only place it
    /// can survive: setting a style rebuilds every source, discarding anything
    /// pushed into the old one. After paint by construction, so the style-construction path
    /// `testPinLayerBuildsInsideAFrame` budgets pays nothing; the 3,125-pin
    /// source rebuild runs off the main thread. Cache only, never a fetch —
    /// `chsPinStates` takes the stored records and nothing else.
    private func applyChsStates(to style: MLNStyle) {
        Task { @MainActor [weak style] in
            let service = ChsFitService.shared
            let tides = service.tideRecords
            let currents = service.currentRecords
            let geojson = await Task.detached(priority: .utility) { () -> Data? in
                let states = chsPinStates(at: appNow(), tideRecords: tides, currentRecords: currents)
                guard !states.isEmpty else { return nil }   // nothing synced — neutral is honest
                let geojson = PinFeaturesCache.shared.update(states: states)
                return try? JSONSerialization.data(withJSONObject: geojson)
            }.value
            guard let geojson, let style,
                  let source = style.source(withIdentifier: "stations") as? MLNShapeSource,
                  let shape = try? MLNShape(data: geojson, encoding: String.Encoding.utf8.rawValue)
            else { return }
            source.shape = shape
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
    /// A tap that hit open water (or a cluster) instead of a pin — the
    /// preview card's dismissal path.
    var onDeselect: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onMiss: onMiss, onDeselect: onDeselect)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        // Top-right, clear of the FAB row and the locate button; white so it
        // reads on the dark basemap.
        map.attributionButtonPosition = .topRight
        map.attributionButton.tintColor = .white
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
            if let id = nearest(["station-pins-current", "station-pins-tide",
                                 "station-pins-dot"])?.attribute(forKey: "id") as? String,
               let item = StationItem.byId[id] {
                onSelect(item)
                return
            }
            onDeselect()
            guard let cluster = nearest(["station-clusters"]) else {
                // Before the style loads nothing framed the camera, so its zoom means nothing.
                onMiss?(map.style == nil ? stationZoom : map.zoomLevel)
                return
            }
            // +2 levels lands past CLUSTER_MAX_ZOOM from any clustered zoom, so
            // one tap on a cluster always breaks it into something tappable.
            map.setCenter(cluster.coordinate, zoomLevel: min(map.zoomLevel + 2, 12), animated: true)
        }
    }
}
