import MapLibre
import SwiftUI
import XCTest
@testable import Slackwater

@MainActor final class MapSettingsTests: XCTestCase {
    func testMountedMapRefreshesReadingsWhenUnitsChange() async throws {
        let defaults = AppGroup.defaults
        let keys = [unitsKey, speedUnitKey]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("imperial", forKey: unitsKey)
        defaults.set("kn", forKey: speedUnitKey)
        let tide = try XCTUnwrap(StationItem.all.first { $0.name == "Kanaka Bay" && $0.series == .tide })
        let current = try XCTUnwrap(StationItem.all.first { $0.name == "Deception Pass (Narrows)" && $0.series == .current })
        let points = [tide, current].map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let center = CLLocationCoordinate2D(latitude: (tide.latitude + current.latitude) / 2,
                                           longitude: (tide.longitude + current.longitude) / 2)
        let (window, host, map) = try await mountedMap(center: center, framing: points)
        defer { window.isHidden = true; window.rootViewController = nil }
        let style = try XCTUnwrap(map.style)
        let source = stationShapeSource()
        style.addSource(source)
        defer { withExtendedLifetime(source) {} }
        defaults.set("kmh", forKey: speedUnitKey)
        let initial = await eventually {
            self.reading(tide.id, from: map)?.hasSuffix(" ft") == true
                && self.reading(current.id, from: map)?.hasSuffix(" km/h") == true
        }
        XCTAssertTrue(initial, "the mounted map did not build its initial readings")
        let position = map.centerCoordinate, zoom = map.zoomLevel
        defaults.set("metric", forKey: unitsKey)
        let metric = await eventually { self.reading(tide.id, from: map)?.hasSuffix(" m") == true }
        XCTAssertTrue(metric, "height units must refresh without a camera move or timer tick")
        defaults.set("ms", forKey: speedUnitKey)
        let speed = await eventually { self.reading(current.id, from: map)?.hasSuffix(" m/s") == true }
        XCTAssertTrue(speed, "speed units must refresh without a camera move or timer tick")
        XCTAssertTrue(map === nativeMap(in: host.view))
        XCTAssertEqual(map.centerCoordinate.latitude, position.latitude, accuracy: 0.000001)
        XCTAssertEqual(map.centerCoordinate.longitude, position.longitude, accuracy: 0.000001)
        XCTAssertEqual(map.zoomLevel, zoom, accuracy: 0.000001)
    }

    func testSelectedPinStaysAboveAGrowingOverlay() async throws {
        let item = try XCTUnwrap(StationItem.all.first { $0.name == "Kanaka Bay" && $0.series == .tide })
        let center = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
        let (window, host, map) = try await mountedMap(center: center)
        defer { window.isHidden = true; window.rootViewController = nil }
        // Isolate camera updates from the style's initial framing callback.
        map.delegate = nil
        host.rootView = page(center: center, selection: MapSelection(item), cover: 240)
        let selected = await eventually {
            abs(map.convert(center, toPointTo: map).y - (map.bounds.height - 240) / 2) < 2
        }
        XCTAssertTrue(selected)
        host.rootView = page(center: center, selection: MapSelection(item), cover: 600)
        let clear = await eventually {
            map.convert(center, toPointTo: map).y < map.bounds.height - 600
        }
        XCTAssertTrue(clear, "a larger preview and legend must leave the selected pin visible")
    }

    private func page(center: CLLocationCoordinate2D, framing: [CLLocationCoordinate2D]? = nil,
                      selection: MapSelection? = nil, cover: CGFloat = 240) -> AnyView {
        AnyView(MapViewRepresentable(center: center, zoom: 11, framing: framing, selected: selection,
                                    previewCover: cover, onSelect: { _ in }, onProject: { _ in })
            .frame(width: 800, height: 800))
    }

    private func mountedMap(center: CLLocationCoordinate2D, framing: [CLLocationCoordinate2D]? = nil)
        async throws -> (UIWindow, UIHostingController<AnyView>, MLNMapView) {
        let host = UIHostingController(rootView: page(center: center, framing: framing))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 800)
        var ready = false
        defer { if !ready { window.isHidden = true; window.rootViewController = nil } }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let appeared = await eventually { self.nativeMap(in: host.view) != nil }
        XCTAssertTrue(appeared)
        let map = try XCTUnwrap(nativeMap(in: host.view))
        // Projection mode omits pin layers and timers, so only the real settings update path can populate this source.
        map.styleJSON = #"{"version":8,"name":"Map settings test","sources":{},"layers":[]}"#
        let loaded = await eventually { map.style?.name == "Map settings test" && map.zoomLevel > READING_MIN_ZOOM }
        XCTAssertTrue(loaded)
        ready = true
        return (window, host, map)
    }

    private func nativeMap(in view: UIView) -> MLNMapView? {
        if let map = view as? MLNMapView { return map }
        return view.subviews.lazy.compactMap { self.nativeMap(in: $0) }.first
    }

    private func reading(_ id: String, from map: MLNMapView) -> String? {
        guard let source = map.style?.source(withIdentifier: "stations") as? MLNShapeSource,
              let data = source.shape?.geoJSONData(usingEncoding: String.Encoding.utf8.rawValue),
              let json = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [String: Any], let features = root["features"] as? [[String: Any]] else { return nil }
        return features.compactMap { $0["properties"] as? [String: Any] }
            .first { $0["id"] as? String == id }?["reading"] as? String
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<Int(200 * max(1, perfScale)) {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }
}
