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
/// How long to wait before asking again after a pack creation fails.
private let PACK_RETRY_S: TimeInterval = 60

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
        for spec in stationSpecs(id: s.id, lat: s.lat, lon: s.lon) { specs.insert(spec) }
    }
    return specs
}

/// A station's detail box: ±20 km, longitude widening with latitude.
/// Overlapping boxes cost nothing extra — the offline database stores a
/// shared tile once. A box crossing the antimeridian becomes TWO packs:
/// `MLNCoordinateBounds` cannot express a span that wraps, and a longitude
/// outside ±180 silently downloads the wrong ground.
func stationSpecs(id: String, lat: Double, lon: Double) -> [ChartPackSpec] {
    let dLat = STATION_RADIUS_KM / 111.0
    let dLon = STATION_RADIUS_KM / (111.0 * max(0.2, cos(lat * .pi / 180)))
    let south = max(-ChartGrid.maxLat, lat - dLat)
    let north = min(ChartGrid.maxLat, lat + dLat)
    func spec(_ key: String, _ west: Double, _ east: Double) -> ChartPackSpec {
        ChartPackSpec(key: key, south: south, west: west, north: north, east: east,
                      minZoom: STATION_MIN_Z, maxZoom: STATION_MAX_Z)
    }
    let west = lon - dLon, east = lon + dLon
    if west < -180 {
        return [spec("station/\(id)", -180, east), spec("station/\(id)/wrap", west + 360, 180)]
    }
    if east > 180 {
        return [spec("station/\(id)", west, 180), spec("station/\(id)/wrap", -180, east - 360)]
    }
    return [spec("station/\(id)", west, east)]
}

// MARK: - The manager

/// Reconciles MLNOfflineStorage against `desiredChartPacks` whenever the fix
/// or the favorites change. Owns only packs whose context carries its
/// "chart" key — anything else in the store is left alone.
/// What the offline manager shows for the chart tiers. Areas, not tiles: a
/// pack is one piece of ground, which is the unit a user can reason about.
struct ChartPackSummary: Equatable {
    var total = 0
    var ready = 0
    var failed = 0
    var bytes: Int64 = 0
    var downloading: Bool { ready < total }
}

@MainActor
final class ChartPackManager: NSObject, ObservableObject {
    static let shared = ChartPackManager()

    @Published private(set) var summary = ChartPackSummary()

    private var styleURL: URL?
    private var packsObservation: NSKeyValueObservation?
    private var cancellables: Set<AnyCancellable> = []
    /// Keys with an addPack in flight — `storage.packs` doesn't show a pack
    /// until its creation lands, and two startup signals reconcile back to
    /// back, so without this every launch double-creates the world pack.
    private var creating: Set<String> = []
    private var retryScheduled = false
    /// Packs MapLibre reported an error for, cleared the moment one makes
    /// progress again. The only honest source of "didn't finish".
    private var errored: Set<String> = []

