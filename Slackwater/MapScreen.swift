// Slackwater — GPL v3. M4 simple pin map, mirroring slackwater-web
// (MapScreen.tsx + mapStyle.ts): the bundled OSM land-polygons PMTiles under
// everything (offline floor), Seascape's style composed in when it can be
// fetched, every bundled station as a pin, tap → detail. MapLibre Native
// reads the same land.pmtiles artifact the web serves, via its built-in
// pmtiles:// support — one artifact, two renderers.
import SwiftUI
import MapLibre

// Discovery-map camera: frames the bundled-station core (Puget Sound through
// the Gulf Islands / Strait of Georgia) so it opens reading as the Salish Sea.
// The UI pin-tap test derives screen points from these same constants.
let SALISH_CENTER = CLLocationCoordinate2D(latitude: 48.35, longitude: -123.05)
let SALISH_ZOOM = 7.35

/// UI-test hook, like `-openMap`: `-mapZoom 3.2` opens the discovery map at a
/// stated zoom. Synthesised pinches are not a camera — five of them land
/// somewhere the test cannot name, which is no way to screenshot "continental".
let discoveryZoom: Double = {
    guard let at = CommandLine.arguments.firstIndex(of: "-mapZoom"),
          CommandLine.arguments.indices.contains(at + 1),
          let zoom = Double(CommandLine.arguments[at + 1]) else { return SALISH_ZOOM }
    return zoom
}()

// The MapScreen full-screen-cover wrapper (header + X) is gone — M4.5 shows
// the map in place behind the list ⇄ map toggle FAB (StationListView.mapPane).

// MARK: - Style building (mirrors web mapStyle.ts)

private let LAND_TONE = "#f5ecd7"   // paper-chart cream
private let WATER_TONE = "#0b1a2b"  // navy water
// A pin's COLOUR is the water's state, never the station's kind — kind is the
// pin's SHAPE: a circle for a current station, a square for a tide one. One
// shape per feature class, the oldest convention on any chart, and a silhouette
// difference reads where an interior one does not.
//
// `chs` is a Canadian tide port. That is provenance, not kind — it draws the
// same square a NOAA tide station does.
private let PIN_NEUTRAL = "#7d9cb8"

/// Every bundled station as a GeoJSON pin. Identity only — no readings.
private func pinFeatures() -> [String: Any] {
    [
        "type": "FeatureCollection",
        "features": StationItem.all.map { s in
            [
                "type": "Feature",
                "geometry": ["type": "Point", "coordinates": [s.longitude, s.latitude]],
                "properties": ["id": s.id, "name": s.name, "kind": s.pinKind],
            ] as [String: Any]
        },
    ]
}

private func landSource(_ landUrl: String) -> [String: Any] {
    ["type": "vector", "url": landUrl, "attribution": "© OpenStreetMap contributors"]
}

/// Two land tilesets, and the split is the M53 basemap decision (see
/// tools/build-land.sh). `land-usca` is US+Canada z0-9 — the floor, so no
/// bundled station can ever open onto blank water. `land` is the Salish Sea at
/// z0-14, drawn OVER it: home water keeps its detail, and outside its bounds
/// the source simply has no tiles and the coarse floor shows through.
private func landSources(_ landUrl: String, _ uscaUrl: String) -> [String: Any] {
    ["land": landSource(landUrl), "land-usca": landSource(uscaUrl)]
}

private let landLayers: [[String: Any]] = [
    ["id": "land-usca", "type": "fill", "source": "land-usca", "source-layer": "land",
     "paint": ["fill-color": LAND_TONE]],
    ["id": "land", "type": "fill", "source": "land", "source-layer": "land",
     "paint": ["fill-color": LAND_TONE]],
]

/// Cluster below this zoom, individual dots at and above it.
///
/// 6, not the default (maxzoom − 1), and the number is the whole point: the
/// discovery map opens at 7.35, so the Salish view every existing user knows
/// still shows individual, tappable stations. Clustering only takes over at
/// the regional-and-wider zooms where 3,125 separate dots are a grey smear
/// nobody can aim at (M53).
private let CLUSTER_MAX_ZOOM = 6

