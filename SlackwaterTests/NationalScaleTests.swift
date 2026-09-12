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
import MapLibre
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
        // 13 fitted + 9 online. M55 took the gates national: Great Bras d'Or
        // and Quatsino fit, Nakwakto and Masset Sound ship online.
        XCTAssertEqual(ChsCurrentGateInfo.all.count, 22,
                       "the 13 validated gates (M47/M53/M55) plus the 9 online fit-rejects")
        XCTAssertEqual(Set(StationItem.all.map(\.id)).count, StationItem.all.count,
                       "two stations sharing an id is a duplicate row, pin and model file")
        let hidden = CurrentStationRecord.all.filter { $0.referenceOnly == true }.count
        XCTAssertEqual(hidden, 13, "reference-only bins")
        XCTAssertEqual(currents, CurrentStationRecord.all.count - hidden, "every non-hidden record is listed once")
    }

    /// Both coasts, both countries, and a real curve at the far end of one —
    /// the bundle is not quietly a Pacific bundle with extras.
    func testFarStationsAreSearchableAndPredictable() throws {
        for query in ["boston", "san francisco", "key west", "halifax", "honolulu"] {
            XCTAssertFalse(StationItem.search(query, near: firstRunFix).isEmpty, "\"\(query)\" found nothing")
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
            let shown = StationItem.search(q, near: firstRunFix)
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
        let after = elapsed { for q in queries { _ = StationItem.search(q, near: firstRunFix) } }
        print(String(format: "M53 search · %d stations · %d queries: %.1f ms -> %.1f ms; " +
                     "worst result list %d rows -> %d",
                     StationItem.all.count, queries.count, before * 1000, after * 1000,
                     worstBefore, StationItem.searchLimit))
        XCTAssertGreaterThan(worstBefore, 500, "pick a query that used to flood the screen")
        XCTAssertLessThan(after / Double(queries.count), 0.016 * perfScale,
                          "a keystroke must land inside one 60 fps frame")
    }

    /// The Tides/Currents narrowing: a series-filtered search returns only
    /// that series and still fills its rows (the filter runs inside the scan,
    /// not over the truncated results), and the nearest-of-series helper —
    /// what the nearby links and the widget cache lean on — answers in kind.
    func testSeriesFilterNarrowsSearchAndNearest() throws {
        let currents = StationItem.search("", near: firstRunFix, series: .current)
        XCTAssertEqual(currents.count, StationItem.searchLimit)
        XCTAssertTrue(currents.allSatisfy { $0.series == .current })
        let tides = StationItem.search("port", near: firstRunFix, series: .tide)
        XCTAssertFalse(tides.isEmpty)
        XCTAssertTrue(tides.allSatisfy { $0.series == .tide })

        let nearest = try XCTUnwrap(
            StationItem.nearest(.current, toLat: firstRunFix.lat, lon: firstRunFix.lon))
        XCTAssertEqual(nearest.item.series, .current)
        // The first-run fix is Victoria Harbour — current-gate country.
        XCTAssertLessThan(nearest.km, nearbyStationRadiusKm)
    }

    /// A detail's Nearby rows: nearest first, never the station itself, and
    /// only the picked series when there is one.
    func testNearbyRanksNeighboursAndHonoursTheSeries() throws {
        let here = try XCTUnwrap(
            StationItem.nearest(.tide, toLat: firstRunFix.lat, lon: firstRunFix.lon)).item
        let any = StationItem.nearby(here, series: nil)
        XCTAssertEqual(any.count, 6)
        XCTAssertFalse(any.contains(here))
        let km = any.map { $0.km(fromLat: here.latitude, lon: here.longitude) }
        XCTAssertEqual(km, km.sorted())

        let currents = StationItem.nearby(here, series: .current)
        XCTAssertEqual(currents.count, 6)
        XCTAssertTrue(currents.allSatisfy { $0.series == .current })
    }

    func testBearingIsTheInitialTrueCourse() {
        XCTAssertEqual(bearingDeg(0, 0, 1, 0), 0, accuracy: 1e-9)
        XCTAssertEqual(bearingDeg(0, 0, 0, 1), 90, accuracy: 1e-9)
        XCTAssertEqual(bearingDeg(0, 0, -1, 0), 180, accuracy: 1e-9)
        XCTAssertEqual(compass16(bearingDeg(0, 0, 0, -1)), "W")
        // Victoria to Friday Harbor runs east-northeast across Haro Strait.
        XCTAssertEqual(compass16(bearingDeg(48.4235, -123.3705, 48.5467, -123.0128)), "ENE")
    }

    /// The My Location cards cover both series where both exist, and never
    /// advertise a series a coast doesn't have: Victoria gets a tide and a
    /// current card, Portsmouth (nearest current: another continent) gets one.
    func testHeroItemsCoverBothSeriesOnlyWhereBothAreNear() {
        let victoria = StationItem.heroItems(
            ranked: StationItem.rankedByDistance(StationItem.all,
                                                 lat: firstRunFix.lat, lon: firstRunFix.lon),
            lat: firstRunFix.lat, lon: firstRunFix.lon)
        XCTAssertEqual(victoria.count, 2)
        XCTAssertEqual(Set(victoria.map(\.series)), [.tide, .current])

        let portsmouth = StationItem.heroItems(
            ranked: StationItem.rankedByDistance(StationItem.all, lat: 50.80, lon: -1.11),
            lat: 50.80, lon: -1.11)
        XCTAssertEqual(portsmouth.map(\.series), [.tide])
    }

    /// The list ranks the catalog inside `body`, which SwiftUI re-evaluates on
    /// every fit, favourite and unit switch. Memoised, a re-render is free.
    @MainActor
    func testRankedCatalogIsMemoisedPerFix() {
        let fix = firstRunFix
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
    ///
    /// The 0.30s budget was set at the M53 milestone against 3,125 bundled
    /// stations. World coverage (Task 5) took the heavy tide/current path to
    /// 1.56× in station count but **2.36×** in total constituent volume
    /// (2,776 stations × 39.72 avg constituents vs the pre-world 1,473 × 31.68
    /// — measured by diffing `stations.json` at the commit before world
    /// coverage landed against today's), which is the quantity `Station.init`
    /// and `heights()` actually do work proportional to. The number moved
    /// because the data got legitimately bigger, not because this code got
    /// slower — no quadratic or repeated-per-station work was found in
    /// `Station`/`tidePinRisingHybrid`/`currentPinTone`.
    ///
    /// What DID regress, and is now fixed separately: `MapStyler.init`
    /// rebuilt this whole pass from scratch on every single pin focus
    /// (`.id(mapFocusToken)` remounts `MapViewRepresentable` on every tap) —
    /// paid again and again in one map session, not once. `PinFeaturesCache`
    /// (`MapPinState.swift`) now caches across those remounts, invalidating on
    /// a real `chsTones` change or a moved time bucket; this test forces a
    /// cold build via `resetForTesting()` so it keeps measuring the one-call
    /// cost that regressed, not a cache hit.
    ///
    /// Re-budgeted from 0.30s to 0.75s: measured 569.3ms cold on this
    /// machine at 4,699 total stations (all kinds), ~32% headroom above that
    /// — enough to absorb shared-machine variance without sitting on the
    /// edge, tight enough that a future 2×+ regression still trips it.
    ///
    /// Re-budgeted again to 1.45s for #229: 1,083.7ms cold at 6,707 stations.
    /// The 2,017 subordinate tide stations have no cheap two-sample path —
    /// a subordinate's curve is only defined by its extremes — so each pays
    /// the exact 13h search (~0.26ms here), about half the growth; the rest
    /// is the catalogue simply being 43% bigger.
    func testPinLayerBuildsInsideAFrame() {
        PinFeaturesCache.shared.resetForTesting()
        let build = elapsed { _ = stationShapeSource() }
        print(String(format: "M53 pin source · %d stations: %.1f ms", StationItem.all.count, build * 1000))
        XCTAssertLessThan(build, 1.45 * perfScale)
    }

    /// The regression this exists for: a stale CHS tone surviving after a fit
    /// lands would be a worse bug than the rebuild cost `PinFeaturesCache`
    /// exists to avoid. Proves invalidation, not just caching — a test that
    /// only checked "the second call is fast" would pass just as happily on
    /// a cache that never updates.
    func testPinFeaturesCacheInvalidatesOnRealChsToneChange() throws {
        PinFeaturesCache.shared.resetForTesting()
        let chsPort = try XCTUnwrap(StationItem.all.first { $0.pinKind == "chs" })

        func stateFor(_ geojson: [String: Any], id: String) -> String? {
            let features = geojson["features"] as? [[String: Any]] ?? []
            let props = features.first { ($0["properties"] as? [String: Any])?["id"] as? String == id }
            return (props?["properties"] as? [String: Any])?["state"] as? String
        }

        // Cold: nothing synced, this CHS station reads "unknown".
        let cold = PinFeaturesCache.shared.snapshot()
        XCTAssertEqual(stateFor(cold, id: chsPort.id), "unknown")

        // A same-value push (no real sync progress) must be a no-op — the
        // object identity check below only means something if this doesn't
        // also happen to rebuild.
        let stillEmpty = PinFeaturesCache.shared.update(tones: [:])
        XCTAssertEqual(stateFor(stillEmpty, id: chsPort.id), "unknown")

        // A real tone lands for exactly this station: the cache must
        // invalidate and the NEXT read must reflect it — not the stale
        // "unknown" from the cold build.
        let synced = PinFeaturesCache.shared.update(tones: [chsPort.id: "flood"])
        XCTAssertEqual(stateFor(synced, id: chsPort.id), "flood",
                       "a real CHS tone must invalidate the cache, not be served stale")

        // And a subsequent plain snapshot() (what a remounted MapStyler asks
        // for) must see the same resolved tone, not fall back to blank.
        let afterRemount = PinFeaturesCache.shared.snapshot()
        XCTAssertEqual(stateFor(afterRemount, id: chsPort.id), "flood",
                       "a remount must reuse the last-known real tone, not flash back to unknown")
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
        // The clustering ceiling and the opening camera are separate constants
        // whose relationship is the invariant: the discovery camera must open
        // on tappable stations, not clusters.
        XCTAssertLessThan(Double(CLUSTER_MAX_ZOOM), SALISH_ZOOM)
    }

    /// The runtime pin layers (offline-chart-packs spec §1/§5: the basemap is
    /// a style URL the app does not own; pins go in through the runtime API).
    /// Both tap layers must exclude clusters, or every cluster draws twice —
    /// and the tap handler hit-tests these exact identifiers.
    func testRuntimePinLayersCarryTheTapContract() throws {
        let layers = stationPinLayers(source: stationShapeSource())
        let byId = Dictionary(uniqueKeysWithValues: layers.map { ($0.identifier, $0) })
        for id in ["station-clusters", "station-cluster-count", "station-pins-current",
                   "station-pins-tide-plate", "station-pins-tide", "station-labels"] {
            XCTAssertNotNil(byId[id], "\(id) missing from the runtime pin layers")
        }
        XCTAssertNotNil((byId["station-pins-current"] as? MLNVectorStyleLayer)?.predicate,
                        "the current-pin layer must exclude clusters, or every cluster draws twice")
        XCTAssertNotNil((byId["station-pins-tide"] as? MLNVectorStyleLayer)?.predicate,
                        "the tide-pin layer must exclude clusters, or every cluster draws twice")
        // The labels ride the basemap's own fontstack, so offline packs cache
        // its glyph ranges as part of the style's needs. A stack of our own
        // here would be blank offline.
        // The getter normalizes the constant to an aggregate expression, so
        // assert on the stack's presence rather than expression equality.
        let labels = try XCTUnwrap(byId["station-labels"] as? MLNSymbolStyleLayer)
        XCTAssertTrue(String(describing: labels.textFontNames).contains("noto_sans_bold"),
                      "station labels must use the basemap style's own fontstack")
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
        for (place, fix, ports, gates) in [("Victoria", firstRunFix, 6, 3),
                                           ("Halifax", (lat: 44.65, lon: -63.57), 6, 0),
                                           ("Boston", (lat: 42.3601, lon: -71.0589), 0, 0),
                                           ("Detroit", (lat: 42.3314, lon: -83.0458), 0, 0)] {
            let set = ChsFitService.autoFitSet(lat: fix.lat, lon: fix.lon)
            let seconds = set.reduce(0) { $0 + $1.estimatedSeconds }
            let far = set.map { distanceKm($0.latitude, $0.longitude, fix.lat, fix.lon) }.max() ?? 0
            print(String(format: "M53 auto-fit from %@: %d ports + %d gates, ~%.1f min, within %.0f km",
                         place, set.filter { !$0.isCurrent }.count, set.filter(\.isCurrent).count,
                         seconds / 60, far))
            XCTAssertEqual(set.filter { !$0.isCurrent }.count, ports,
                           "\(place) auto-fits only the ports within reach of the fix")
            // Halifax's gate count is 0 for the honest reason rather than the
            // accidental one: since M55 there IS a CHS gate on the Atlantic
            // (Great Bras d'Or), it is simply ~305 km away and the auto-fit
            // radius is 150 km. Distance decides this, not an ocean the bundle
            // happens not to reach.
            XCTAssertEqual(set.filter(\.isCurrent).count, gates,
                           "\(place) auto-fits only the passes within reach of the fix")
            XCTAssertLessThan(seconds, 10 * 60, "\(place)'s first run must not be an afternoon")
            XCTAssertLessThanOrEqual(far, ChsFitService.autoFitRadiusKm,
                                     "\(place) downloads nothing beyond the radius")
        }
    }

    /// #205: the radius guards ports as well as gates. Boston and Detroit are
    /// the cases the Victoria/Halifax pair above cannot see, because both of
    /// those fixes sit on top of Canadian water — an unguarded port budget
    /// looks identical to a guarded one from inside the country.
    ///
    /// Boston is the reported fix. Its nearest CHS ports are Montréal Jetée #1
    /// at 402 km — a river gauge 400 km inland — and Seal Cove NB across the
    /// Gulf of Maine, while the nearest station in its ranked list is NOAA
    /// Boston at 1 km. Downloading Canada there is pure waste, and the ranking
    /// proves it can never be seen: the first CHS entry is ~385th.
    @MainActor
    func testFarFromCanadaDownloadsNothing() {
        for (place, fix) in [("Boston", (lat: 42.3601, lon: -71.0589)),
                             ("Detroit", (lat: 42.3314, lon: -83.0458)),
                             ("Denver", (lat: 39.7392, lon: -104.9903)),
                             ("Austin", (lat: 30.2672, lon: -97.7431))] {
            XCTAssertTrue(ChsFitService.autoFitSet(lat: fix.lat, lon: fix.lon).isEmpty,
                          "\(place) is far from every CHS station and must fit none of them")
            XCTAssertTrue(ChsFitService.autoPrefetchGates(lat: fix.lat, lon: fix.lon).isEmpty,
                          "\(place) must fetch no online gate windows either")
            let (ranked, _) = RankedStations.near(lat: fix.lat, lon: fix.lon)
            let firstChs = ranked.prefix(5).contains { item in
                switch item {
                case .chs, .chsCurrent, .chsGate: return true
                case .tide, .current: return false
                }
            }
            XCTAssertFalse(firstChs, "\(place): no CHS row reaches the first screen, so none is left uncovered")
        }
    }

    /// The manager's bulk currents action, and why #8 needs no region picker.
    ///
    /// The radius is right for ports and leaves gates stranded: Great Bras
    /// d'Or is 305 km from Halifax, so an Atlantic fix auto-fits zero passes,
    /// and a passage planned from the dock crosses gates well past 150 km.
    /// Every fittable gate in the country is 13 stations and minutes — the
    /// 1,058 ports are hours — so the whole set is the selection, and "the
    /// Gulf Islands" never has to become a place you pick.
    @MainActor
    func testEveryCanadianGateIsOneAffordableDownload() {
        let service = ChsFitService.shared
        let offered = service.gatesToDownload
        XCTAssertTrue(offered.allSatisfy(\.isCurrent),
                      "the bulk action is currents only — ports are the hours-long series")
        let everyGate = offered + service.queue.jobs.filter(\.isCurrent)
        XCTAssertEqual(Set(everyGate.map(\.id)),
                       Set(ChsCurrentGateInfo.all.filter { !$0.isOnline }.map(\.id)),
                       "every fittable gate is either already queued or one tap from it")
        XCTAssertTrue(everyGate.contains { $0.id == "chs-great-bras-dor" },
                      "the Atlantic gate no fix is ever within 150 km of is the point of this")
        let seconds = everyGate.reduce(0) { $0 + $1.estimatedSeconds }
        XCTAssertLessThan(seconds, 30 * 60,
                          "all of Canada's gates must stay minutes, not an afternoon")
        print(String(format: "#8 bulk currents: %d gates, ~%.0f min", everyGate.count, seconds / 60))
    }

    /// A US fix near the border is the case the radius must NOT break: a Puget
    /// Sound sailor works Canadian water daily, and Bellingham has 84 CHS ports
    /// and Boundary Pass inside 150 km.
    @MainActor
    func testBorderFixKeepsCanadianCoverage() {
        for (place, fix) in [("Bellingham", (lat: 48.7519, lon: -122.4787)),
                             ("Port Angeles", (lat: 48.1181, lon: -123.4307)),
                             ("Eastport ME", (lat: 44.9062, lon: -66.9899))] {
            let set = ChsFitService.autoFitSet(lat: fix.lat, lon: fix.lon)
            XCTAssertEqual(set.filter { !$0.isCurrent }.count, ChsFitService.autoFitPorts,
                           "\(place) is inside the radius and must still get its ports")
        }
        XCTAssertFalse(ChsFitService.autoFitSet(lat: 48.7519, lon: -122.4787).filter(\.isCurrent).isEmpty,
                       "Bellingham has Salish passes in reach and must fit them")
    }

    /// #178, second half: what the first screen SHOWS and what a first run
    /// DOWNLOADS have to be the same stations. The hero and the four Near Me
    /// rows are the entire first screen of a Canadian first run, and every CHS
    /// entry in them must be covered — by the fit queue if it can be fitted, by
    /// the online prefetch if it cannot. An uncovered one sits on "Tap to
    /// download" with nothing on its way, which is the reported bug.
    ///
    /// The online half is why this is not just a restatement of `autoFitSet`:
    /// Tillicum Bridge is 3.4 km from downtown Victoria and Second Narrows is
    /// in Vancouver harbour, and `candidates` excludes both at the source.
    @MainActor
    func testFirstScreenIsEntirelyCoveredByWhatTheFirstRunDownloads() {
        // `StationListView.locatedSections`: hero is `ranked.first`, Near Me is
        // the next four when there is a fix.
        let firstScreen = 5
        for (place, fix) in [("Victoria", firstRunFix),
                             ("Vancouver", (lat: 49.2867, lon: -123.1120)),
                             ("Nanaimo", (lat: 49.1659, lon: -123.9401))] {
            let (ranked, _) = RankedStations.near(lat: fix.lat, lon: fix.lon)
            let covered = Set(ChsFitService.autoFitSet(lat: fix.lat, lon: fix.lon).map(\.id))
                .union(ChsFitService.autoPrefetchGates(lat: fix.lat, lon: fix.lon).map(\.id))
            for item in ranked.prefix(firstScreen) {
                switch item {
                // Bundled: constituents ship in the app, the card renders a
                // number on frame one and never shows a status strip at all.
                case .tide, .current: continue
                // A derived gate rides its reference port's fit, so what has
                // to be covered is that port, not this id.
                case .chsGate(let gate):
                    XCTAssertTrue(covered.contains(gate.reference),
                                  "\(place): \(gate.name) is on the first screen, its reference port is not downloading")
                case .chs, .chsCurrent:
                    XCTAssertTrue(covered.contains(item.id),
                                  "\(place): \(item.name) is on the first screen and nothing downloads it")
                }
            }
        }
    }

    /// The online prefetch keeps the auto-fit budget's shape — nearest first,
    /// capped, and radius-limited — so it cannot become the bulk download M53
    /// removed. Halifax is the check that matters: the nearest online gate is
    /// a coast away and a Nova Scotian must fetch none of them.
    @MainActor
    func testOnlinePrefetchIsBoundedLikeTheFitBudget() {
        let victoria = ChsFitService.autoPrefetchGates(lat: firstRunFix.lat, lon: firstRunFix.lon)
        XCTAssertFalse(victoria.isEmpty, "Victoria's nearest pass is 3.4 km away and must not be left to a tap")
        XCTAssertEqual(victoria.first?.id, "chs-tillicum-bridge",
                       "nearest first, like every other download decision")
        XCTAssertLessThanOrEqual(victoria.count, ChsFitService.autoFitGates)
        XCTAssertTrue(victoria.allSatisfy(\.isOnline), "a fittable gate belongs in the queue, not here")
        for gate in victoria {
            XCTAssertLessThanOrEqual(distanceKm(gate.latitude, gate.longitude, firstRunFix.lat, firstRunFix.lon),
                                     ChsFitService.autoFitRadiusKm)
        }
        XCTAssertTrue(ChsFitService.autoPrefetchGates(lat: 44.65, lon: -63.57).isEmpty,
                      "Halifax fetches no Salish passes")
    }

    /// A Canadian station outside the auto-fit set is visible, searchable, says
    /// the thing that is actually true about it — and downloading it is one tap.
    @MainActor
    func testOnDemandStationIsVisibleAndSaysSo() throws {
        let service = ChsFitService.shared
        let far = try XCTUnwrap(ChsStationInfo.all.first {
            !service.isQueued($0.id) && $0.region == "Atlantic Coast"
        })
        XCTAssertTrue(StationItem.search(far.name.lowercased(), near: firstRunFix).contains { $0.id == far.id },
                      "an undownloaded station still has to be findable")
        XCTAssertEqual(cardStatus(id: far.id), .notDownloaded,
                       "it must not claim to be queued when it isn't")
        service.promote(far.id)   // what ChsDetailView does on appear
        XCTAssertTrue(service.isQueued(far.id))
        XCTAssertEqual(service.queue.position(far.id), 1, "what you opened is next up")
        XCTAssertTrue([.queued, .offline].contains(cardStatus(id: far.id)),
                      "once queued it stops saying \"tap to download\"")
    }
}