    /// Idempotent. No-op under -networkKillSwitch / -chartPacksOff so tests
    /// never start real downloads — and never under XCTest at all: unit tests
    /// run in the app host and end with `exit()`, which finalizes MapLibre's
    /// statics while its DatabaseFileSource thread is still mid-download. That
    /// races into a SIGSEGV that looks like a test failure and isn't.
    func start(styleURL: URL) {
        guard !networkKillSwitch, !CommandLine.arguments.contains("-chartPacksOff"),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              self.styleURL == nil else { return }
        self.styleURL = styleURL
        // Far above the three tiers' combined worst case; the default ~6k
        // ceiling silently caps packs (spec §4).
        MLNOfflineStorage.shared.setMaximumAllowedMapboxTiles(200_000)
        // `packs` is nil until the store loads it — reconcile then, and again
        // on every later signal.
        packsObservation = MLNOfflineStorage.shared.observe(\.packs, options: [.initial]) { [weak self] _, _ in
            Task { @MainActor in self?.reconcile() }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.MLNOfflinePackProgressChanged, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                // Progress means this pack is alive again, whatever it did before.
                if let pack = note.object as? MLNOfflinePack,
                   let key = Self.chartContext(of: pack)?["chart"] {
                    self?.errored.remove(key)
                }
                self?.publishSummary()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.MLNOfflinePackError, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                if let pack = note.object as? MLNOfflinePack,
                   let key = Self.chartContext(of: pack)?["chart"] {
                    self?.errored.insert(key)
                }
                self?.publishSummary()
            }
        }
        FavoritesStore.shared.$ids
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)
        // The CHS download set is the other half of "starred or downloaded":
        // a station whose model is on disk gets chart coverage too, so the
        // map matches the data wherever the user has chosen to work offline.
        ChsFitService.shared.$queue
            .map { $0.jobs.filter { $0.status == .ready }.map(\.id) }
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
        // Only while the fix is ours to use: LocationService keeps its last
        // location after permission is revoked, and holding a 3×3 of cells
        // around where the user used to be is not coverage they asked for.
        let fix = LocationService.shared.authorized
            ? LocationService.shared.location.map {
                (lat: $0.coordinate.latitude, lon: $0.coordinate.longitude)
              }
            : nil
        let downloaded = ChsFitService.shared.queue.jobs
            .filter { $0.status == .ready }
            .map(\.id)
        let stations = Set(FavoritesStore.shared.ids + downloaded)
            .compactMap { id -> (String, Double, Double)? in
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
        for pack in existing.values { pack.requestProgress() }
        for (key, pack) in existing where desiredByKey[key] == nil {
            MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil)
        }
        defer { publishSummary() }
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
            MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] pack, error in
                Task { @MainActor in
                    self?.creating.remove(key)
                    // Nothing else will ask again: a failed creation leaves
                    // `packs` unchanged, so without this the world pack can
                    // stay missing for a whole session on a launch-time blip.
                    if error != nil { self?.scheduleRetry() }
                }
                pack?.resume()
            }
        }
    }

    /// Recomputed from the store rather than tracked incrementally — pack
    /// state changes in more ways than this class starts (a resumed download,
    /// a failure, a pack the user's other session removed).
    private func publishSummary() {
        let ours = (MLNOfflineStorage.shared.packs ?? []).filter { Self.chartContext(of: $0) != nil }
        var next = ChartPackSummary(total: ours.count)
        var live: Set<String> = []
        for pack in ours {
            let progress = pack.progress
            if let key = Self.chartContext(of: pack)?["chart"] { live.insert(key) }
            if pack.state == .complete
                || (progress.countOfResourcesExpected > 0
                    && progress.countOfResourcesCompleted >= progress.countOfResourcesExpected) {
                next.ready += 1
            }
            next.bytes += Int64(progress.countOfBytesCompleted)
        }
        // Failure is what MapLibre REPORTED, never what a state looks like
        // mid-flight: a pack sits `.inactive` between being added and being
        // resumed, and reading that as "didn't finish" made the card flash a
        // retry prompt every time a batch of packs was created.
        errored.formIntersection(live)
        next.failed = errored.count
        guard next != summary else { return }   // progress fires per resource
        summary = next
    }

    /// The manager's "refresh": ask every chart pack to re-validate what it
    /// holds, so a sailor can top the charts up before leaving signal.
    func refresh() {
        guard let packs = MLNOfflineStorage.shared.packs else { return }
        errored.removeAll()
        for pack in packs where Self.chartContext(of: pack) != nil {
            pack.requestProgress()
            pack.resume()
        }
        reconcile()
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + PACK_RETRY_S) { [weak self] in
            self?.retryScheduled = false
            self?.reconcile()
        }
    }

    static func chartContext(of pack: MLNOfflinePack) -> [String: String]? {
        (try? JSONSerialization.jsonObject(with: pack.context) as? [String: String])
            .flatMap { $0["chart"] != nil ? $0 : nil }
    }
}
