// Slackwater — GPL v3. M4 simple pin map, mirroring slackwater-web
// (MapScreen.tsx + mapStyle.ts): the bundled OSM land-polygons PMTiles under
// everything (offline floor), Seascape's style composed in when it can be
// fetched, every bundled station as a pin, tap → detail. MapLibre Native
// reads the same land.pmtiles artifact the web serves, via its built-in
// pmtiles:// support — one artifact, two renderers.
import SwiftUI
import MapLibre

private let SALISH_CENTER = CLLocationCoordinate2D(latitude: 48.6, longitude: -123.4)

struct MapScreen: View {
    let onSelect: (StationItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MonoLabel(text: "Map")
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SN.foam)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Close map")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(SN.page)

            MapViewRepresentable(onSelect: onSelect)
                .accessibilityIdentifier("map-canvas")
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) {
                    Text("Depths not reduced to chart datum — not for navigation.")
                        .font(.geist(11))
                        .foregroundStyle(SN.foam.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(SN.page.opacity(0.82), in: Capsule())
                        .padding(.bottom, 26)
                }
        }
        .background(SN.page.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Style building (mirrors web mapStyle.ts)

private let LAND_TONE = "#f5ecd7"   // paper-chart cream
private let WATER_TONE = "#0b1a2b"  // navy water
private let PIN_TIDE = "#7fb3d5", PIN_CURRENT = "#8fd0a0", PIN_CHS = "#c0d8e4"

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

private let landLayer: [String: Any] = [
    "id": "land", "type": "fill", "source": "land", "source-layer": "land",
    "paint": ["fill-color": LAND_TONE],
]

private func pinLayers(hasGlyphs: Bool, labelFont: [String]) -> [[String: Any]] {
    let dots: [String: Any] = [
        "id": "station-dots", "type": "circle", "source": "stations",
        "paint": [
            "circle-radius": 5,
            "circle-color": ["match", ["get", "kind"],
                             "current", PIN_CURRENT, "chs", PIN_CHS, PIN_TIDE] as [Any],
            "circle-stroke-width": 1.5,
            "circle-stroke-color": WATER_TONE,
        ],
    ]
    // Labels need glyphs — the local fallback declares none, so it's dots only
    // (same decisive signal as the web).
    guard hasGlyphs else { return [dots] }
    let labels: [String: Any] = [
        "id": "station-labels", "type": "symbol", "source": "stations",
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
    return [dots, labels]
}

/// Offline / style-fetch-failed: land + pins, honestly bare (web localFallbackStyle).
func localFallbackStyle(landUrl: String) -> [String: Any] {
    [
        "version": 8,
        "sources": ["land": landSource(landUrl), "stations": ["type": "geojson", "data": pinFeatures()]],
        "layers": [
            ["id": "land-bg", "type": "background", "paint": ["background-color": WATER_TONE]],
            landLayer,
        ] + pinLayers(hasGlyphs: false, labelFont: []),
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
func composeStyle(_ seascape: [String: Any], landUrl: String) -> [String: Any] {
    var style = seascape
    var layers = (seascape["layers"] as? [[String: Any]] ?? [])
        .filter { ($0["id"] as? String) != "osm-base" }
        .filter { nativeLayerTypes.contains($0["type"] as? String ?? "") }
    let anchor = layers.firstIndex { ($0["id"] as? String) == "contour-lines" } ?? layers.count
    layers.insert(landLayer, at: anchor)
    // Seascape's water tone comes from its color-relief layers, which the
    // filter above removed — put our navy under everything so water isn't the
    // renderer's default black.
    layers.insert(["id": "water-bg", "type": "background",
                   "paint": ["background-color": WATER_TONE]], at: 0)

    var sources = seascape["sources"] as? [String: Any] ?? [:]
    sources["land"] = landSource(landUrl)
    sources["stations"] = ["type": "geojson", "data": pinFeatures()]
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

// MARK: - The map view

struct MapViewRepresentable: UIViewRepresentable {
    let onSelect: (StationItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.setCenter(SALISH_CENTER, zoomLevel: 7, animated: false)
        map.attributionButtonPosition = .bottomLeft
        map.logoViewPosition = .bottomLeft
        map.showsUserLocation = LocationService.shared.authorized
        context.coordinator.install(on: map)
        return map
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject {
        let onSelect: (StationItem) -> Void
        private weak var map: MLNMapView?
        private let killSwitch = CommandLine.arguments.contains("-networkKillSwitch")

        init(onSelect: @escaping (StationItem) -> Void) { self.onSelect = onSelect }

        private var landUrl: String {
            guard let url = Bundle.main.url(forResource: "land", withExtension: "pmtiles") else { return "" }
            return "pmtiles://\(url.absoluteString)"  // pmtiles://file:///…/land.pmtiles
        }

        func install(on map: MLNMapView) {
            self.map = map
            // Fallback first: land + pins render immediately (and are all an
            // offline user gets); Seascape replaces the style when its fetch
            // lands. No error banner when it doesn't — the map renders what it
            // can reach (web MapScreen, Open Waters offline.md).
            setStyle(localFallbackStyle(landUrl: landUrl), name: "fallback")
            fetchSeascape()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            map.addGestureRecognizer(tap)
        }

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
                self.setStyle(composeStyle(json, landUrl: self.landUrl), name: "seascape")
            }.resume()
        }

        /// Tap → nearest station dot within a finger-sized box → detail.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map else { return }
            let point = gesture.location(in: map)
            let box = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let features = map.visibleFeatures(in: box, styleLayerIdentifiers: ["station-dots"])
            let hit = features.min { a, b in
                let pa = map.convert(a.coordinate, toPointTo: map)
                let pb = map.convert(b.coordinate, toPointTo: map)
                return hypot(pa.x - point.x, pa.y - point.y) < hypot(pb.x - point.x, pb.y - point.y)
            }
            guard let id = hit?.attribute(forKey: "id") as? String,
                  let item = StationItem.all.first(where: { $0.id == id }) else { return }
            onSelect(item)
        }
    }
}
