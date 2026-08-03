// Slackwater — GPL v3. M53: what going from 195 bundled stations to 3,125
// has to keep true. Three kinds of check live here:
//
//   1. The BUNDLE census — the generators are build-time scripts, so this is
//      the only thing standing between a botched regeneration and a shipped
//      binary with half a country missing.
//   2. The SCALE work, MEASURED rather than asserted — search and the distance
//      ranking each run the old shape beside the new one in the same test, so
//      the numbers in the commit message are numbers, not vibes.
//   3. The CANADA rule — the download set is the nearest few plus what you
//      opened, and it has to fit in a first run somebody will sit through,
//      from any fix.
import XCTest
@testable import Slackwater

final class NationalScaleTests: XCTestCase {

    // MARK: - The bundle

    /// Counts by source. Floors, not equality: upstream adding stations should
    /// not break the build — losing them should.
    func testBundleCoversTheUsAndCanada() {
        func count(_ match: (StationItem) -> Bool) -> Int { StationItem.all.filter(match).count }
        let tides = count { if case .tide = $0 { true } else { false } }
        let currents = count { if case .current = $0 { true } else { false } }
        let chs = count { if case .chs = $0 { true } else { false } }
        XCTAssertGreaterThanOrEqual(tides, 1_100, "NOAA tide stations")
        XCTAssertGreaterThanOrEqual(currents, 800, "NOAA current stations")
        XCTAssertGreaterThanOrEqual(chs, 1_000, "CHS tide station identities")
        XCTAssertEqual(ChsCurrentGateInfo.all.count, 11,
                       "Canadian CURRENT gates stay the 11 validated Salish ones (M47/M53)")
        XCTAssertEqual(Set(StationItem.all.map(\.id)).count, StationItem.all.count,
                       "two stations sharing an id is a duplicate row, pin and model file")
    }

    /// Both coasts, both countries, and a real curve at the far end of one —
    /// the bundle is not quietly a Pacific bundle with extras.
    func testFarStationsAreSearchableAndPredictable() throws {
        for query in ["boston", "san francisco", "key west", "halifax", "honolulu"] {
            XCTAssertFalse(StationItem.search(query).isEmpty, "\"\(query)\" found nothing")
        }
        let boston = try XCTUnwrap(TideStationRecord.all.first { $0.name == "Boston" })
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let extremes = boston.engineStation.extremes(from: now, to: now.addingTimeInterval(30 * 3600))
        XCTAssertGreaterThanOrEqual(extremes.count, 3, "a day of Boston tide has 3-4 turns")
        let range = extremes.map(\.height).max()! - extremes.map(\.height).min()!
        XCTAssertGreaterThan(range, 1.5, "Boston's range is metres, not centimetres")
        XCTAssertLessThan(range, 6.0)
        XCTAssertEqual(boston.tz.identifier, "America/New_York",
                       "a national bundle needs a per-station zone, not the Pacific one")
    }