/// Every bundled station as a clustered GeoJSON source.
private func stationSource() -> [String: Any] {
    [
        "type": "geojson", "data": pinFeatures(),
        "cluster": true, "clusterMaxZoom": CLUSTER_MAX_ZOOM, "clusterRadius": 46,
    ]
}

private func pinLayers(hasGlyphs: Bool, labelFont: [String]) -> [[String: Any]] {
    let notACluster: [Any] = ["!", ["has", "point_count"]]
    let clusters: [String: Any] = [
        "id": "station-clusters", "type": "circle", "source": "stations",
        "filter": ["has", "point_count"] as [Any],
        "paint": [
            // Area, roughly, with the count — so a 400-station cluster reads
            // as bigger than a 5-station one without swallowing the coast.
            "circle-radius": ["interpolate", ["linear"], ["get", "point_count"],
                              2, 11, 25, 16, 150, 22, 600, 30] as [Any],
            "circle-color": PIN_NEUTRAL,
            "circle-opacity": 0.82,
            "circle-stroke-width": 1.5,
            "circle-stroke-color": WATER_TONE,
        ],
    ]
    let currentPins: [String: Any] = [
        "id": "station-pins-current", "type": "circle", "source": "stations",
        "filter": ["all", notACluster, ["==", ["get", "kind"], "current"]] as [Any],
        "paint": [
            "circle-radius": 5,
            "circle-color": PIN_NEUTRAL,
            "circle-stroke-width": 1.5,
            "circle-stroke-color": WATER_TONE,
        ],
    ]
    // tide and chs are both tide stations — provenance is not kind.
    let tidePins: [String: Any] = [
        "id": "station-pins-tide", "type": "symbol", "source": "stations",
        "filter": ["all", notACluster, ["!=", ["get", "kind"], "current"]] as [Any],
        "layout": [
            "icon-image": "pin-square",
            "icon-allow-overlap": true,
            "icon-ignore-placement": true,
        ],
        "paint": [
            "icon-color": PIN_NEUTRAL,
            "icon-halo-color": WATER_TONE,
            "icon-halo-width": 1.5,
        ],
    ]
    // Labels need glyphs — the local fallback declares none, so it's pins only
    // (same decisive signal as the web). A cluster with no number on it is a
    // blob, so the cluster layer is glyphless-safe by the same rule.
    guard hasGlyphs else { return [clusters, currentPins, tidePins] }
    let counts: [String: Any] = [
        "id": "station-cluster-count", "type": "symbol", "source": "stations",
        "filter": ["has", "point_count"] as [Any],
        "layout": [
            "text-field": ["get", "point_count_abbreviated"] as [Any],
            "text-font": labelFont,
            "text-size": 12,
            "text-allow-overlap": true,
        ],
        "paint": ["text-color": WATER_TONE],
    ]
    let labels: [String: Any] = [
        "id": "station-labels", "type": "symbol", "source": "stations",
        "filter": notACluster,
        "layout": [
            "text-field": ["get", "name"] as [Any],
            "text-font": labelFont,
            "text-size": 11,
            "text-offset": [0, 1.1],
            "text-anchor": "top",
            "text-optional": true,
        ],
        "paint": ["text-color": "#e8e4d8", "text-halo-color": WATER_TONE, "text-halo-width": 1],
    ]
    return [clusters, counts, currentPins, tidePins, labels]
}

/// Offline / style-fetch-failed: land + pins, honestly bare (web localFallbackStyle).
func localFallbackStyle(landUrl: String, uscaUrl: String) -> [String: Any] {
    var sources = landSources(landUrl, uscaUrl)
    sources["stations"] = stationSource()
    return [
        "version": 8,
        "sources": sources,
        "layers": [
            ["id": "land-bg", "type": "background", "paint": ["background-color": WATER_TONE]],
        ] + landLayers + pinLayers(hasGlyphs: false, labelFont: []),
    ]
}

