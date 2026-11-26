// Slackwater — GPL v3. Validated CHS current gates (M47): bundled identity,
// the flood-axis projection, and the fit→events math — a fitted model's
// record drives SlackwaterKit's CurrentStation exactly like a bundled NOAA
// station (slacks at velocity zeros, maxima signed flood/ebb).
import XCTest
@testable import Slackwater
import SlackwaterKit

final class ChsCurrentGateTests: XCTestCase {
    func testPendingWeekResumesAfterManualUpdateCompletes() {
        XCTAssertTrue(onlineGateShouldResumePendingFetch(from: .fetching, to: .idle),
                      "Finishing a manual update must resume any still-uncovered pending week")
        XCTAssertTrue(onlineGateShouldResumePendingFetch(from: .deferred(.distantFuture), to: .idle))
        XCTAssertFalse(onlineGateShouldResumePendingFetch(from: .deferred(.distantFuture), to: .fetching),
                       "A pending week must not preempt the manual update as it starts")
        XCTAssertFalse(onlineGateShouldResumePendingFetch(from: .fetching, to: .deferred(.distantFuture)),
                       "A failed fetch must respect the new retry delay")
        XCTAssertFalse(onlineGateShouldResumePendingFetch(from: .idle, to: .idle))
    }


    func testPendingWeekCompletionDoesNotStartAnotherFetchCycle() {
        XCTAssertFalse(onlineGateShouldResumePendingFetch(from: .fetching, to: .idle,
                                                          pendingFetchActive: true),
                       "A partial response must not give the pending week another two attempts")
    }

