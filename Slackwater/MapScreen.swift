// Slackwater — GPL v3. The discovery map: its camera, the MapLibre delegate
// that loads the satellite style and re-registers the app's own runtime
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

    /// A filled square at equal AREA with the 5pt circle pins (side r·√π —
    /// same-width reads heavier). Template image so `icon-color` can tint it
    /// (MapLibre Native's SDF path; without it the pin ignores state).
    /// GOTCHA: Native draws no `icon-halo-*` on this image at all, so the
    /// outline is `inflate` — a larger backing square drawn underneath in
    /// `CHART_INK`.
    private func squarePinImage(radius: CGFloat = CGFloat(PIN_RADIUS),
                                inflate: CGFloat = 0, scale: CGFloat = 3) -> UIImage {
        let side = radius * CGFloat(Double.pi.squareRoot()) + inflate * 2
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.withRenderingMode(.alwaysTemplate)
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
        style.setImage(squarePinImage(), forName: "pin-square")
        style.setImage(squarePinImage(inflate: CGFloat(PIN_HALO)), forName: "pin-square-plate")
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
        applyChsTones(to: style)
    }

    /// Issue #12: colour the CHS pins from what the offline sync has ALREADY
    /// stored. Runs here, per style load, because that is the only place it
    /// can survive: setting a style rebuilds every source, discarding anything
    /// pushed into the old one. After paint by construction, so the style-construction path
    /// `testPinLayerBuildsInsideAFrame` budgets pays nothing; the 3,125-pin
    /// source rebuild runs off the main thread. Cache only, never a fetch —
    /// `chsPinTones` takes the stored records and nothing else.
    private func applyChsTones(to style: MLNStyle) {
        Task { @MainActor [weak style] in
            let service = ChsFitService.shared
            let tides = service.tideRecords
            let currents = service.currentRecords
            let geojson = await Task.detached(priority: .utility) { () -> Data? in
                let tones = chsPinTones(at: appNow(), tideRecords: tides, currentRecords: currents)
                guard !tones.isEmpty else { return nil }   // nothing synced — neutral is honest
                let geojson = PinFeaturesCache.shared.update(tones: tones)
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
    let onSelect: (StationItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onMiss: onMiss) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.attributionButtonPosition = .bottomLeft
        map.logoViewPosition = .bottomLeft
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
    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject {
        let onSelect: (StationItem) -> Void
        let onMiss: ((Double) -> Void)?
        private weak var map: MLNMapView?
        private var styler: MapStyler?

        init(onSelect: @escaping (StationItem) -> Void, onMiss: ((Double) -> Void)?) {
            self.onSelect = onSelect
            self.onMiss = onMiss
        }

        func install(on map: MLNMapView, center: CLLocationCoordinate2D, zoom: Double,
                     framing: [CLLocationCoordinate2D]?) {
            self.map = map
            styler = MapStyler(map: map, center: center, zoom: zoom, framing: framing)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            map.addGestureRecognizer(tap)
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
            if let id = nearest(["station-pins-current", "station-pins-tide"])?.attribute(forKey: "id") as? String,
               let item = StationItem.byId[id] {
                onSelect(item)
                return
            }
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
