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
        // +7 online fit-reject identities (online-gates task 1) — count moved
        // by exactly the 7 new entries, so this floor is bumped, not broken.
        XCTAssertEqual(ChsCurrentGateInfo.all.count, 18,
                       "the 11 validated Salish gates (M47/M53) plus the 7 online fit-rejects")
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

    /// Task 5 fix round 1 shrank the pin's direction search to a 1h window
    /// and drew neutral whenever nothing turned up inside it — correct, but
    /// only 838/5,700 (station, moment) checks actually resolved a tone
    /// (~15% coverage): "declining to answer" isn't the same as "cheap and
    /// correct". Round 2 is the hybrid in `tidePinRisingHybrid`: a cheap
    /// two-sample check, its noise threshold weighted by each constituent's
    /// astronomical speed (not just amplitude — a diurnal station's peak
    /// slope is roughly half a semidiurnal one's at equal amplitude, so an
    /// amplitude-only proxy over-flagged diurnal stations as "near a turn"),
    /// that resolves almost every station directly and falls back to the
    /// exact search only for the ones actually near a turn. This asserts
    /// BOTH numbers the round-1 test was missing — coverage (should read
    /// ~100%, not a fraction) and correctness (mismatches against the 30h
    /// baseline, which must be zero) — at four times spread across a day,
    /// across the whole bundled tide set. Threshold sweep this shipped with
    /// (speed-weighted relative delta): 0.0003 → 2 wrong-signed trusted
    /// samples out of 5,700; 0.00033 → 0; shipped at 0.0004 for margin above
    /// that empirical floor (7.4% fall back to the exact search, versus 15%
    /// for the amplitude-only version of this same idea).
    ///
    /// Issue #15: one reference date leaves the ~27-day lunar declination
    /// cycle unsampled, and four probes 6h apart all share one alignment on
    /// the sampler's 30-min epoch grid. So: five day-starts spanning a lunar
    /// month, each day's four times shifted by a different odd-minute offset
    /// so no two dates land on the same grid phase.
    ///
    /// What the wider sweep taught (and the single date could not): the
    /// cheap pair snaps to the absolute 30-min grid and *straddles* `now`
    /// (the GOTCHA on `tidePinRisingHybrid`), so its answer is the window's
    /// net motion. When a turn falls inside that window the hybrid can
    /// honestly disagree with the exact-at-`now` baseline — a timing lag
    /// bounded by the window, self-correcting on the next style build, with
    /// the detail view authoritative. The original probes all sat 20 min
    /// into their window, the one grid phase where that band is narrowest
    /// (~0.5% of samples land in it at other phases). So the assertion that
    /// closes #15 is split to match the design: mismatches AWAY from a turn
    /// — the threshold trusting sampling noise, the failure the sweep was
    /// hunting — must be zero; near-turn straddle lag gets a rate bound.
    func testHybridDirectionHasFullCoverageAndMatchesBaseline() {
        let base = Date(timeIntervalSince1970: 1_785_000_000)
        var checkTimes: [Date] = []
        for (day, shiftMinutes) in [(0, 0.0), (7, 11.0), (13, 23.0), (20, 37.0), (27, 49.0)] {
            let dayStart = base.addingTimeInterval(Double(day) * 86_400)
            for hour in [0.0, 6.0, 12.0, 18.0] {
                checkTimes.append(dayStart.addingTimeInterval(hour * 3600 + shiftMinutes * 60))
            }
        }
        var resolved = 0
        var nearTurnLags = 0
        var mismatches: [String] = []
        for record in TideStationRecord.all {
            for now in checkTimes {
                let baseline = record.cardState(at: now).rising
                guard let hybrid = tidePinRisingHybrid(record, at: now) else { continue }
                resolved += 1
                guard hybrid != baseline else { continue }
                let turnNearby = !record.engineStation.extremes(
                    from: now.addingTimeInterval(-PIN_TIDE_DIFF_DT),
                    to: now.addingTimeInterval(PIN_TIDE_DIFF_DT)).isEmpty
                if turnNearby {
                    nearTurnLags += 1
                } else {
                    mismatches.append("\(record.id) at \(now): hybrid=\(hybrid) baseline=\(baseline)")
                }
            }
        }
        let checked = TideStationRecord.all.count * checkTimes.count
        let coveragePct = Double(resolved) / Double(checked) * 100
        print(String(format: "Hybrid direction: %d/%d resolved a tone (%.1f%% coverage), "
                     + "%d lagged within one window of a turn, %d disagreed away from one",
                     resolved, checked, coveragePct, nearTurnLags, mismatches.count))
        XCTAssertGreaterThan(coveragePct, 99.0, "the hybrid must not quietly fall back to mostly-neutral again")
        XCTAssertTrue(mismatches.isEmpty,
                      "hybrid trusted a wrong-signed sample with no turn within its window: \(mismatches.prefix(10))")
        XCTAssertLessThan(Double(nearTurnLags) / Double(resolved), 0.01,
                          "near-turn straddle lag should stay a rare, bounded timing artifact")
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

    /// Bathymetry offline (openwatersio/seascape#121). Depth used to be the one
    /// thing that vanished with the signal: the app composed the remote
    /// Seascape style when it could reach it, so you got soundings in the
    /// marina and lost them offshore, which is backwards from where they
    /// matter. `seascape.pmtiles` puts the Salish box in the bundle.
    ///
    /// Draw order is the assertion that earns its keep: depth is UNDER the
    /// seamap marks and OVER the land floor. A buoy hidden behind a depth-area
    /// fill is a chart that lies about what is there.
    func testFallbackStyleCarriesBathymetryUnderTheChart() throws {
        let style = localFallbackStyle(landUrl: "", uscaUrl: "")
        let sources = try XCTUnwrap(style["sources"] as? [String: Any])
        let seascape = try XCTUnwrap(sources["seascape-vector"] as? [String: Any],
                                     "no bundled bathymetry: run tools/build-seascape.sh")
        XCTAssertTrue((seascape["url"] as? String)?.hasPrefix("pmtiles://") == true,
                      "bathymetry must read the bundle, not the network")

        let ids = try XCTUnwrap(style["layers"] as? [[String: Any]]).map { $0["id"] as? String ?? "" }
        let depth = try XCTUnwrap(ids.firstIndex(of: "depth-areas"), "depth areas are not drawn")
        let contours = try XCTUnwrap(ids.firstIndex(of: "contour-lines"), "contours are not drawn")
        XCTAssertLessThan(depth, contours, "contours must draw over the depth fill, not under it")
        let land = try XCTUnwrap(ids.firstIndex(of: "land-usca"), "the continental floor is missing")
        XCTAssertLessThan(land, depth, "depth must draw over the land floor")
        let seamapIds = Set((offlineLayers("seamap", sprite: "freenauticalchart",
                                           attribution: "© Open Waters: Seamap © OpenStreetMap contributors")?.layers ?? [])
            .compactMap { $0["id"] as? String })
        if let firstMark = ids.firstIndex(where: { seamapIds.contains($0) }) {
            XCTAssertLessThan(contours, firstMark, "the chart marks must draw over bathymetry")
        }
        let pins = try XCTUnwrap(ids.firstIndex(of: "station-clusters"))
        XCTAssertLessThan(contours, pins, "station pins must stay on top")
    }

    /// #29: the offline chart carries its own fontstack, so seamap labels and
    /// station names render with no network at all. The invariant that earns
    /// its keep is the last loop: every fontstack any offline layer references
    /// must have its glyph PBFs in the bundle — a slice regenerated with a new
    /// font, or a deleted PBF, fails here instead of shipping silent blank
    /// labels.
    func testFallbackStyleBundlesGlyphsForItsLabels() throws {
        let style = localFallbackStyle(landUrl: "", uscaUrl: "")
        let glyphs = try XCTUnwrap(style["glyphs"] as? String,
                                   "no bundled fontstack: run tools/build-seamap.sh")
        XCTAssertTrue(glyphs.hasPrefix("file://"),
                      "offline glyphs must read the bundle, not the network")
        let layers = try XCTUnwrap(style["layers"] as? [[String: Any]])
        XCTAssertTrue(layers.contains { ($0["id"] as? String) == "station-labels" },
                      "with glyphs bundled, station-name labels must be on")
        XCTAssertTrue(layers.contains { ($0["id"] as? String) == "station-cluster-count" },
                      "with glyphs bundled, clusters must carry their count")
        let seamarkLabel = try XCTUnwrap(layers.first { ($0["id"] as? String) == "seamark-label" },
                                         "the seamap slice is missing its label layer")
        XCTAssertNotNil((seamarkLabel["layout"] as? [String: Any])?["text-field"],
                        "the slice must keep text-* now that glyphs ship")
        for layer in layers {
            guard let font = (layer["layout"] as? [String: Any])?["text-font"] as? [String]
            else { continue }
            for stack in font {
                XCTAssertNotNil(Bundle.main.url(forResource: "\(stack)-0-255", withExtension: "pbf"),
                                "\(layer["id"] ?? "?") wants \(stack) but its glyphs are not bundled")
            }
        }
    }

    /// #30: the chart and the bathymetry used to stop at the Salish box, so a
    /// station in Puget Sound opened onto seamarks and depth and one in San
    /// Francisco onto bare land. Four tilesets now — the same shape as the two
    /// land ones, twice over: seamap national z9 under Salish z12, seascape
    /// national z6 under Salish z12.
    ///
    /// The assertion that earns its keep is the draw order. Both cuts of each
    /// pair carry home water, and the detailed one has to be on top, or the
    /// Salish Sea takes its chart from the coarse tileset — two thirds of its
    /// rocks gone, with nothing on screen to say so.
    func testFallbackStyleCarriesTheChartPastTheSalishBox() throws {
        let style = localFallbackStyle(landUrl: "", uscaUrl: "")
        let sources = try XCTUnwrap(style["sources"] as? [String: Any])
        let layers = try XCTUnwrap(style["layers"] as? [[String: Any]])
        let drawn = { (source: String) in
            layers.indices.filter { (layers[$0]["source"] as? String) == source }
        }
        let floor = try XCTUnwrap(layers.firstIndex { ($0["id"] as? String) == "land-usca" })

        for (wide, detailed, script) in [("seamap-natl", "seamap", "build-seamap.sh"),
                                         ("seascape-natl", "seascape-vector", "build-seascape.sh")] {
            let source = try XCTUnwrap(sources[wide] as? [String: Any],
                                       "no national \(wide): run tools/\(script)")
            XCTAssertTrue((source["url"] as? String)?.hasPrefix("pmtiles://") == true,
                          "\(wide) must read the bundle, not the network")
            let national = drawn(wide), salish = drawn(detailed)
            let lastNational = try XCTUnwrap(national.max(), "\(wide) draws nothing")
            let firstSalish = try XCTUnwrap(salish.min(), "\(detailed) draws nothing")
            XCTAssertLessThan(lastNational, firstSalish,
                              "home water must draw \(detailed) over \(wide), not under it")
            XCTAssertLessThan(floor, lastNational, "\(wide) must draw over the land floor")

            // Neither seamap artifact carries the `land` source-layer — the app
            // draws land from its own two tilesets, and seamap's was 92% of the
            // national extract for a second, coarser copy of what land.pmtiles
            // already has.
            for i in national + salish {
                XCTAssertNotEqual(layers[i]["source-layer"] as? String, "land",
                                  "\(layers[i]["id"] ?? "?") reads a source-layer the extract does not have")
            }
        }
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