    @MainActor
    func testManualFutureUpdateAlsoFetchesMissingTodayOnlyOnce() async throws {
        let gate = ChsCurrentGateInfo(id: "chs-test-\(UUID().uuidString)", name: "Test", region: "Test",
                                     aliases: [], latitude: 49, longitude: -123, timezone: "America/Vancouver",
                                     tideReference: nil, fitDays: 0, provisionalSlackMinutes: nil, online: true)
        let today = todayLocal(gate.tz)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gate.tz
        let future = calendar.date(byAdding: .day, value: 60, to: today)!
        let span = Timeline.window(anchor: future)
        let partial = onlineWindow([span.start.timeIntervalSince1970,
                                    span.end.timeIntervalSince1970], [1, 2], id: gate.id)
        var requests: [Date] = []
        let result = try await ChsFitService.fetchOnlineUpdate(for: gate, from: future) { anchor in
            requests.append(anchor)
            return partial
        }
        XCTAssertEqual(requests, [future, today],
                       "A manual future update must replace the today request it removed from the queue")
        XCTAssertEqual(result.start, partial.start, "The requested week remains the result for the detail")

        let todaySpan = Timeline.window(anchor: today)
        let cached = onlineWindow([todaySpan.start.timeIntervalSince1970,
                                   todaySpan.end.timeIntervalSince1970], [1, 2], id: gate.id)
        try ChsModelStore.saveOnline(cached)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(gate.id)) }
        requests = []
        _ = try await ChsFitService.fetchOnlineUpdate(for: gate, from: future) { anchor in
            requests.append(anchor)
            return partial
        }
        XCTAssertEqual(requests, [future], "An existing today block must not be downloaded again")
    }

    @MainActor
    func testFailedFutureUpdateStillFetchesMissingToday() async throws {
        let gate = ChsCurrentGateInfo(id: "chs-test-\(UUID().uuidString)", name: "Test", region: "Test",
                                     aliases: [], latitude: 49, longitude: -123, timezone: "America/Vancouver",
                                     tideReference: nil, fitDays: 0, provisionalSlackMinutes: nil, online: true)
        let today = todayLocal(gate.tz)
        let future = today.addingTimeInterval(60 * 86_400)
        let span = Timeline.window(anchor: today)
        let todayWindow = onlineWindow([span.start.timeIntervalSince1970, span.end.timeIntervalSince1970],
                                       [1, 2], id: gate.id)
        var requests: [Date] = []
        do {
            _ = try await ChsFitService.fetchOnlineUpdate(for: gate, from: future) { anchor in
                requests.append(anchor)
                if anchor == future { throw ChsError.incomplete("Incomplete predictions") }
                return todayWindow
            }
            XCTFail("The original future-date failure should be returned")
        } catch ChsError.incomplete(let message) {
            XCTAssertEqual(message, "Incomplete predictions")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(requests, [future, today])
    }

    @MainActor
    func testRateLimitedFutureUpdateDoesNotFetchToday() async throws {
        let gate = ChsCurrentGateInfo(id: "chs-test-\(UUID().uuidString)", name: "Test", region: "Test",
                                     aliases: [], latitude: 49, longitude: -123, timezone: "America/Vancouver",
                                     tideReference: nil, fitDays: 0, provisionalSlackMinutes: nil, online: true)
        let future = todayLocal(gate.tz).addingTimeInterval(60 * 86_400)
        var requests: [Date] = []
        do {
            _ = try await ChsFitService.fetchOnlineUpdate(for: gate, from: future) { anchor in
                requests.append(anchor)
                throw ChsError.transient("HTTP 429")
            }
            XCTFail("The rate limit should be returned")
        } catch ChsError.transient(let message) {
            XCTAssertEqual(message, "HTTP 429")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(requests, [future])
    }

    // MARK: - Bundled identity (chs-current-gates.json, generated from the registry)

    func testBundledGatesAreRegistryKeysWithBundledPairings() {
        for gate in ChsCurrentGateInfo.all {
            XCTAssert(gate.id.hasPrefix("chs-"), "\(gate.id) is not a registry key")
            // Was `== "America/Vancouver"`, which held only while every gate
            // was Salish. The bundle now reaches Cape Breton, so assert the
            // thing that assertion was really protecting: the zone resolves,
            // and it is the right zone for where the gate actually is. A Bay
            // of Fundy gate stamped Pacific renders its slacks four hours out,
            // and that is exactly what this must catch.
            let tz = TimeZone(identifier: gate.timezone)
            XCTAssertNotNil(tz, "\(gate.id): \(gate.timezone) is not a time zone")
            guard let tz else { continue }
            // Solar time from longitude, against the zone's own offset today.
            // Two hours of slack absorbs every honest zone boundary (a zone can
            // legitimately sit well east or west of its solar meridian) while
            // still failing an ocean-sized mistake.
            let solarOffset = gate.longitude / 15.0 * 3600
            let zoneOffset = Double(tz.secondsFromGMT(for: Date()))
            XCTAssertLessThan(abs(zoneOffset - solarOffset), 2 * 3600,
                              "\(gate.id): \(gate.timezone) is wrong for longitude \(gate.longitude)")
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
        for query in ["dodd", "northumberland"] {
            XCTAssert(StationItem.search(query, near: firstRunFix).contains { $0.id == dodd.id },
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

    func testOnlineVectorPairsDownloadedSpeedAndDirection() throws {
        let speeds = [ChsSample(t: 0, v: 2), ChsSample(t: 900_000, v: 2), ChsSample(t: 1_800_000, v: 2)]
        let directions = [ChsSample(t: 0, v: 60), ChsSample(t: 900_000, v: 90), ChsSample(t: 1_800_000, v: 120)]
        let result = try XCTUnwrap(ChsFitService.onlineVectors(speeds: speeds + [speeds[1]], dirs: directions, flood: 0))
        XCTAssertEqual(result.projected.count, 3)
        XCTAssertEqual(result.projected[1].v, 0, accuracy: 1e-9)
        XCTAssertEqual(result.magnitudes, [2, 2, 2])
        XCTAssertEqual(result.directions, [60, 90, 120])
    }

    func testOnlineVectorsRejectMissingSamplesAndUseFirstDirection() throws {
        let speeds = [ChsSample(t: 0, v: 2), ChsSample(t: 900_000, v: 2), ChsSample(t: 1_800_000, v: 2)]
        let directions = [ChsSample(t: 0, v: 0), ChsSample(t: 900_000.1, v: 60),
                          ChsSample(t: 900_000, v: 240), ChsSample(t: 1_800_000, v: 180)]
        let result = try XCTUnwrap(ChsFitService.onlineVectors(speeds: speeds, dirs: directions, flood: 0))
        XCTAssertEqual(result.directions, [0, 60, 180])
        XCTAssertEqual(result.projected[1].v, 1, accuracy: 1e-9)
        let incomplete = try XCTUnwrap(ChsFitService.onlineVectors(speeds: speeds, dirs: [directions[0], directions[3]], flood: 0))
        XCTAssertTrue(ChsFitService.onlineRuns(incomplete.projected).isEmpty)
    }

    func testSingleMissingOnlineBearingRemainsUnknownAcrossNorth() throws {
        let samples = [ChsSample(t: 0, v: 1), ChsSample(t: 1_800_000, v: 1)]
        let filled = ChsFitService.fillSingleOnlineGaps(projected: samples, magnitudes: [2, 2], directions: [350, 10], measuredSpeeds: [ChsSample(t: 900_000, v: 2)], flood: 0)
        XCTAssertEqual(filled.projected.map(\.t), [0, 900_000, 1_800_000])
        XCTAssertEqual(filled.magnitudes[1], 2, accuracy: 1e-9)
        XCTAssertNil(filled.directions[1])
        XCTAssertEqual(ChsFitService.onlineRuns(filled.projected), [0..<3])
        let wide = ChsFitService.fillSingleOnlineGaps(projected: [samples[0], ChsSample(t: 2_700_000, v: 1)],
                                                        magnitudes: [2, 2], directions: [350, 10], measuredSpeeds: [], flood: 0)
        XCTAssertEqual(wide.projected.count, 2)
        let opposing = ChsFitService.fillSingleOnlineGaps(projected: samples, magnitudes: [2, 2], directions: [0, 180], measuredSpeeds: [ChsSample(t: 900_000, v: 2)], flood: 0)
        XCTAssertEqual(opposing.projected.count, 3)
        if opposing.projected.count == 3 {
            XCTAssertEqual(opposing.magnitudes[1], 2)
            XCTAssertNil(opposing.directions[1] as Double?)
        }
        let missingSpeed = ChsFitService.fillSingleOnlineGaps(projected: samples, magnitudes: [2, 2], directions: [350, 10], measuredSpeeds: [], flood: 0)
        XCTAssertEqual(missingSpeed.projected.count, 2)
    }

    func testMeasuredSpeedsSurviveWithoutAnyBearings() throws {
        let measured = [ChsSample(t: 0, v: 1), ChsSample(t: 900_000, v: 0.8)]
        let raw = try XCTUnwrap(ChsFitService.onlineVectors(speeds: measured, dirs: [], flood: 0))
        let filled = ChsFitService.fillSingleOnlineGaps(projected: raw.projected, magnitudes: raw.magnitudes,
                                                         directions: raw.directions, measuredSpeeds: measured, flood: 0)
        XCTAssertEqual(filled.magnitudes, [1, 0.8])
        XCTAssertTrue(filled.directions.allSatisfy { $0 == nil })
        XCTAssertEqual(ChsFitService.onlineRuns(filled.projected), [0..<2])
    }

    func testConsecutiveMissingBearingsKeepMeasuredSpeeds() {
        let points = [ChsSample(t: 0, v: 1), ChsSample(t: 2_700_000, v: -1)]
        let measured = [ChsSample(t: 900_000, v: 0.8), ChsSample(t: 1_800_000, v: 0.6)]
        let filled = ChsFitService.fillSingleOnlineGaps(projected: points, magnitudes: [1, 1],
                                                         directions: [0, 180], measuredSpeeds: measured, flood: 0)
        XCTAssertEqual(filled.projected.map(\.t), [0, 900_000, 1_800_000, 2_700_000])
        XCTAssertEqual(filled.magnitudes, [1, 0.8, 0.6, 1])
        XCTAssertNil(filled.directions[1])
        XCTAssertNil(filled.directions[2])
        XCTAssertEqual(ChsFitService.onlineRuns(filled.projected), [0..<4])
    }

    func testMissingDirectionKeepsMeasuredCrossFlowInsteadOfInventingSlack() throws {
        let speeds = [ChsSample(t: 0, v: 2), ChsSample(t: 900_000, v: 2), ChsSample(t: 1_800_000, v: 2)]
        let directions = [ChsSample(t: 0, v: 60), ChsSample(t: 1_800_000, v: 120)]
        let raw = try XCTUnwrap(ChsFitService.onlineVectors(speeds: speeds, dirs: directions, flood: 0))
        let filled = ChsFitService.fillSingleOnlineGaps(projected: raw.projected, magnitudes: raw.magnitudes,
                                                         directions: raw.directions, measuredSpeeds: speeds, flood: 0)
        XCTAssertEqual(filled.projected.count, 3)
        XCTAssertEqual(filled.magnitudes[1], 2, accuracy: 1e-9)
        let window = ChsOnlineWindow(stationID: "test", iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1800),
                                     floodDirection: 0, ebbDirection: 180,
                                     times: filled.projected.map { $0.t / 1000 }, speeds: filled.projected.map(\.v),
                                     magnitudes: filled.magnitudes, directions: filled.directions)
        XCTAssertFalse(window.events(from: window.start, to: window.end).contains { $0.kind == .slack })
        XCTAssertTrue(currentWindows(window.points, events: [], threshold: 0.5).isEmpty)
    }

    func testSavingVectorDataPreservesTheOlderAppDownload() throws {
        let id = "chs-rollback-\(UUID().uuidString)"
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let old = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                  start: start, end: start.addingTimeInterval(900), floodDirection: 0, ebbDirection: 180,
                                  times: [start.timeIntervalSince1970, start.timeIntervalSince1970 + 900], speeds: [1, 1])
        let oldURL = ChsModelStore.url(id, suffix: "-online")
        defer {
            try? FileManager.default.removeItem(at: oldURL)
            try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(id))
        }
        try FileManager.default.createDirectory(at: oldURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try JSONEncoder().encode(ChsOnlineStore(stationID: id, blocks: [old]))
        try original.write(to: oldURL)
        let vector = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: start, end: start.addingTimeInterval(900), floodDirection: 0, ebbDirection: 180,
                                     times: old.times, speeds: [0, 1], magnitudes: [2, 1], directions: [nil, 0])
        try ChsModelStore.saveOnline(vector, retainingFrom: start)
        XCTAssertEqual(try Data(contentsOf: oldURL), original)
        XCTAssertFalse(ChsModelStore.onlineUrl(id).lastPathComponent.hasSuffix(".json"), "The previous release removes unknown JSON files during orphan cleanup")
        XCTAssertNotNil(ChsModelStore.loadOnline(id))
    }

    func testUnknownDirectionDoesNotCreateNewPeakAfterReload() throws {
        let values: [Double] = [2, 3, 2.75, 2.5, 1]
        let window = ChsOnlineWindow(stationID: "test", iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600),
                                     floodDirection: 0, ebbDirection: 180,
                                     times: [0, 900, 1800, 2700, 3600], speeds: values,
                                     magnitudes: values, directions: [0, 0, nil, 0, 0])
        let reloaded = try JSONDecoder().decode(ChsOnlineWindow.self, from: JSONEncoder().encode(window))
        XCTAssertEqual(sampleEvents(window.points).map(\.time), sampleEvents(reloaded.points).map(\.time))
    }

    func testRefreshDoesNotOverwriteKnownDirectionWithUnknown() throws {
        let start = Date(timeIntervalSince1970: 1000)
        func window(_ bearing: Double?) -> ChsOnlineWindow {
            ChsOnlineWindow(stationID: "test", iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                            start: start, end: start.addingTimeInterval(900), floodDirection: 0, ebbDirection: 180,
                            times: [1000, 1900], speeds: [1, 1], magnitudes: [1, 1], directions: [bearing, bearing])
        }
        let merged = window(90).merging(window(nil), prunedBefore: start)
        XCTAssertEqual(merged.directions?.first!, 90)
    }

    func testUnknownAxisIsNotPersistedAsACalmReading() throws {
        struct OldWindow: Decodable { let speeds: [Double] }
        let window = ChsOnlineWindow(stationID: "test", iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: .now, end: .now, floodDirection: 0, ebbDirection: 180,
                                     times: [0, 900], speeds: [0, 1], magnitudes: [2, 1], directions: [nil, 0])
        let data = try JSONEncoder().encode(window)
        XCTAssertThrowsError(try JSONDecoder().decode(OldWindow.self, from: data))
        let decoded = try JSONDecoder().decode(ChsOnlineWindow.self, from: data)
        XCTAssertEqual(decoded.magnitudes?[0], 2)
        XCTAssertNil(decoded.directions?[0])
    }

    func testMissingDirectionAtReversalKeepsSpeedWithoutClaimingSlack() throws {
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let base = start.timeIntervalSince1970 * 1000
        let raw = [ChsSample(t: base, v: -1), ChsSample(t: base + 1_800_000, v: 1)]
        let filled = ChsFitService.fillSingleOnlineGaps(projected: raw, magnitudes: [2, 2], directions: [180, 0],
                                                       measuredSpeeds: [ChsSample(t: base + 900_000, v: 2)], flood: 0)
        let id = "chs-unknown-direction-\(UUID().uuidString)"
        let window = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: start, end: start.addingTimeInterval(1800), floodDirection: 0, ebbDirection: 180,
                                     times: filled.projected.map { $0.t / 1000 }, speeds: filled.projected.map(\.v),
                                     magnitudes: filled.magnitudes, directions: filled.directions)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(id)) }
        try ChsModelStore.saveOnline(window)
        let loaded = try XCTUnwrap(ChsModelStore.loadOnline(id)?.blocks.first)
        let midpoint = start.addingTimeInterval(900)
        let point = try XCTUnwrap(loaded.speeds(from: midpoint, to: midpoint, step: 1).first)
        XCTAssertEqual(point.magnitude, 2, accuracy: 1e-9)
        XCTAssertNil(point.direction)
        XCTAssertTrue(point.magnitudeIsKnown)
        let card = loaded.cardState(at: midpoint)
        XCTAssertTrue(card.directionUnknown)
        XCTAssertFalse(currentCardFace(magnitude: card.magnitude, direction: card.direction, speed: card.signed, unit: "kn", inWindow: false, setFormat: "compass", directionUnknown: card.directionUnknown).spoken.contains("ebb"))
        XCTAssertNil(loaded.signedSpeed(at: midpoint))
        XCTAssertNil(loaded.signedSpeed(at: midpoint.addingTimeInterval(-450)))
        XCTAssertEqual(loaded.signedSpeed(at: start), -1)
        let crossing = CurrentEvent(time: midpoint, speed: 0, kind: .slack)
        XCTAssertNotEqual(readCurrent(at: midpoint, timeline: loaded.points, events: [crossing], flood: 0, ebb: 180)?.state, .slack)
        XCTAssertTrue(currentWindows(loaded.points, events: [crossing], threshold: 0.5).isEmpty)
        XCTAssertFalse(sampleEvents(loaded.points).contains { $0.kind == .slack })
        XCTAssertTrue(sampleEvents(loaded.points).contains { $0.time == start })
        let reading = currentLeadReading("Flooding", isSlack: false, point: point, floodDeg: 0, ebbDeg: 180, speedUnit: "kn", setFormat: "compass")
        XCTAssertEqual(reading.glyph, "arrow.triangle.2.circlepath")
        XCTAssertTrue(reading.state.isEmpty)
    }

    func testOnlineRunsPreserveSamplesOnBothSidesOfGap() throws {
        let speeds = (0..<5).map { ChsSample(t: Double($0) * 900_000, v: 2) }
        let dirs = speeds.enumerated().filter { $0.offset != 2 }.map { ChsSample(t: $0.element.t, v: 90) }
        let vectors = try XCTUnwrap(ChsFitService.onlineVectors(speeds: speeds, dirs: dirs, flood: 0))
        XCTAssertEqual(ChsFitService.onlineRuns(vectors.projected), [0..<2, 2..<4])
        XCTAssertEqual(vectors.magnitudes, [2, 2, 2, 2])
        let invalid = speeds.map { ChsSample(t: $0.t, v: $0.t == 1_800_000 ? .nan : 90) }
        let cleaned = try XCTUnwrap(ChsFitService.onlineVectors(speeds: speeds, dirs: invalid, flood: 0))
        XCTAssertEqual(ChsFitService.onlineRuns(cleaned.projected), [0..<2, 2..<4])
    }

    func testIncompleteOnlineBlocksStopRetryingUnlessCachedBlockCoversStrip() throws {
        let anchor = Date(timeIntervalSince1970: 1_767_225_600)
        let span = Timeline.window(anchor: anchor)
        func block(_ start: Date, _ end: Date) -> ChsOnlineWindow {
            ChsOnlineWindow(axisOnly: true, stationID: "test", iwlsName: "Test", timezone: "UTC",
                            fetchedAt: .now, start: start, end: end, floodDirection: 0, ebbDirection: 180,
                            times: [start.timeIntervalSince1970, end.timeIntervalSince1970], speeds: [1, -1])
        }
        let partial = [block(span.start, anchor), block(anchor.addingTimeInterval(900), span.end)]
        XCTAssertThrowsError(try ChsFitService.onlineCoveredWindow(partial, anchor: anchor, name: "Test")) { error in
            XCTAssertTrue(ChsError.isPermanent(error))
        }
        XCTAssertThrowsError(try ChsFitService.onlineCoveredWindow([], anchor: anchor, name: "Test")) { error in
            XCTAssertTrue(ChsError.isPermanent(error))
        }
        let complete = block(span.start, span.end)
        XCTAssertTrue(try ChsFitService.onlineCoveredWindow(partial + [complete], anchor: anchor, name: "Test").covers(anchor: anchor))
    }

    func testOnlineVectorSurvivesCacheAndDoesNotInventSlack() throws {
        let id = "chs-vector-regression"
        let window = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1800),
                                     floodDirection: 0, ebbDirection: 180,
                                     times: [0, 900, 1800], speeds: [1, 0, -1],
                                     magnitudes: [2, 2, 2], directions: [60, 90, 120])
        try ChsModelStore.saveOnline(window)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(id)) }
        let loaded = try XCTUnwrap(ChsModelStore.loadOnline(id)?.blocks.first)
        let middle = try XCTUnwrap(loaded.speeds(from: Date(timeIntervalSince1970: 900),
                                                 to: Date(timeIntervalSince1970: 900), step: 1).first)
        XCTAssertEqual(middle.speed, 0, accuracy: 1e-9)
        XCTAssertEqual(middle.magnitude, 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(middle.direction), 90, accuracy: 1e-9)
        XCTAssertTrue(currentWindows(loaded.points, events: loaded.events(from: window.start, to: window.end),
                                     threshold: 0.5).isEmpty)
        XCTAssertFalse(loaded.events(from: window.start, to: window.end).contains { $0.kind == .slack })
    }

    func testOnlineVectorInterpolationCrossesNorthWithoutReversing() throws {
        let window = ChsOnlineWindow(stationID: "vector", iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 900),
                                     floodDirection: 0, ebbDirection: 180, times: [0, 900], speeds: [1, 1],
                                     magnitudes: [1, 1], directions: [350, 10])
        let point = try XCTUnwrap(window.speeds(from: Date(timeIntervalSince1970: 450),
                                                 to: Date(timeIntervalSince1970: 450), step: 1).first)
        let direction = try XCTUnwrap(point.direction)
        XCTAssertLessThan(min(direction, 360 - direction), 0.001)
        XCTAssertGreaterThan(point.magnitude, 0.98)
    }

    func testOnlineVectorSurvivesMergeAndPrune() throws {
        func window(_ start: Double, _ speeds: [Double], _ magnitudes: [Double], _ directions: [Double]) -> ChsOnlineWindow {
            ChsOnlineWindow(stationID: "vector", iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                            start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: start + 900),
                            floodDirection: 0, ebbDirection: 180, times: [start, start + 900], speeds: speeds,
                            magnitudes: magnitudes, directions: directions)
        }
        let a = window(0, [1, 0], [2, 2], [60, 90])
        let b = window(900, [0, -1], [3, 2], [90, 120])
        let merged = a.merging(b, prunedBefore: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(merged.magnitudes, [2, 3, 2])
        XCTAssertEqual(merged.directions, [60, 90, 120])
        let pruned = try XCTUnwrap(merged.pruned(before: Date(timeIntervalSince1970: 900)))
        XCTAssertEqual(pruned.magnitudes, [3, 2])
        XCTAssertEqual(pruned.directions, [90, 120])
    }

    func testSavingSplitHistoricalFetchRetainsBothRuns() throws {
        let id = "chs-split-\(UUID().uuidString)"
        let start = Date.now.addingTimeInterval(-90 * 86_400).timeIntervalSince1970
        let first = onlineWindow([start, start + 900], [1, 1], id: id)
        let second = onlineWindow([start + 2700, start + 3600], [1, 1], id: id)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(id)) }
        try ChsModelStore.saveOnline(first, retainingFrom: first.start)
        try ChsModelStore.saveOnline(second, retainingFrom: first.start)
        let blocks = try XCTUnwrap(ChsModelStore.loadOnline(id)).blocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks.contains { $0.start == first.start && $0.end == first.end })
        XCTAssertTrue(blocks.contains { $0.start == second.start && $0.end == second.end })
    }

    func testAxisOnlyOnlineCacheIsNotUsedAsAFullVector() throws {
        let id = "chs-axis-only-regression"
        let window = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 900),
                                     floodDirection: 0, ebbDirection: 180, times: [0, 900], speeds: [1, -1])
        let url = ChsModelStore.onlineUrl(id)
        try ChsModelStore.saveOnline(window)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ChsModelStore.loadOnline(id))
        let legacy = try XCTUnwrap(ChsModelStore.loadLegacyOnline(id)?.blocks.first)
        XCTAssertFalse(legacy.hasVectors)
        XCTAssertEqual(legacy.signedSpeed(at: Date(timeIntervalSince1970: 450)), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let vector = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: window.start, end: window.end, floodDirection: 0, ebbDirection: 180,
                                     times: [0, 900], speeds: [1, -1], magnitudes: [2, 2], directions: [60, 120])
        try ChsModelStore.saveOnline(vector)
        XCTAssertEqual(ChsModelStore.loadOnline(id)?.blocks.first?.magnitudes, [2, 2])
    }

    func testVectorRefreshPreservesAxisOnlySamplesOutsideItsRange() throws {
        let id = "chs-axis-partial-\(UUID().uuidString)"
        let legacy = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 5400),
                                     floodDirection: 0, ebbDirection: 180,
                                     times: [0, 900, 1800, 2700, 3600, 4500, 5400], speeds: [1, 1, 1, 1, 1, 1, 1])
        let vector = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: Date(timeIntervalSince1970: 1800), end: Date(timeIntervalSince1970: 3600),
                                     floodDirection: 0, ebbDirection: 180, times: [1800, 2700, 3600],
                                     speeds: [1, 1, 1], magnitudes: [2, 2, 2], directions: [90, 90, 90])
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(id)) }
        try ChsModelStore.saveOnline(legacy, retainingFrom: legacy.start)
        try ChsModelStore.saveOnline(vector, retainingFrom: legacy.start)
        XCTAssertEqual(ChsModelStore.loadOnline(id)?.blocks.first?.times, vector.times)
        XCTAssertEqual(ChsModelStore.loadLegacyOnline(id)?.blocks.map(\.times), [[0, 900], [4500, 5400]])
    }

    func testOnlineWindowStoreRoundTrip() throws {
        let window = ChsOnlineWindow(axisOnly: true,
            stationID: "chs-test-online", iwlsName: "Test Online Station",
            timezone: "America/Vancouver", fetchedAt: .now,
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1_000_000),
            floodDirection: 45, ebbDirection: 225, times: [0, 900], speeds: [1.5, -1.5])
        try ChsModelStore.saveOnline(window)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(window.stationID)) }
        let store = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-online"))
        let loaded = try XCTUnwrap(store.blocks.first)
        XCTAssertEqual(store.blocks.count, 1)
        XCTAssertEqual(loaded.floodDirection, 45)
        XCTAssertEqual(loaded.times, [0, 900])
        XCTAssertEqual(loaded.speeds, [1.5, -1.5])
        // The online store must never shadow a fitted model of the same key.
        XCTAssertNil(ChsModelStore.loadCurrent("chs-test-online"))
        XCTAssertNil(ChsModelStore.load("chs-test-online"))
    }

    func testLoadOnlineCachesDecodedStore() throws {
        let window = ChsOnlineWindow(axisOnly: true,
            stationID: "chs-test-cache", iwlsName: "Test Cache Station",
            timezone: "America/Vancouver", fetchedAt: .now,
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1_000_000),
            floodDirection: 45, ebbDirection: 225, times: [0, 900], speeds: [1.5, -1.5])
        try ChsModelStore.saveOnline(window)
        let url = ChsModelStore.onlineUrl(window.stationID)
        defer { try? FileManager.default.removeItem(at: url) }
        // A pinned whole-second mtime, not the stat-read one: Date → timespec
        // → Date loses ~240 ns of Double precision on a real "now", so forging
        // "the same mtime" from a stat read races that rounding (it failed on
        // CI, passed locally). A whole second survives every conversion.
        let stamp = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        let first = try XCTUnwrap(ChsModelStore.loadOnline(window.stationID))

        // Corrupt the file while forging identical mtime+size — only the memo
        // can still answer, so this fails if loadOnline re-decodes every call
        // (the main-thread decode storm behind the build-31 watchdog kills).
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = try XCTUnwrap(attrs[.size] as? Int)
        try Data(repeating: 0x7B, count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        XCTAssertEqual(ChsModelStore.loadOnline(window.stationID)?.blocks.first?.times,
                       first.blocks.first?.times,
                       "unchanged mtime+size serves the memoized store without touching the bytes")

        // A genuine change invalidates: the junk bytes now decode as nothing.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        XCTAssertNil(ChsModelStore.loadOnline(window.stationID),
                     "a changed file is re-read, never served from the memo")

        try FileManager.default.removeItem(at: url)
        XCTAssertNil(ChsModelStore.loadOnline(window.stationID),
                     "a deleted file is gone immediately, never served from the memo")
    }

    func testLegacyOnlineReaderSharesTheFileCache() throws {
        let id = "chs-legacy-cache-\(UUID().uuidString)"
        let window = ChsOnlineWindow(stationID: id, iwlsName: "Test", timezone: "UTC", fetchedAt: .now,
                                     start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 900),
                                     floodDirection: 0, ebbDirection: 180, times: [0, 900], speeds: [1, -1])
        try ChsModelStore.saveOnline(window, retainingFrom: window.start)
        let url = ChsModelStore.onlineUrl(id)
        defer { try? FileManager.default.removeItem(at: url) }
        let stamp = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        XCTAssertNil(ChsModelStore.loadOnline(id))
        XCTAssertEqual(ChsModelStore.loadLegacyOnline(id)?.blocks.first?.speeds, [1, -1])
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        try Data(repeating: 0x7B, count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        XCTAssertEqual(ChsModelStore.loadLegacyOnline(id)?.blocks.first?.speeds, [1, -1])
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        XCTAssertNil(ChsModelStore.loadLegacyOnline(id))
    }

    func testOnlineWindowCoversStrip() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now0 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12)))
        let today0 = cal.startOfDay(for: now0)
        let need = Timeline.window(anchor: today0)

        func window(start: Date, end: Date) -> ChsOnlineWindow {
            ChsOnlineWindow(axisOnly: true, stationID: "chs-test-online", iwlsName: "Test", timezone: "America/Vancouver",
                            fetchedAt: .now, start: start, end: end,
                            floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
        }

        // Inside: a window wider than the strip needs still covers it.
        let padded = window(start: need.start.addingTimeInterval(-3600), end: need.end.addingTimeInterval(3600))
        XCTAssert(padded.covers(anchor: today0))

        // Exact edge: start/end exactly matching the required strip bounds.
        let exact = window(start: need.start, end: need.end)
        XCTAssert(exact.covers(anchor: today0))

        // 3 days later (a later today, anchor following it): the same window
        // no longer reaches the shifted strip end.
        let later = today0.addingTimeInterval(3 * 86_400)
        XCTAssertFalse(exact.covers(anchor: later))
    }

    /// A 30-day fetched window covers every anchor whose own 7.5-day strip fits
    /// inside it — 30 − 7.5 ≈ 22 days out — and honestly fails past that.
    func testCoversHoldsForThreeWeeksOfAnchors() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: Date())
        let w = Timeline.window(anchor: today)
        let window = ChsOnlineWindow(axisOnly: true,
            stationID: "test", iwlsName: "Test", timezone: tz.identifier,
            fetchedAt: Date(), start: w.start,
            end: today.addingTimeInterval(30 * 86_400),
            floodDirection: 0, ebbDirection: 180, times: [], speeds: [])

        XCTAssert(window.covers(anchor: today))
        XCTAssert(window.covers(anchor: today.addingTimeInterval(22 * 86_400)),
                  "22 days out still fits its 7.5-day strip inside 30 days of samples")
        XCTAssertFalse(window.covers(anchor: today.addingTimeInterval(24 * 86_400)),
                       "past the edge it must fail, not silently render a hole")
    }

    /// Detail views keep the offline state so they never offer a download
    /// action that cannot succeed without a connection.
    func testOnlineGateStatusRequiresSignalWhenOffline() {
        XCTAssertEqual(onlineGateStatus(nil, online: true), .notQueued)
        XCTAssertEqual(onlineGateStatus(onlineWindow([0, 900], [1, 2]), online: true), .notQueued)
        XCTAssertEqual(onlineGateStatus(nil, online: false), .offline)
        XCTAssertEqual(onlineGateStatus(onlineWindow([0, 900], [1, 2]), online: false), .offline)
    }

    /// A date in the station's zone, never a count of days left.
    func testOnlineDownloadValidityNamesTheLastDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 13))!

        XCTAssertEqual(onlineDownloadValidity(end: cal.date(byAdding: .day, value: 36, to: now)!,
                                              now: now, calendar: cal),
                       "Through Sep 30")
        XCTAssertEqual(onlineDownloadValidity(end: cal.date(byAdding: .hour, value: 2, to: now)!,
                                              now: now, calendar: cal),
                       "Through Aug 25")
        // 23:30 in Vancouver is already the next day in UTC: the date is the station's.
        let lateEvening = cal.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 23, minute: 30))!
        XCTAssertEqual(onlineDownloadValidity(end: lateEvening, now: now, calendar: cal),
                       "Through Aug 27")
        XCTAssertEqual(onlineDownloadValidity(end: lateEvening, now: now, calendar: cal, standalone: true),
                       "Offline through Aug 27", "a sentence with no title above it says what the date is for")
        // The last day holds until it ends, as the strip still draws it.
        let lastMorning = cal.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 8))!
        XCTAssertEqual(onlineDownloadValidity(end: lastMorning, now: now, calendar: cal), "Through Aug 25")
        XCTAssertEqual(onlineDownloadValidity(end: cal.date(byAdding: .day, value: -1, to: now)!,
                                              now: now, calendar: cal),
                       "Expired")
    }

    /// Online, a copy reaching less than a fetch ahead refreshes even though
    /// it still covers today, whenever it was last fetched; Low Data Mode
    /// waits until today is missing.
    func testAnOnlineCopyRefreshesUntilItReachesAMonthAhead() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        let today = todayLocal(tz)
        let span = Timeline.window(anchor: today)
        let month = Timeline.onlineFetchDays * 86_400
        func block(_ start: Date, _ end: Date, fetchedAt: Date = appNow()) -> ChsOnlineWindow {
            ChsOnlineWindow(axisOnly: true, stationID: "chs-test-refresh", iwlsName: "Test", timezone: tz.identifier,
                            fetchedAt: fetchedAt, start: start, end: end,
                            floodDirection: 0, ebbDirection: 180,
                            times: [start.timeIntervalSince1970, end.timeIntervalSince1970],
                            speeds: [0, 0])
        }
        func store(_ blocks: ChsOnlineWindow...) -> ChsOnlineStore {
            ChsOnlineStore(stationID: "chs-test-refresh", blocks: blocks)
        }
        let fetchedToday = block(span.start, today.addingTimeInterval(month - 900))
        let fetchedYesterday = block(span.start, today.addingTimeInterval(month - 86_400))
        XCTAssertFalse(store(fetchedToday).needsRefresh(today: today),
                       "today's fetch, clamped to its last sample, is a full month")
        XCTAssertTrue(store(fetchedYesterday).needsRefresh(today: today))
        XCTAssertTrue(store(block(span.start, today.addingTimeInterval(month - 86_400), fetchedAt: today))
            .needsRefresh(today: today), "an older week merged in today does not renew the month ahead")
        XCTAssertFalse(store(fetchedYesterday).needsRefresh(today: today, lowData: true))
        let behind = store(block(span.start.addingTimeInterval(-40 * 86_400), span.start.addingTimeInterval(-10 * 86_400)))
        XCTAssertTrue(behind.needsRefresh(today: today, lowData: true),
                      "a copy that no longer covers today downloads even in Low Data Mode")
        let later = block(today.addingTimeInterval(60 * 86_400), today.addingTimeInterval(90 * 86_400))
        XCTAssertEqual(store(fetchedYesterday, later).reachBlock(today: today)?.end, fetchedYesterday.end,
                       "the date shown is today's block, never one past a gap")
        XCTAssertNil(store(later).reachBlock(today: today), "a future week alone says nothing about today")
        let past = block(span.start.addingTimeInterval(-40 * 86_400), span.start.addingTimeInterval(-10 * 86_400))
        XCTAssertEqual(store(past, later).reachBlock(today: today)?.end, past.end,
                       "an older copy that ran out reads as expired")
    }

    // MARK: - Merging (the 30-day fetch, unioned on save)

    /// A window whose bounds are exactly its own samples — the shape a fetch
    /// clamps itself to, and the only shape these merge tests need.
    private func onlineWindow(_ times: [Double], _ speeds: [Double],
                              id: String = "chs-test-merge") -> ChsOnlineWindow {
        ChsOnlineWindow(axisOnly: true, stationID: id, iwlsName: "Test", timezone: "America/Vancouver",
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

        let store = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-merge"))
        XCTAssertEqual(store.blocks.count, 1)
        XCTAssertEqual(store.blocks[0].times, [t0, t0 + 900, t0 + 1800, t0 + 2700])
        XCTAssertEqual(store.blocks[0].speeds, [1, 2, 3, 4])
        XCTAssertEqual(store.blocks[0].start, Date(timeIntervalSince1970: t0), "the earlier block survives the save")
        XCTAssertEqual(store.blocks[0].end, Date(timeIntervalSince1970: t0 + 2700))
    }

    /// THE #67 item 4 headline: a far-forward fetch and today's block coexist on
    /// disk. Under the single window the second save discarded the first.
    func testSaveOnlineKeepsTodayWhenAFarBlockLands() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        let t0 = todayLocal(tz).timeIntervalSince1970
        let url = ChsModelStore.onlineUrl("chs-test-merge")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try ChsModelStore.saveOnline(onlineWindow([t0, t0 + 900], [1, 2]))
        let far = t0 + 40 * 86_400
        let saved = try ChsModelStore.saveOnline(onlineWindow([far, far + 900], [3, 4]))
        XCTAssertEqual(saved.times, [far, far + 900],
                       "saveOnline returns the block the fetch landed in, not the whole store")

        let store = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-merge"))
        XCTAssertEqual(store.blocks.count, 2, "today's block survived the far save")
        XCTAssertEqual(store.blocks[0].times, [t0, t0 + 900])
    }

    /// A single-window file carrying vectors still decodes as one block.
    func testLoadOnlineMigratesSingleWindowWithVectors() throws {
        let legacy = onlineWindow([0, 900], [1, 2], id: "chs-test-legacy")
        let url = ChsModelStore.onlineUrl("chs-test-legacy")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: url)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl("chs-test-legacy")) }
        let store = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-legacy"))
        XCTAssertEqual(store.blocks.count, 1)
        XCTAssertEqual(store.blocks[0].times, [0, 900])
    }

    /// The anchored fetch's arithmetic, without the IWLS round trip the rest of
    /// `fetchOnlineWindow` needs: 30 days forward of the anchor, back-padded
    /// like every window (#67 item 1), and a chunk plan that reaches both ends
    /// of it. The `from:` branch is what a date picker will call.
    func testOnlineFetchSpanBackPadsAndRunsThirtyDaysForward() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        let today = todayLocal(tz)
        let month = Timeline.onlineFetchDays * 86_400

        let now = ChsFitService.onlineFetchSpan(anchor: nil, today: today)
        XCTAssertEqual(now.start, today.addingTimeInterval(-Timeline.backHours * 3600),
                       "no anchor means today, which keeps the 48h look-back")
        XCTAssertEqual(now.end, today.addingTimeInterval(month))

        let ahead = today.addingTimeInterval(21 * 86_400)
        let paged = ChsFitService.onlineFetchSpan(anchor: ahead, today: today)
        XCTAssertEqual(paged.start, ahead.addingTimeInterval(-Timeline.backHours * 3600),
                       "an anchored fetch is back-padded like every window (#67 item 1)")
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
        let fetched = ChsOnlineWindow(axisOnly: true,
            stationID: "chs-test-online", iwlsName: "Test", timezone: tz.identifier,
            fetchedAt: .now, start: paged.start, end: paged.end,
            floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
        XCTAssert(fetched.covers(anchor: ahead),
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
        let w = ChsOnlineWindow(axisOnly: true, stationID: "g", iwlsName: "G", timezone: tz.identifier,
                                fetchedAt: Date(), start: today, end: end,
                                floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
        XCTAssertEqual(prefetchAnchor(after: w, tz: tz), cal.startOfDay(for: end))
    }

    // MARK: - Multi-block store (#67 item 4)

    /// A far-forward fetch used to discard today's block outright (single
    /// start/end, newest wins). The store keeps both.
    func testInsertingKeepsDisjointBlocksSeparate() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let today = onlineWindow([t0, t0 + 900], [1, 2])
        let far = onlineWindow([t0 + 40 * 86_400, t0 + 40 * 86_400 + 900], [3, 4])
        let store = ChsOnlineStore(stationID: "chs-test-merge", blocks: [today])
            .inserting(far, prunedBefore: Date(timeIntervalSince1970: t0 - 1))
        XCTAssertEqual(store.blocks.count, 2, "a disjoint fetch must not cost the stored block")
        XCTAssertEqual(store.blocks[0].times, today.times, "sorted by start, stored block intact")
        XCTAssertEqual(store.blocks[1].times, far.times)
    }

    /// An incoming block that reaches two stored blocks joins all three — the
    /// single ascending pass has to absorb a chain, not just one neighbour.
    func testInsertingBridgesTwoStoredBlocks() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let a = onlineWindow([t0, t0 + 900], [1, 2])
        let c = onlineWindow([t0 + 3600, t0 + 4500], [5, 6])
        let bridge = onlineWindow([t0 + 1800, t0 + 2700], [3, 4])
        let store = ChsOnlineStore(stationID: "chs-test-merge", blocks: [a, c])
            .inserting(bridge, prunedBefore: Date(timeIntervalSince1970: t0 - 1))
        XCTAssertEqual(store.blocks.count, 1, "the bridge joins both neighbours")
        XCTAssertEqual(store.blocks[0].times, [t0, t0 + 900, t0 + 1800, t0 + 2700, t0 + 3600, t0 + 4500])
    }

    /// Coverage never stitches across the gap between blocks — the same "no strip
    /// with a dead zone" rule `covers` enforces inside one block.
    func testBlockCoveringRefusesTheGap() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: Date())
        func span(_ anchor: Date) -> ChsOnlineWindow {
            let w = Timeline.window(anchor: anchor)
            return ChsOnlineWindow(axisOnly: true, stationID: "g", iwlsName: "G", timezone: tz.identifier,
                                   fetchedAt: .now, start: w.start, end: w.end,
                                   floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
        }
        let far = today.addingTimeInterval(60 * 86_400)
        let store = ChsOnlineStore(stationID: "g", blocks: [span(today), span(far)])
        XCTAssertNotNil(store.block(covering: today))
        XCTAssertNotNil(store.block(covering: far))
        XCTAssertNil(store.block(covering: today.addingTimeInterval(30 * 86_400)),
                     "the gap between blocks has no samples — it must not read as covered")
    }

    /// #67 item 6 (bounded backward retention): a block ages out at the next save
    /// after it falls behind today − 60d — but never the save's own fetch, so a
    /// deliberately-picked old week still renders (the min(_, incoming.start)
    /// guard lives in saveOnline; inserting itself just applies the cut).
    func testInsertingPrunesAgedBlocks() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let aged = onlineWindow([t0 - 70 * 86_400, t0 - 70 * 86_400 + 900], [1, 2])
        let fresh = onlineWindow([t0, t0 + 900], [3, 4])
        let store = ChsOnlineStore(stationID: "chs-test-merge", blocks: [aged])
            .inserting(fresh, prunedBefore: Date(timeIntervalSince1970: t0 - 60 * 86_400))
        XCTAssertEqual(store.blocks.count, 1, "the aged block is gone, not half-kept")
        XCTAssertEqual(store.blocks[0].times, fresh.times)
    }

    /// pruned(before:) follows merging's rule: `start` follows the cut, or
    /// `covers` keeps claiming a range whose samples were deleted.
    func testPrunedDropsSamplesAndMovesStart() {
        let t0 = Date().timeIntervalSince1970.rounded(.down)
        let w = onlineWindow([t0, t0 + 900, t0 + 1800], [1, 2, 3])
        let cut = Date(timeIntervalSince1970: t0 + 900)
        let p = w.pruned(before: cut)
        XCTAssertEqual(p?.times, [t0 + 900, t0 + 1800])
        XCTAssertEqual(p?.start, cut)
        XCTAssertNil(w.pruned(before: Date(timeIntervalSince1970: t0 + 86_400)),
                     "nothing survives → nil, not an empty shell that still claims a span")
        XCTAssertEqual(w.pruned(before: Date(timeIntervalSince1970: t0 - 1))?.times, w.times,
                       "a cut before the block is a no-op")
    }

    // MARK: - Online gates (fit-rejects backed by official CHS predictions)

    /// Online identities remain findable,
    /// never fitted, never provisional (online-gates spec §1).
    func testOnlineGatesShipAndShippedGatesStayOffline() throws {
        let online = ChsCurrentGateInfo.all.filter(\.isOnline)
        XCTAssertEqual(online.count, 16, "year-round evidence decides online admission")
        for g in online {
            XCTAssert(g.id.hasPrefix("chs-"))
            XCTAssertFalse(g.offersProvisional, "an online gate never offers a fast answer")
            XCTAssertNotNil(g.onlineMiss, "\(g.id) needs its measured failing clause")
        }
        // Seven gates qualify for a fitted model on year-round evidence.
        XCTAssertEqual(ChsCurrentGateInfo.all.filter { !$0.isOnline }.count, 7)
        XCTAssert(ChsCurrentGateInfo.all.first { $0.id == "chs-active-pass" }?.isOnline == false)
    }

    /// The origin bug: Sechelt Rapids must be findable by name AND alias.
    func testSecheltIsSearchable() throws {
        let sechelt = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == "chs-sechelt-rapids" })
        XCTAssert(sechelt.isOnline)
        XCTAssertEqual(sechelt.magnitudeNote,
                       "16.5 kn flood · 16 kn ebb")
        for query in ["sechelt", "skookumchuck"] {
            XCTAssert(StationItem.search(query, near: firstRunFix).contains { $0.id == sechelt.id },
                      "search '\(query)' did not find Sechelt Rapids")
        }
    }
}