// Layer types this MapLibre Native release renders. Seascape's style leans on
// GL-JS-v5 `color-relief` (depth shading), which native rejects — filtered
// out, so online adds contours/soundings/labels but not the shaded relief.
private let nativeLayerTypes: Set<String> = [
    "background", "fill", "line", "symbol", "circle", "raster",
    "fill-extrusion", "heatmap", "hillshade",
]

/// Seascape, made ours (web composeStyle): OSM raster out (licence), our land
/// in above the relief, pins on top. Missing anchors degrade to appending.
func composeStyle(_ seascape: [String: Any], landUrl: String, uscaUrl: String) -> [String: Any] {
    var style = seascape
    var layers = (seascape["layers"] as? [[String: Any]] ?? [])
        .filter { ($0["id"] as? String) != "osm-base" }
        .filter { nativeLayerTypes.contains($0["type"] as? String ?? "") }
    let anchor = layers.firstIndex { ($0["id"] as? String) == "contour-lines" } ?? layers.count
    layers.insert(contentsOf: landLayers, at: anchor)
    // Seascape's water tone comes from its color-relief layers, which the
    // filter above removed — put our navy under everything so water isn't the
    // renderer's default black.
    layers.insert(["id": "water-bg", "type": "background",
                   "paint": ["background-color": WATER_TONE]], at: 0)

    var sources = seascape["sources"] as? [String: Any] ?? [:]
    for (key, value) in landSources(landUrl, uscaUrl) { sources[key] = value }
    sources["stations"] = stationSource()
    style["sources"] = sources

    let hasGlyphs = seascape["glyphs"] is String
    // Prefer the host style's own font stack, like the web.
    let sample = layers.first {
        ($0["type"] as? String) == "symbol" &&
        (($0["layout"] as? [String: Any])?["text-font"] as? [String]) != nil
    }
    let font = (sample?["layout"] as? [String: Any])?["text-font"] as? [String]
        ?? ["Open Sans Regular", "Arial Unicode MS Regular"]
    style["layers"] = layers + pinLayers(hasGlyphs: hasGlyphs, labelFont: font)
    return style
}

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
    private let killSwitch = CommandLine.arguments.contains("-networkKillSwitch")

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
        guard !killSwitch else { return }
        let imperial = UserDefaults.standard.string(forKey: unitsKey) != "metric"
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

    /// A filled square, drawn to equal AREA with the 5pt circle pins: for
    /// radius r the side is r·√π. A same-width square always reads heavier.
    /// Registered as a template image so `icon-color` can tint it — that is
    /// MapLibre Native's SDF path, and without it the pin ignores state.
    private func squarePinImage(radius: CGFloat = 5, scale: CGFloat = 3) -> UIImage {
        let side = radius * CGFloat(Double.pi.squareRoot())
        let size = CGSize(width: side * 2, height: side * 2)
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
    }
}

// MARK: - The map view

struct MapViewRepresentable: UIViewRepresentable {
    /// Where the discovery map opens. A real fix when there is one — a user in
    /// Boston must not open the map on the Salish Sea (M53) — and the Salish
    /// camera when there isn't, which is also what the UI tests see.
    let center: CLLocationCoordinate2D
    let onSelect: (StationItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.attributionButtonPosition = .bottomLeft
        map.logoViewPosition = .bottomLeft
        map.showsUserLocation = LocationService.shared.authorized
        context.coordinator.install(on: map, center: center)
        return map
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject {
        let onSelect: (StationItem) -> Void
        private weak var map: MLNMapView?
        private var styler: MapStyler?

        init(onSelect: @escaping (StationItem) -> Void) { self.onSelect = onSelect }

        func install(on map: MLNMapView, center: CLLocationCoordinate2D) {
            self.map = map
            styler = MapStyler(map: map, cacheName: "discovery",
                               center: center, zoom: discoveryZoom)
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
