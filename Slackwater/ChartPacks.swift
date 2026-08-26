// Slackwater — GPL v3. Offline chart packs (2026-08-25 offline-chart-packs
// spec §4): the map renders one hosted style, and MLNOfflineStorage keeps
// three tiers of tile packs — world z0–4, z5 grid-cell areas z5–8, station
// discs z9–12 — so the chart works offline wherever the user actually is.
// Tiers stack: each owns its zoom range outright, so no tile is fetched twice.
import Foundation
import Combine
import CoreLocation
import MapLibre

/// The one basemap: the published VersaTiles satellite style, consumed
/// verbatim. The map's `styleURL` and every offline pack's region point at
/// this same URL — switching basemaps is changing this constant. The app's
/// own channels (station pins, current fill) are runtime-added layers and
/// never touch the style.
let BASEMAP_STYLE_URL = URL(string: "https://tiles.versatiles.org/assets/styles/satellite/style.json")!

// MARK: - Grid math (pure — ChartPackTests)

/// Web-Mercator slippy-tile arithmetic. MapLibre-free so the tier logic is
/// unit-testable without a map.
enum ChartGrid {
    /// Web-Mercator's latitude edge; beyond it there are no tiles.
    static let maxLat = 85.0511

    static func tileX(lon: Double, z: Int) -> Int {
        let n = 1 << z
        return min(n - 1, max(0, Int(floor((lon + 180) / 360 * Double(n)))))
    }

    static func tileY(lat: Double, z: Int) -> Int {
        let n = 1 << z
        let clamped = min(maxLat, max(-maxLat, lat))
        let y = (1 - asinh(tan(clamped * .pi / 180)) / .pi) / 2 * Double(n)
        return min(n - 1, max(0, Int(floor(y))))
    }

    /// (south, west, north, east) of tile (x, y) at zoom z.
    static func cellBounds(x: Int, y: Int, z: Int) -> (s: Double, w: Double, n: Double, e: Double) {
        let n = Double(1 << z)
        func lat(_ y: Double) -> Double { atan(sinh(.pi * (1 - 2 * y / n))) * 180 / .pi }
        return (s: lat(Double(y + 1)), w: Double(x) / n * 360 - 180,
                n: lat(Double(y)), e: Double(x + 1) / n * 360 - 180)
    }

    /// The 3×3 cell set around a coordinate: x wraps the antimeridian, y
    /// clamps at the poles (the clamped row simply repeats and dedupes).
    static func neighborhood(lat: Double, lon: Double, z: Int) -> Set<Cell> {
        let n = 1 << z
        let cx = tileX(lon: lon, z: z), cy = tileY(lat: lat, z: z)
        var cells = Set<Cell>()
        for dx in -1...1 {
            for dy in -1...1 {
                cells.insert(Cell(x: (cx + dx + n) % n, y: min(n - 1, max(0, cy + dy)), z: z))
            }
        }
        return cells
    }

    struct Cell: Hashable {
        let x: Int, y: Int, z: Int
        var key: String { "area/\(z)/\(x)/\(y)" }
    }
}

// MARK: - Tier constants and pack specs (spec §4 table)

let AREA_GRID_Z = 5
private let WORLD_MAX_Z = 4.0
private let AREA_MAX_Z = 8.0
private let STATION_MIN_Z = 9.0
private let STATION_MAX_Z = 12.0
private let STATION_RADIUS_KM = 20.0

/// One desired offline pack: identity (`key`), region, zoom range. Bounds are
/// plain degrees so specs stay Hashable and testable.
struct ChartPackSpec: Hashable {
    let key: String
    let south: Double, west: Double, north: Double, east: Double
    let minZoom: Double, maxZoom: Double
}

/// The full desired pack set for a fix and the starred/downloaded stations.
/// Pure: the manager diffs this against MLNOfflineStorage's actual packs.
func desiredChartPacks(fix: (lat: Double, lon: Double)?,
                       stations: [(id: String, lat: Double, lon: Double)]) -> Set<ChartPackSpec> {
    var specs: Set<ChartPackSpec> = [
        ChartPackSpec(key: "world", south: -ChartGrid.maxLat, west: -180,
                      north: ChartGrid.maxLat, east: 180, minZoom: 0, maxZoom: WORLD_MAX_Z),
    ]
    // Area cells: 3×3 around the fix, plus the cell under every station —
    // starring keeps a station's area alive after the boat sails away.
    var cells = fix.map { ChartGrid.neighborhood(lat: $0.lat, lon: $0.lon, z: AREA_GRID_Z) } ?? []
    for s in stations {
        cells.insert(ChartGrid.Cell(x: ChartGrid.tileX(lon: s.lon, z: AREA_GRID_Z),
                                    y: ChartGrid.tileY(lat: s.lat, z: AREA_GRID_Z), z: AREA_GRID_Z))
    }
    for cell in cells {
        let b = ChartGrid.cellBounds(x: cell.x, y: cell.y, z: cell.z)
        specs.insert(ChartPackSpec(key: cell.key, south: b.s, west: b.w, north: b.n, east: b.e,
                                   minZoom: Double(AREA_GRID_Z), maxZoom: AREA_MAX_Z))
    }
    for s in stations {
        // ±20 km box; longitude widens with latitude. Overlapping boxes cost
        // nothing extra: the offline database stores a shared tile once.
        let dLat = STATION_RADIUS_KM / 111.0
        let dLon = STATION_RADIUS_KM / (111.0 * max(0.2, cos(s.lat * .pi / 180)))
        specs.insert(ChartPackSpec(key: "station/\(s.id)",
                                   south: max(-ChartGrid.maxLat, s.lat - dLat), west: s.lon - dLon,
                                   north: min(ChartGrid.maxLat, s.lat + dLat), east: s.lon + dLon,
                                   minZoom: STATION_MIN_Z, maxZoom: STATION_MAX_Z))
    }
    return specs
}

