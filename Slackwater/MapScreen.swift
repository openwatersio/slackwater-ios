// Slackwater — GPL v3. The discovery map: its camera, the MapLibre delegate
// that loads and re-loads the style, and the tap-to-detail view hosting it.
import SwiftUI
import MapLibre

// Discovery-map camera: frames the bundled-station core (Puget Sound through
// the Gulf Islands / Strait of Georgia) so it opens reading as the Salish Sea.
// The UI pin-tap test derives screen points from these same constants.
let SALISH_CENTER = CLLocationCoordinate2D(latitude: 48.35, longitude: -123.05)
let SALISH_ZOOM = 7.35

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

/// Loads the fallback style immediately and Seascape when its fetch lands
/// (web MapScreen, Open Waters offline.md: no error banner — the map renders
/// what it can reach), and re-asserts the camera after each style load. The
/// camera must be asserted post-layout: a zoomLevel set on a zero-frame view
/// converts through a degenerate altitude and the map opened continent-wide.
final class MapStyler: NSObject, MLNMapViewDelegate {
    private weak var map: MLNMapView?
    private let cacheName: String
    private let center: CLLocationCoordinate2D
    private let zoom: Double
    private let fill = currentFillEnabled() ? CurrentFillRenderer() : nil

    init(map: MLNMapView, cacheName: String, center: CLLocationCoordinate2D, zoom: Double) {
        self.map = map
        self.cacheName = cacheName
        self.center = center
        self.zoom = zoom
        super.init()
        map.delegate = self
        setStyle(localFallbackStyle(landUrl: landUrl, uscaUrl: uscaUrl), name: "\(cacheName)-fallback")
        fetchSeascape()
    }

    private func pmtilesUrl(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pmtiles") else { return "" }
        return "pmtiles://\(url.absoluteString)"  // pmtiles://file:///…/land.pmtiles
    }

    private var landUrl: String { pmtilesUrl("land") }
    private var uscaUrl: String { pmtilesUrl("land-usca") }

    /// MLN loads styles by URL — write the composed JSON next to the caches.
    private func setStyle(_ style: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: style),
              let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        let url = dir.appendingPathComponent("map-style-\(name).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        DispatchQueue.main.async { self.map?.styleURL = url }
    }

    private func fetchSeascape() {
        guard !networkKillSwitch else { return }
        // Not .standard: Settings' unit toggle now writes to the App Group
        // (H2), so a plain .standard read here would freeze at whatever the
        // one-time migration copied and never see a later change.
        let imperial = AppGroup.defaults.string(forKey: unitsKey) != "metric"
        guard let url = URL(string: "https://tiles.openwaters.io/seascape/style.json?unit=\(imperial ? "ft" : "m")")
        else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self, let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }  // offline or upstream down: the fallback style is already up
            self.setStyle(composeStyle(json, landUrl: self.landUrl, uscaUrl: self.uscaUrl),
                          name: "\(self.cacheName)-seascape")
        }.resume()
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

    // ponytail: re-asserts on every style load, so a Seascape arriving late
    // recenters a user who already panned; track interaction if it annoys.
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        mapView.setCenter(center, zoomLevel: zoom, animated: false)
        // Fires on every style load (local fallback, then Seascape) — the
        // tide-pin icon must be re-registered each time or the swap loses it.
        style.setImage(squarePinImage(), forName: "pin-square")
        style.setImage(squarePinImage(inflate: CGFloat(PIN_HALO)), forName: "pin-square-plate")
        style.setImage(currentDirectionImage(),
                       forName: CurrentFillRenderer.directionImageID)
        applyChsTones(to: style)
        fill?.attach(to: style, map: mapView)
    }

    /// Issue #12: colour the CHS pins from what the offline sync has ALREADY
    /// stored. Runs here, per style load, because that is the only place it
    /// can survive: setting a style rebuilds every source, discarding anything
    /// pushed into the old one — and this map styles twice (fallback, then
    /// Seascape). After paint by construction, so the style-construction path
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
    let onSelect: (StationItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.attributionButtonPosition = .bottomLeft
        map.logoViewPosition = .bottomLeft
        map.showsUserLocation = LocationService.shared.authorized
        context.coordinator.install(on: map, center: center, zoom: zoom)
        return map
    }

    /// Camera changes arrive as remounts — `mapPane` sets `.id(mapFocusToken)`
    /// so a header-title focus rebuilds the view and `makeUIView` frames it.
    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject {
        let onSelect: (StationItem) -> Void
        private weak var map: MLNMapView?
        private var styler: MapStyler?

        init(onSelect: @escaping (StationItem) -> Void) { self.onSelect = onSelect }

        func install(on map: MLNMapView, center: CLLocationCoordinate2D, zoom: Double) {
            self.map = map
            styler = MapStyler(map: map, cacheName: "discovery",
                               center: center, zoom: zoom)
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
            guard let cluster = nearest(["station-clusters"]) else { return }
            // +2 levels lands past CLUSTER_MAX_ZOOM from any clustered zoom, so
            // one tap on a cluster always breaks it into something tappable.
            map.setCenter(cluster.coordinate, zoomLevel: min(map.zoomLevel + 2, 12), animated: true)
        }
    }
}
