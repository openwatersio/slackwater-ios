// Slackwater — GPL v3. Validated CHS current gates (M47): bundled identity,
// the flood-axis projection, and the fit→events math — a fitted model's
// record drives TideEngine's CurrentStation exactly like a bundled NOAA
// station (slacks at velocity zeros, maxima signed flood/ebb).
import XCTest
@testable import Slackwater
import TideEngine

final class ChsCurrentGateTests: XCTestCase {

    // MARK: - Bundled identity (chs-current-gates.json, generated from the registry)

    func testBundledGatesAreRegistryKeysWithBundledPairings() {
        for gate in ChsCurrentGateInfo.all {
            XCTAssert(gate.id.hasPrefix("chs-"), "\(gate.id) is not a registry key")
            XCTAssertEqual(gate.timezone, "America/Vancouver")
            if let ref = gate.tideReference {
                // Dual-track needs the port on this device: it must be a
                // bundled CHS tide port the app fits.
                XCTAssert(ChsStationInfo.all.contains { $0.id == ref },
                          "\(gate.id) pairs \(ref), not in chs-stations.json")
            }
        }
    }

    func testDoddNarrowsShipsAndIsSearchable() throws {
        let dodd = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == "chs-dodd-narrows" },
                                 "Dodd Narrows missing from chs-current-gates.json")
        XCTAssertEqual(dodd.name, "Dodd Narrows")
        for query in ["dodd", "nanaimo"] {
            XCTAssert(StationItem.search(query).contains { $0.id == dodd.id },
                      "search '\(query)' did not find Dodd Narrows")
        }
    }

    // MARK: - Flood-axis projection (speed · cos(dir − floodDirection))

    func testProjectionSignsAlongTheFloodAxis() {
        let speeds = [ChsSample(t: 0, v: 3), ChsSample(t: 1, v: 2), ChsSample(t: 2, v: 1)]
        let dirs = [ChsSample(t: 0, v: 45), ChsSample(t: 1, v: 225)]  // t:2 has no direction
        let out = ChsFitService.project(speeds: speeds, dirs: dirs, floodDirection: 45)
        XCTAssertEqual(out.count, 2, "sample without a direction stamp must drop")
        XCTAssertEqual(out[0].v, 3, accuracy: 1e-12)   // dir == flood → +speed
        XCTAssertEqual(out[1].v, -2, accuracy: 1e-12)  // dir == ebb (flood+180) → −speed
    }

    // MARK: - Fit → events: the record's engine finds slacks and signed maxima

    func testFittedModelRecordPredictsSlackAndSignedMaxima() throws {
        let gate = ChsCurrentGateInfo(
            id: "chs-test-gate", name: "Test Gate", region: "Test", aliases: [],
            latitude: 49, longitude: -123, timezone: "America/Vancouver", tideReference: nil,
            fitDays: 210, provisionalSlackMinutes: 35)
        // A pure M2 current, 2 kn peak: slack every ~6.21 h, alternating maxima.
        let model = ChsCurrentModel(
            stationID: gate.id, iwlsID: "x", iwlsName: "x", fittedAt: .now,
            fitStartMs: 0, fitEndMs: 0, fitDays: 210, floodDirection: 45, ebbDirection: 225,
            offset: 0, rms: 0.01,
            constituents: [.init(name: "M2", amplitude: 2, phase: 0)])
        let record = gate.record(with: model)
        XCTAssertEqual(record.floodDirection, 45)
        XCTAssert(record.isChs)

        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let events = record.engineStation.events(from: start, to: start.addingTimeInterval(25 * 3600))
        let slacks = events.filter { $0.kind == .slack }
        let floods = events.filter { $0.kind == .maxFlood }
        let ebbs = events.filter { $0.kind == .maxEbb }
        // ~2 M2 cycles in 25 h: ~4 slacks (two zero crossings per 12.42 h
        // cycle), ~2 of each maximum (±1 at the window edges).
        XCTAssert(slacks.count >= 3, "expected ~4 slacks, got \(slacks.count)")
        XCTAssert(floods.count >= 1 && ebbs.count >= 1)
        // The slack finder bisects to 1 s, so |v| is ~2.5e-5 kn, not exactly 0.
        for s in slacks { XCTAssertEqual(s.speed, 0, accuracy: 1e-3) }
        for f in floods { XCTAssertEqual(f.speed, 2, accuracy: 0.1) }
        for e in ebbs { XCTAssertEqual(e.speed, -2, accuracy: 0.1) }
        // Events alternate slack / maximum — a maximum sits between slacks.
        for (a, b) in zip(events, events.dropFirst()) {
            XCTAssert((a.kind == .slack) != (b.kind == .slack),
                      "events must alternate slack and maxima")
        }
    }

    // MARK: - Store round-trip (the model that survives relaunch, offline)

    func testCurrentModelStoreRoundTrip() throws {
        let model = ChsCurrentModel(
            stationID: "chs-test-store", iwlsID: "abc", iwlsName: "Test", fittedAt: .now,
            fitStartMs: 1, fitEndMs: 2, fitDays: 210, floodDirection: 355, ebbDirection: 155,
            offset: 0.1, rms: 0.37,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 123)])
        try ChsModelStore.saveCurrent(model)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.currentUrl(model.stationID)) }
        let loaded = try XCTUnwrap(ChsModelStore.loadCurrent("chs-test-store"))
        XCTAssertEqual(loaded.floodDirection, 355)
        XCTAssertEqual(loaded.constituents.first?.phase, 123)
        // The gate store must never shadow a port model of the same key.
        XCTAssertNil(ChsModelStore.load("chs-test-store"))
    }

    // MARK: - The id the star and Recents write (fresh-install favorite bug)

    /// The favorite star and the Recents record must write the id the LIST
    /// resolves through `StationItem.byId`. NOAA current stations are
    /// namespaced "current:<id>" (Friday Harbor has both a tide and a current
    /// station); CHS gates key the catalog by their bare registry id. Build 20
    /// wrote the NOAA prefix onto CHS ids too, minting favorites and recents
    /// no list section could resolve — starred stations silently never
    /// appeared.
    func testItemIdResolvesInTheCatalog() throws {
        // Every bundled NOAA current station: prefixed, and resolvable.
        let noaa = try XCTUnwrap(CurrentStationRecord.all.first)
        XCTAssertEqual(noaa.itemId, "current:" + noaa.id)
        XCTAssertNotNil(StationItem.byId[noaa.itemId])

        // A fitted CHS gate record (the shape ChsFitService hands the detail):
        // bare registry id, and resolvable.
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first)
        let record = CurrentStationRecord(
            id: gate.id, name: gate.name, region: gate.region, aliases: [],
            latitude: gate.latitude, longitude: gate.longitude,
            timezone: "America/Vancouver", floodDirection: 355, ebbDirection: 155,
            meanFlow: 0, tideReference: nil,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        XCTAssertEqual(record.itemId, gate.id, "a CHS gate's catalog id is bare — no NOAA prefix")
        XCTAssertNotNil(StationItem.byId[record.itemId])
    }

    // MARK: - The fetched window (online gates: official CHS predictions, no fit)

    func testOnlineWindowStoreRoundTrip() throws {
        let window = ChsOnlineWindow(
            stationID: "chs-test-online", iwlsName: "Test Online Station",
            timezone: "America/Vancouver", fetchedAt: .now,
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1_000_000),
            floodDirection: 45, ebbDirection: 225, times: [0, 900], speeds: [1.5, -1.5])
        try ChsModelStore.saveOnline(window)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(window.stationID)) }
        let loaded = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-online"))
        XCTAssertEqual(loaded.floodDirection, 45)
        XCTAssertEqual(loaded.times, [0, 900])
        XCTAssertEqual(loaded.speeds, [1.5, -1.5])
        // The online store must never shadow a fitted model of the same key.
        XCTAssertNil(ChsModelStore.loadCurrent("chs-test-online"))
        XCTAssertNil(ChsModelStore.load("chs-test-online"))
    }

    func testOnlineWindowCoversStrip() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now0 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12)))
        let today0 = cal.startOfDay(for: now0)
        let need = Timeline.window(anchor: today0, today: today0)

        func window(start: Date, end: Date) -> ChsOnlineWindow {
            ChsOnlineWindow(stationID: "chs-test-online", iwlsName: "Test", timezone: "America/Vancouver",
                            fetchedAt: .now, start: start, end: end,
                            floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
        }

        // Inside: a window wider than the strip needs still covers it.
        let padded = window(start: need.start.addingTimeInterval(-3600), end: need.end.addingTimeInterval(3600))
        XCTAssert(padded.covers(anchor: today0, today: today0))

        // Exact edge: start/end exactly matching the required strip bounds.
        let exact = window(start: need.start, end: need.end)
        XCTAssert(exact.covers(anchor: today0, today: today0))

        // 3 days later (a later today, anchor following it): the same window
        // no longer reaches the shifted strip end.
        let later = today0.addingTimeInterval(3 * 86_400)
        XCTAssertFalse(exact.covers(anchor: later, today: later))
    }

    /// A 30-day fetched window covers every anchor whose own 7.5-day strip fits
    /// inside it — 30 − 7.5 ≈ 22 days out — and honestly fails past that.
    func testCoversHoldsForThreeWeeksOfAnchors() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: Date())
        let w = Timeline.window(anchor: today, today: today)
        let window = ChsOnlineWindow(
            stationID: "test", iwlsName: "Test", timezone: tz.identifier,
            fetchedAt: Date(), start: w.start,
            end: today.addingTimeInterval(30 * 86_400),
            floodDirection: 0, ebbDirection: 180, times: [], speeds: [])

        XCTAssert(window.covers(anchor: today, today: today))
        XCTAssert(window.covers(anchor: today.addingTimeInterval(22 * 86_400), today: today),
                  "22 days out still fits its 7.5-day strip inside 30 days of samples")
        XCTAssertFalse(window.covers(anchor: today.addingTimeInterval(24 * 86_400), today: today),
                       "past the edge it must fail, not silently render a hole")
    }

    // MARK: - Merging (the 30-day fetch, unioned on save)

    /// A window whose bounds are exactly its own samples — the shape a fetch
    /// clamps itself to, and the only shape these merge tests need.
    private func onlineWindow(_ times: [Double], _ speeds: [Double],
                              id: String = "chs-test-merge") -> ChsOnlineWindow {
        ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "America/Vancouver",
                        fetchedAt: .now,
                        start: Date(timeIntervalSince1970: times.first ?? 0),
                        end: Date(timeIntervalSince1970: times.last ?? 0),
                        floodDirection: 0, ebbDirection: 180, times: times, speeds: speeds)
    }

    /// Merging must union by timestamp, not append — a refetch overlapping the
    /// stored window would otherwise duplicate every sample in the overlap and
    /// hand `sampleEvents` a doubled series.
    func testMergingUnionsByTimestampAndWidensTheWindow() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let a = onlineWindow([t0, t0 + 900, t0 + 1800], [1, 2, 3])
        let b = onlineWindow([t0 + 1800, t0 + 2700], [3, 4])

        let m = a.merging(b, prunedBefore: Date(timeIntervalSince1970: t0 - 1))
        XCTAssertEqual(m.times, [t0, t0 + 900, t0 + 1800, t0 + 2700], "no duplicate at the seam")
        XCTAssertEqual(m.speeds, [1, 2, 3, 4])
        XCTAssertEqual(m.end, Date(timeIntervalSince1970: t0 + 2700), "the window widens")
        XCTAssertEqual(m.start, Date(timeIntervalSince1970: t0))
    }

    /// Past current has no value once it is past, and pruning is what keeps the
    /// file from growing in the direction nobody looks.
    func testMergingPrunesTheStalePast() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let a = onlineWindow([t0, t0 + 900, t0 + 1800, t0 + 2700], [1, 2, 3, 4])
        let m = a.merging(a, prunedBefore: Date(timeIntervalSince1970: t0 + 1800))
        XCTAssertEqual(m.times, [t0 + 1800, t0 + 2700])
        XCTAssertEqual(m.speeds, [3, 4])
        XCTAssertEqual(m.start, Date(timeIntervalSince1970: t0 + 1800),
                       "start follows the prune, or coverage would lie")
    }

    /// Blocks that don't touch must not union. Nothing sampled the gap between
    /// them, so a window spanning both would answer `covers` true for an anchor
    /// in the middle — the dead-zone strip this plan exists to prevent. Reachable
    /// once an anchor can jump further than one fetch is wide.
    func testMergingDropsAStaleDisjointBlock() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let stale = onlineWindow([t0, t0 + 900], [1, 2])
        let far = onlineWindow([t0 + 60 * 86_400, t0 + 60 * 86_400 + 900], [3, 4])

        let m = stale.merging(far, prunedBefore: Date(timeIntervalSince1970: t0 - 1))
        XCTAssertEqual(m.times, far.times, "the stale block is dropped, not bridged")
        XCTAssertEqual(m.start, far.start, "an unsampled gap is never claimed as covered")
        XCTAssertEqual(m.end, far.end)
    }

    /// The seam is exact-instant, and a one-sample gap at it is producible, not
    /// theoretical: `fetchOnlineWindow` clamps a stored `end` down to the last
    /// sample IWLS actually returned, while a new block starts at its anchor.
    /// Discarding a stored month over that would defeat the whole point of
    /// merging — but tolerating MORE would paper over a real missing sample.
    func testMergingSeamToleratesOneSampleGapAndNoMore() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let stored = onlineWindow([t0, t0 + 900], [1, 2])
        let past = Date(timeIntervalSince1970: t0 - 1)
        /// A fresh block whose first sample sits `gap` after the stored last one.
        func merged(gap: Double) -> ChsOnlineWindow {
            stored.merging(onlineWindow([t0 + 900 + gap, t0 + 1800 + gap], [3, 4]), prunedBefore: past)
        }
        XCTAssertEqual(merged(gap: 0).times, [t0, t0 + 900, t0 + 1800],
                       "blocks that abut exactly merge, sharing the seam sample")
        XCTAssertEqual(merged(gap: 900).times, [t0, t0 + 900, t0 + 1800, t0 + 2700],
                       "one interval of slack is what a clamped fetch end produces — still continuous")
        XCTAssertEqual(merged(gap: 1800).times, [t0 + 2700, t0 + 3600],
                       "two intervals means a sample is genuinely missing: a hole, kept disjoint")
    }

    /// `other` is the fresh fetch, but it is not always the LATER block — a
    /// fetch for today after paging a month out arrives earlier than what is
    /// stored. Union and sort must not care which side it lands on.
    func testMergingHandlesAFreshBlockEarlierThanTheStoredOne() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let stored = onlineWindow([t0 + 1800, t0 + 2700], [3, 4])
        let earlier = onlineWindow([t0, t0 + 900], [1, 2])

        let m = stored.merging(earlier, prunedBefore: Date(timeIntervalSince1970: t0 - 1))
        XCTAssertEqual(m.times, [t0, t0 + 900, t0 + 1800, t0 + 2700], "sorted whichever side is older")
        XCTAssertEqual(m.speeds, [1, 2, 3, 4], "speeds follow their own timestamps")
        XCTAssertEqual(m.start, Date(timeIntervalSince1970: t0), "the window widens backwards too")
        XCTAssertEqual(m.end, Date(timeIntervalSince1970: t0 + 2700))

        // Far enough back to be a hole rather than a seam: the fresh block still
        // wins outright, even though it is the earlier of the two.
        let far = onlineWindow([t0 - 60 * 86_400, t0 - 60 * 86_400 + 900], [5, 6])
        XCTAssertEqual(stored.merging(far, prunedBefore: Date(timeIntervalSince1970: t0 - 61 * 86_400)).times,
                       far.times, "the gap is not claimed from either direction")
    }

    /// Saving merges into what is already on disk. Replacing would make any
    /// prefetch destructive: fetching the next block would discard the current
    /// one, and paging back would refetch what the user just had.
    func testSaveOnlineMergesInsteadOfReplacing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        // Today's local midnight is inside the 48h prune cut, so nothing here
        // is dropped for being stale.
        let t0 = todayLocal(tz).timeIntervalSince1970
        let url = ChsModelStore.onlineUrl("chs-test-merge")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try ChsModelStore.saveOnline(onlineWindow([t0, t0 + 900, t0 + 1800], [1, 2, 3]))
        // The saver returns what it WROTE, not the block handed in: the fetch
        // passes that straight back to its caller, and a view holding the
        // narrower just-fetched block would answer `covers` false for a week
        // the app has on disk.
        let saved = try ChsModelStore.saveOnline(onlineWindow([t0 + 1800, t0 + 2700], [3, 4]))
        XCTAssertEqual(saved.times, [t0, t0 + 900, t0 + 1800, t0 + 2700],
                       "saveOnline returns the merged window, not its argument")

        let loaded = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-merge"))
        XCTAssertEqual(loaded.times, [t0, t0 + 900, t0 + 1800, t0 + 2700])
        XCTAssertEqual(loaded.speeds, [1, 2, 3, 4])
        XCTAssertEqual(loaded.start, Date(timeIntervalSince1970: t0), "the earlier block survives the save")
        XCTAssertEqual(loaded.end, Date(timeIntervalSince1970: t0 + 2700))
    }

    /// The anchored fetch's arithmetic, without the IWLS round trip the rest of
    /// `fetchOnlineWindow` needs: 30 days forward of the anchor, back-padded
    /// only when the anchor IS today, and a chunk plan that reaches both ends of
    /// it. The `from:` branch is what a date picker will call.
    func testOnlineFetchSpanBackPadsOnlyTodayAndRunsThirtyDaysForward() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        let today = todayLocal(tz)
        let month = Timeline.onlineFetchDays * 86_400

        let now = ChsFitService.onlineFetchSpan(anchor: nil, today: today)
        XCTAssertEqual(now.start, today.addingTimeInterval(-Timeline.backHours * 3600),
                       "no anchor means today, which keeps the 48h look-back")
        XCTAssertEqual(now.end, today.addingTimeInterval(month))

        let ahead = today.addingTimeInterval(21 * 86_400)
        let paged = ChsFitService.onlineFetchSpan(anchor: ahead, today: today)
        XCTAssertEqual(paged.start, ahead, "an anchor that is not today gets no look-back")
        XCTAssertEqual(paged.end, ahead.addingTimeInterval(month))

        // The plan the fetch builds from that span must reach both of its ends,
        // or the saved window would claim samples no chunk asked for.
        let plan = ChsFitService.chunkPlan(days: paged.end.timeIntervalSince(paged.start) / 86_400,
                                           end: paged.end)
        XCTAssertLessThanOrEqual(try XCTUnwrap(plan.last).start, paged.start,
                                 "the oldest chunk must reach the window start")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(plan.first).end, paged.end,
                                    "the newest chunk must reach the window end")

        // And the window that span produces covers the strip its own anchor draws.
        let fetched = ChsOnlineWindow(
            stationID: "chs-test-online", iwlsName: "Test", timezone: tz.identifier,
            fetchedAt: .now, start: paged.start, end: paged.end,
            floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
        XCTAssert(fetched.covers(anchor: ahead, today: today),
                  "a fetch from an anchor must cover that anchor's own strip")
    }

    /// The prefetch aims at the block AFTER what is stored — the point is that a
    /// user paging forward lands in cache, so re-fetching the stored range would
    /// be pure waste.
    func testPrefetchAnchorIsTheStoredWindowsEdge() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: Date())
        let end = today.addingTimeInterval(30 * 86_400)
        let w = ChsOnlineWindow(stationID: "g", iwlsName: "G", timezone: tz.identifier,
                                fetchedAt: Date(), start: today, end: end,
                                floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
        XCTAssertEqual(prefetchAnchor(after: w, tz: tz), cal.startOfDay(for: end))
    }

    // MARK: - Online gates (fit-rejects backed by official CHS predictions)

    /// The 7 validation rejects ship as online: true identities — findable,
    /// never fitted, never provisional (online-gates spec §1).
    func testOnlineGatesShipAndShippedGatesStayOffline() throws {
        let online = ChsCurrentGateInfo.all.filter(\.isOnline)
        XCTAssertEqual(online.count, 7, "the 7 fit-rejects ship as online gates")
        for g in online {
            XCTAssert(g.id.hasPrefix("chs-"))
            XCTAssertFalse(g.offersProvisional, "an online gate never offers a fast answer")
            XCTAssertNotNil(g.onlineNote, "\(g.id) needs its plain-words measured error")
        }
        // The 11 shipped gates are untouched: not online, still fittable.
        XCTAssertEqual(ChsCurrentGateInfo.all.filter { !$0.isOnline }.count, 11)
        XCTAssert(ChsCurrentGateInfo.all.first { $0.id == "chs-dodd-narrows" }?.isOnline == false)
    }

    /// The origin bug: Sechelt Rapids must be findable by name AND alias.
    func testSecheltIsSearchable() throws {
        let sechelt = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == "chs-sechelt-rapids" })
        XCTAssert(sechelt.isOnline)
        for query in ["sechelt", "skookumchuck"] {
            XCTAssert(StationItem.search(query).contains { $0.id == sechelt.id },
                      "search '\(query)' did not find Sechelt Rapids")
        }
    }
}