// MARK: - The manager

/// Reconciles MLNOfflineStorage against `desiredChartPacks` whenever the fix
/// or the favorites change. Owns only packs whose context carries its
/// "chart" key — anything else in the store is left alone.
final class ChartPackManager: NSObject {
    static let shared = ChartPackManager()

    private var styleURL: URL?
    private var packsObservation: NSKeyValueObservation?
    private var cancellables: Set<AnyCancellable> = []
    /// Keys with an addPack in flight — `storage.packs` doesn't show a pack
    /// until its creation lands, and two startup signals reconcile back to
    /// back, so without this every launch double-creates the world pack.
    private var creating: Set<String> = []

    /// Idempotent. No-op under -networkKillSwitch / -chartPacksOff so tests
    /// never start real downloads.
    func start(styleURL: URL) {
        guard !networkKillSwitch, !CommandLine.arguments.contains("-chartPacksOff"),
              self.styleURL == nil else { return }
        self.styleURL = styleURL
        // Far above the three tiers' combined worst case; the default ~6k
        // ceiling silently caps packs (spec §4).
        MLNOfflineStorage.shared.setMaximumAllowedMapboxTiles(200_000)
        // `packs` is nil until the store loads it — reconcile then, and again
        // on every later signal.
        packsObservation = MLNOfflineStorage.shared.observe(\.packs, options: [.initial]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reconcile() }
        }
        FavoritesStore.shared.$ids
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)
        LocationService.shared.$location
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            // Reconcile is cheap, but pack churn isn't: ignore movement until
            // it can actually change the z5 cell set.
            .removeDuplicates { a, b in
                ChartGrid.tileX(lon: a.coordinate.longitude, z: AREA_GRID_Z) == ChartGrid.tileX(lon: b.coordinate.longitude, z: AREA_GRID_Z)
                    && ChartGrid.tileY(lat: a.coordinate.latitude, z: AREA_GRID_Z) == ChartGrid.tileY(lat: b.coordinate.latitude, z: AREA_GRID_Z)
            }
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)
    }

    private func reconcile() {
        guard let styleURL, let packs = MLNOfflineStorage.shared.packs else { return }
        let fix = LocationService.shared.location.map {
            (lat: $0.coordinate.latitude, lon: $0.coordinate.longitude)
        }
        let stations = FavoritesStore.shared.ids.compactMap { id -> (String, Double, Double)? in
            guard let item = StationItem.byId[id] else { return nil }
            return (id, item.latitude, item.longitude)
        }
        let desired = desiredChartPacks(fix: fix, stations: stations)
        let desiredByKey = Dictionary(uniqueKeysWithValues: desired.map { ($0.key, $0) })

        var existing: [String: MLNOfflinePack] = [:]
        for pack in packs {
            guard let context = Self.chartContext(of: pack) else { continue }  // not ours
            // A pack built against a different basemap holds that style's
            // resources — switching basemaps must rebuild it, not keep it.
            guard context["style"] == styleURL.absoluteString, let key = context["chart"],
                  existing[key] == nil else {  // a duplicate of a kept pack goes too
                MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil)
                continue
            }
            existing[key] = pack
        }
        for (key, pack) in existing where desiredByKey[key] == nil {
            MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil)
        }
        for (key, spec) in desiredByKey {
            if creating.contains(key) { continue }
            if let pack = existing[key] {
                // Resume state doesn't persist across launches; nudging a
                // complete pack is a no-op.
                pack.resume()
                continue
            }
            creating.insert(key)
            let region = MLNTilePyramidOfflineRegion(
                styleURL: styleURL,
                bounds: MLNCoordinateBounds(
                    sw: CLLocationCoordinate2D(latitude: spec.south, longitude: spec.west),
                    ne: CLLocationCoordinate2D(latitude: spec.north, longitude: spec.east)),
                fromZoomLevel: spec.minZoom, toZoomLevel: spec.maxZoom)
            guard let context = try? JSONSerialization.data(withJSONObject:
                ["chart": key, "style": styleURL.absoluteString]) else { continue }
            MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] pack, _ in
                DispatchQueue.main.async { self?.creating.remove(key) }
                pack?.resume()  // errors are retried by the next reconcile
            }
        }
    }

    static func chartContext(of pack: MLNOfflinePack) -> [String: String]? {
        (try? JSONSerialization.jsonObject(with: pack.context) as? [String: String])
            .flatMap { $0["chart"] != nil ? $0 : nil }
    }
}