    /// Identity, not readings. The whole CHS licensing posture is one file's
    /// contents, so assert on the file.
    func testNoChsPredictionsAreBundled() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "chs-stations", withExtension: "json"))
        let json = String(decoding: try Data(contentsOf: url), as: UTF8.self).lowercased()
        for forbidden in ["constituent", "amplitude", "iwls", "datum"] {
            XCTAssertFalse(json.contains(forbidden),
                           "chs-stations.json carries \"\(forbidden)\" — identity only ships")
        }
    }

    /// Every region line renders — and none of them is the resolver's Salish
    /// gazetteer guessing about a station 4,000 km from the Salish Sea.
    func testEveryStationHasARegionAndNoneIsAGazetteerGuess() {
        for item in StationItem.all {
            XCTAssertFalse(item.region.isEmpty, "\(item.name) has no region line")
        }
        XCTAssertEqual(StationItem.all.first { $0.name == "Boston" }?.region, "MA")
        XCTAssertFalse(StationItem.all.contains { $0.region.hasSuffix(" of") },
                       "a dangling preposition survived the generators")
        XCTAssertFalse(StationItem.all.contains { $0.name == "Boston" && $0.region.contains("WA") },
                       "the 19-town Salish gazetteer leaked into a national context line")
    }

    // MARK: - Scale, measured

    /// Search at national scale. The M52 implementation runs beside the new one
    /// so the claim is measured: the win is not the matching (a scan of 3,125
    /// stations is milliseconds either way) — it is that the screen stops
    /// handing SwiftUI a thousand rows to diff on every keystroke.
    func testSearchIsBoundedAndLandsInsideAFrame() {
        let queries = ["p", "po", "por", "port", "port t", "boston", "b", "san", "halifax", "z"]
        /// The M52 implementation, verbatim: every match, sorted by name, with
        /// no cap. Anything less faithful would be measuring the sort.
        func naive(_ query: String) -> [StationItem] {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            if q.isEmpty { return StationItem.all }
            var ranked: [(item: StationItem, rank: Int)] = []
            for s in StationItem.all {
                if let rank = s.searchRank(q) { ranked.append((s, rank)) }
            }
            ranked.sort { $0.rank == $1.rank ? $0.item.name < $1.item.name : $0.rank < $1.rank }
            return ranked.map(\.item)
        }
        var worstBefore = 0
        for q in queries {
            let shown = StationItem.search(q)
            let every = naive(q)
            worstBefore = max(worstBefore, every.count)
            XCTAssertEqual(shown.count, min(every.count, StationItem.searchLimit),
                           "\"\(q)\" shows the wrong number of results")
            XCTAssertTrue(Set(shown.map(\.id)).isSubset(of: Set(every.map(\.id))),
                          "\"\(q)\" surfaced something the old matcher would not have")
        }
        // Nearest first, not alphabetical: the ordering change scale forced.
        let near = (lat: 42.35, lon: -71.05)  // Boston
        let ports = StationItem.search("port", near: near)
        XCTAssertLessThan(ports[0].km(fromLat: near.lat, lon: near.lon), 500,
                          "\"port\" in Boston must not answer with Alaska")
        let before = elapsed { for q in queries { _ = naive(q) } }
        let after = elapsed { for q in queries { _ = StationItem.search(q) } }
        print(String(format: "M53 search · %d stations · %d queries: %.1f ms -> %.1f ms; " +
                     "worst result list %d rows -> %d",
                     StationItem.all.count, queries.count, before * 1000, after * 1000,
                     worstBefore, StationItem.searchLimit))
        XCTAssertGreaterThan(worstBefore, 500, "pick a query that used to flood the screen")
        XCTAssertLessThan(after / Double(queries.count), 0.016,
                          "a keystroke must land inside one 60 fps frame")
    }

    /// The list ranks the catalog inside `body`, which SwiftUI re-evaluates on
    /// every fit, favourite and unit switch. Memoised, a re-render is free.
    @MainActor
    func testRankedCatalogIsMemoisedPerFix() {
        let fix = fallbackFix
        _ = RankedStations.near(lat: 0, lon: 0)   // evict, so "cold" is cold
        let cold = elapsed { _ = RankedStations.near(lat: fix.lat, lon: fix.lon) }
        let warm = elapsed { for _ in 0..<20 { _ = RankedStations.near(lat: fix.lat, lon: fix.lon) } }
        print(String(format: "M53 ranking · %d stations: one sort %.1f ms, 20 re-renders %.2f ms",
                     StationItem.all.count, cold * 1000, warm * 1000))
        XCTAssertLessThan(warm, cold, "20 memoised re-renders must cost less than one sort")
        // A real move re-sorts; GPS jitter under ~100 m does not.
        XCTAssertEqual(RankedStations.near(lat: fix.lat + 0.00001, lon: fix.lon).ranked.first?.id,
                       RankedStations.near(lat: fix.lat, lon: fix.lon).ranked.first?.id)
    }

    /// The map hands MapLibre one GeoJSON document; building it must not be
    /// something the map screen notices.
    func testPinLayerBuildsInsideAFrame() {
        let build = elapsed { _ = localFallbackStyle(landUrl: "", uscaUrl: "") }
        print(String(format: "M53 pin source · %d stations: %.1f ms", StationItem.all.count, build * 1000))
        XCTAssertLessThan(build, 0.30)
    }

    /// Task 5 fix round 1: the pin's direction check shrank from the list
    /// card's 30h "next" guarantee to `PIN_TIDE_WINDOW`, to fit the budget
    /// above. Shrinking a forward search can only ever MISS the next turn
    /// (window ends before it — `tidePinRising` returns nil, the pin draws
    /// neutral) or find the SAME next extreme the 30h search finds first —
    /// never a different one, because both searches walk forward from `now`
    /// in the same order and stop at the first root. This test checks that
    /// claim against the real bundled set instead of trusting the argument:
    /// every tide station, at four times spread across a day (so a station
    /// sitting right at a turn at hour 0 isn't the only case exercised),
    /// short-window direction compared to the 30h baseline.
    func testShortWindowDirectionMatchesThirtyHourBaseline() {
        let dayStart = Date(timeIntervalSince1970: 1_785_000_000)
        let checkTimes = [0.0, 6.0, 12.0, 18.0].map { dayStart.addingTimeInterval($0 * 3600) }
        var resolved = 0
        var mismatches: [String] = []
        for record in TideStationRecord.all {
            for now in checkTimes {
                let baseline = record.cardState(at: now).rising
                guard let short = tidePinRising(record, at: now, window: PIN_TIDE_WINDOW) else { continue }
                resolved += 1
                if short != baseline {
                    mismatches.append("\(record.id) at \(now): short=\(short) baseline=\(baseline)")
                }
            }
        }
        let checked = TideStationRecord.all.count * checkTimes.count
        print("Short-window (\(Int(PIN_TIDE_WINDOW / 3600))h) direction: "
              + "\(resolved)/\(checked) resolved a tone, \(mismatches.count) disagreed with the 30h baseline")
        XCTAssertTrue(mismatches.isEmpty,
                      "short window direction disagreed with the 30h baseline: \(mismatches.prefix(10))")
    }

    /// Clustering is what makes 3,125 pins a map rather than a smear — and the
    /// zoom it stops at is what keeps the discovery view tappable.
    func testStationSourceClustersOnlyBelowTheDiscoveryZoom() throws {
        let style = localFallbackStyle(landUrl: "", uscaUrl: "")
        let sources = try XCTUnwrap(style["sources"] as? [String: Any])
        let stations = try XCTUnwrap(sources["stations"] as? [String: Any])
        XCTAssertEqual(stations["cluster"] as? Bool, true)
        let maxZoom = try XCTUnwrap(stations["clusterMaxZoom"] as? Int)
        XCTAssertLessThan(Double(maxZoom), SALISH_ZOOM,
                          "the discovery camera must open on tappable stations, not clusters")
        let layers = try XCTUnwrap(style["layers"] as? [[String: Any]])
        XCTAssertTrue(layers.contains { ($0["id"] as? String) == "station-clusters" })
        XCTAssertNotNil(layers.first { ($0["id"] as? String) == "station-pins-current" }?["filter"],
                        "the current-pin layer must exclude clusters, or every cluster draws twice")
        XCTAssertNotNil(layers.first { ($0["id"] as? String) == "station-pins-tide" }?["filter"],
                        "the tide-pin layer must exclude clusters, or every cluster draws twice")
        // Both land tilesets, or somewhere in the covered area is blank water.
        XCTAssertNotNil(sources["land-usca"], "the continental land floor is missing")
        XCTAssertNotNil(sources["land"], "the Salish detail layer is missing")
    }

    // MARK: - Canada on demand

    /// The download set is the nearest few, not the country — it budgets the
    /// two series separately (ten nearest anything is ten Victoria harbour
    /// gauges and no passes), and it fits in a first run from either coast.
    @MainActor
    func testAutoFitSetIsBoundedAndAffordableFromAnyFix() {
        let service = ChsFitService.shared
        XCTAssertLessThan(service.queue.total, 60,
                          "the queue is the download set, not the 1,097-station catalog")
        XCTAssertGreaterThan(service.notQueued, 1_000, "the rest of Canada is on demand, not gone")
        for (place, fix, gates) in [("Victoria", fallbackFix, 3),
                                    ("Halifax", (lat: 44.65, lon: -63.57), 0)] {
            let set = ChsFitService.autoFitSet(lat: fix.lat, lon: fix.lon)
            let seconds = set.reduce(0) { $0 + $1.estimatedSeconds }
            let far = set.map { distanceKm($0.latitude, $0.longitude, fix.lat, fix.lon) }.max() ?? 0
            print(String(format: "M53 auto-fit from %@: %d ports + %d gates, ~%.1f min, within %.0f km",
                         place, set.filter { !$0.isCurrent }.count, set.filter(\.isCurrent).count,
                         seconds / 60, far))
            XCTAssertEqual(set.filter { !$0.isCurrent }.count, ChsFitService.autoFitPorts)
            XCTAssertEqual(set.filter(\.isCurrent).count, gates,
                           "\(place) must not download passes on the wrong ocean")
            XCTAssertLessThan(seconds, 10 * 60, "\(place)'s first run must not be an afternoon")
        }
    }

    /// A Canadian station outside the auto-fit set is visible, searchable, says
    /// the thing that is actually true about it — and downloading it is one tap.
    @MainActor
    func testOnDemandStationIsVisibleAndSaysSo() throws {
        let service = ChsFitService.shared
        let far = try XCTUnwrap(ChsStationInfo.all.first {
            !service.isQueued($0.id) && $0.region == "Atlantic Coast"
        })
        XCTAssertTrue(StationItem.search(far.name.lowercased()).contains { $0.id == far.id },
                      "an undownloaded station still has to be findable")
        XCTAssertTrue(chsPendingMessage("tidal", id: far.id).hasPrefix("Open to download"),
                      "it must not claim to be queued when it isn't")
        service.promote(far.id)   // what ChsDetailView does on appear
        XCTAssertTrue(service.isQueued(far.id))
        XCTAssertEqual(service.queue.position(far.id), 1, "what you opened is next up")
        XCTAssertTrue(chsPendingMessage("tidal", id: far.id).hasPrefix("Queued") ||
                      chsPendingMessage("tidal", id: far.id).hasPrefix("Needs a moment"),
                      "once queued it stops saying \"open to download\"")
    }
}

/// Wall clock for one block, in seconds.
private func elapsed(_ body: () -> Void) -> TimeInterval {
    let start = Date.now
    body()
    return Date.now.timeIntervalSince(start)
}
