// Slackwater — GPL v3. The download queue's behaviour, mirroring the web's
// offlineSync.test.ts (proximity ordering, claim-the-head, retry) plus the two
// rules iOS adds: promotion is sticky against a later re-sort, and opening a
// failed station re-queues it.
import XCTest
import Combine
@testable import Slackwater

final class ChsQueueTests: XCTestCase {
    @MainActor
    func testLocationUpdatesDoNotRememberAPermanentlyFailedAutomaticGate() throws {
        let markers = savedDownloadMarkers()
        let service = ChsFitService()
        defer { service.resetOnlineStateForTesting(); restoreDownloadMarkers(markers) }
        service.setAllCurrents(false)
        service.accept(.inView)
        service.prioritize(lat: 48.4235, lon: -123.3705, favorites: [])
        service.captureCohort(ids: ["chs-tillicum-bridge"], heroID: "failed-automatic")
        service.noteOnlineFailure("chs-tillicum-bridge", error: "no predictions", permanent: true)
        service.prioritize(lat: 48.4235, lon: -123.3705, favorites: [])
        XCTAssertFalse(AppGroup.defaults.stringArray(forKey: AppGroup.requestedDownloadsKey)?.contains("chs-tillicum-bridge") == true,
                       "a location tick must not remember a terminal failure for relaunch")
    }

    @MainActor
    func testBulkSelectionDoesNotTakeOwnershipOfEarlierAutomaticDownloads() {
        let markers = savedDownloadMarkers()
        let service = ChsFitService()
        defer { service.resetOnlineStateForTesting(); restoreDownloadMarkers(markers) }
        service.accept(.inView)
        service.setAllCurrents(false)
        service.prioritize(lat: 49.1344, lon: -123.8171, favorites: [])
        service.captureCohort(ids: ["chs-johnstone-strait-central"], heroID: "earlier-automatic")
        service.prioritize(lat: 44.65, lon: -63.57, favorites: [])
        service.captureCohort(ids: ["chs-halifax"], heroID: "later-automatic")
        XCTAssertNotNil(service.queue.job("chs-johnstone-strait-central"))
        service.setAllCurrents(true)
        service.setAllCurrents(false)
        XCTAssertNotNil(service.queue.job("chs-johnstone-strait-central"), "unchecking bulk work must keep the earlier automatic download")
    }

    @MainActor
    func testCompletedOnlineRequestsDoNotBecomeRefreshSubscriptions() throws {
        let markers = savedDownloadMarkers()
        let service = ChsFitService()
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.isOnline && ChsModelStore.loadOnline($0.id) == nil })
        defer {
            service.resetOnlineStateForTesting()
            restoreDownloadMarkers(markers)
            try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(gate.id))
        }
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        let span = Timeline.window(anchor: todayLocal(gate.tz))
        try ChsModelStore.saveOnline(ChsOnlineWindow(
            stationID: gate.id, iwlsName: gate.name, timezone: gate.timezone, fetchedAt: appNow(),
            start: span.start, end: span.end, floodDirection: 45, ebbDirection: 225,
            times: [span.start.timeIntervalSince1970, span.end.timeIntervalSince1970], speeds: [1, -1]))
        service.finishOnlineFetch(gate.id)
        XCTAssertFalse(AppGroup.defaults.stringArray(forKey: AppGroup.requestedDownloadsKey)?.contains(gate.id) == true)
        service.retainOnline(gate)
        XCTAssertFalse(AppGroup.defaults.stringArray(forKey: AppGroup.requestedDownloadsKey)?.contains(gate.id) == true,
                       "viewing complete cached predictions must not subscribe to future downloads")
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        service.noteOnlineFailure(gate.id, error: "unavailable", permanent: true)
        XCTAssertFalse(AppGroup.defaults.stringArray(forKey: AppGroup.requestedDownloadsKey)?.contains(gate.id) == true,
                       "a terminal failure must not restart itself on every launch")
    }

    @MainActor
    func testUncheckingRadiiDoesNotRestartUnseenOnlineDownloads() {
        let markers = savedDownloadMarkers()
        let service = ChsFitService()
        let oldTier = service.tier, oldCurrents = service.allCurrentsSelected
        defer {
            service.accept(oldTier)
            service.setAllCurrents(oldCurrents)
            service.resetOnlineStateForTesting()
            restoreDownloadMarkers(markers)
        }
        service.resetOnlineStateForTesting()
        service.setAllCurrents(false)
        service.prioritize(lat: 48.4235, lon: -123.3705, favorites: [])
        service.captureCohort(ids: ["chs-victoria", "chs-tillicum-bridge"], heroID: "online-radius-test")
        service.accept(.everything)
        XCTAssertTrue(service.isFetchingOnline("chs-gabriola-passage"))
        service.accept(.nearby)
        XCTAssertFalse(service.isFetchingOnline("chs-gabriola-passage"))
        service.accept(.inView)
        XCTAssertFalse(service.isFetchingOnline("chs-gabriola-passage"), "unchecking 25 km must not restore an unseen gate 82 km away")
        XCTAssertTrue(service.isFetchingOnline("chs-tillicum-bridge"), "the online gate shown on the list remains automatic")
        XCTAssertTrue(service.declinedNearby, "turning a radius off must not immediately offer it again")
    }

    @MainActor
    func testDeselectingAllCurrentsDoesNotCancelTidesFromAnEarlierFix() {
        let markers = savedDownloadMarkers()
        let service = ChsFitService()
        let oldTier = service.tier, oldCurrents = service.allCurrentsSelected
        defer {
            service.accept(oldTier)
            service.setAllCurrents(oldCurrents)
            service.resetOnlineStateForTesting()
            restoreDownloadMarkers(markers)
        }
        service.prioritize(lat: 48.4235, lon: -123.3705, favorites: [])
        service.accept(.everything)
        service.setAllCurrents(true)
        XCTAssertNotNil(service.queue.job("chs-nanaimo-harbour"))
        service.prioritize(lat: 44.65, lon: -63.57, favorites: [])
        service.setAllCurrents(false)
        XCTAssertNotNil(service.queue.job("chs-nanaimo-harbour"), "the current-only choice must not cancel tide work")
    }

    private var downloadPreferenceKeys: [String] {
        [AppGroup.downloadTierKey, AppGroup.downloadAllCurrentsKey,
         AppGroup.cancelledDownloadsKey, AppGroup.requestedDownloadsKey]
    }

    @MainActor
    private func savedDownloadMarkers() -> [String: Any] {
        Dictionary(uniqueKeysWithValues: downloadPreferenceKeys.compactMap { key in
            AppGroup.defaults.object(forKey: key).map { (key, $0) }
        })
    }

    @MainActor
    private func restoreDownloadMarkers(_ markers: [String: Any]) {
        for key in downloadPreferenceKeys { AppGroup.defaults.set(markers[key], forKey: key) }
    }

    @MainActor
    func testNarrowingChoicesRemovesOnlyUnselectedDownloads() throws {
        let markers = savedDownloadMarkers()
        let service = ChsFitService()
        let oldTier = service.tier, oldCurrents = service.allCurrentsSelected
        defer {
            service.accept(oldTier)
            service.setAllCurrents(oldCurrents)
            service.resetOnlineStateForTesting()
            restoreDownloadMarkers(markers)
        }
        service.accept(.inView)
        service.setAllCurrents(false)
        service.prioritize(lat: 48.4235, lon: -123.3705, favorites: [])
        service.captureCohort(ids: ["chs-victoria"], heroID: "chs-victoria")
        service.accept(.everything)
        XCTAssertNotNil(service.queue.job("chs-nanaimo-harbour"))
        service.accept(.nearby)
        XCTAssertNil(service.queue.job("chs-nanaimo-harbour"))
        XCTAssertNotNil(service.queue.job("chs-victoria"))
        XCTAssertTrue(AppGroup.defaults.stringArray(forKey: AppGroup.cancelledDownloadsKey)?.contains("chs-nanaimo-harbour") == true)
        service.accept(.everything)
        XCTAssertFalse(AppGroup.defaults.stringArray(forKey: AppGroup.cancelledDownloadsKey)?.contains("chs-nanaimo-harbour") == true)
        service.accept(.nearby)

        service.setAllCurrents(true)
        XCTAssertNotNil(service.queue.job("chs-blackney-passage"))
        service.accept(.inView)
        XCTAssertNotNil(service.queue.job("chs-blackney-passage"), "all currents still selects this gate")
        service.setAllCurrents(false)
        XCTAssertNil(service.queue.job("chs-blackney-passage"))
        XCTAssertNotNil(service.queue.job("chs-victoria"))
        XCTAssertEqual(AppGroup.defaults.string(forKey: AppGroup.downloadTierKey), "inView")
        XCTAssertFalse(AppGroup.defaults.bool(forKey: AppGroup.downloadAllCurrentsKey))
    }

    @MainActor
    func testDeselectingAllCurrentsKeepsTheRadiusAndExplicitOnlineRequests() throws {
        let markers = savedDownloadMarkers()
        let service = ChsFitService()
        let oldTier = service.tier, oldCurrents = service.allCurrentsSelected
        service.resetOnlineStateForTesting()
        defer {
            service.accept(oldTier)
            service.setAllCurrents(oldCurrents)
            service.resetOnlineStateForTesting()
            restoreDownloadMarkers(markers)
        }
        service.prioritize(lat: 48.4235, lon: -123.3705, favorites: [])
        service.accept(.everything)
        service.setAllCurrents(true)
        let far = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && distanceKm($0.latitude, $0.longitude, 48.4235, -123.3705) > 150
        })
        let local = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && distanceKm($0.latitude, $0.longitude, 48.4235, -123.3705) < 150
        })
        XCTAssertTrue(service.isFetchingOnline(far.id))
        service.noteOnlineFailure(far.id, error: "offline", permanent: false)
        service.setAllCurrents(false)
        XCTAssertFalse(service.isFetchingOnline(far.id))
        XCTAssertEqual(service.onlineState(far.id), .idle, "deselection clears its retry state")
        XCTAssertTrue(service.isFetchingOnline(local.id), "the selected radius still includes local currents")

        service.setAllCurrents(true)
        XCTAssertTrue(service.prepareOnlineUpdate(far))
        service.setAllCurrents(false)
        XCTAssertTrue(service.isFetchingOnline(far.id), "an explicit request survives bulk deselection")
    }

    func testNarrowingDownloadsKeepsReadySelectedOpenedAndFavoriteJobs() {
        var q = ChsQueue([job("selected", 0, 0), job("ready", 0, 0),
                          job("opened", 0, 0), job("favorite", 0, 0),
                          job("excluded", 0, 0), job("retry", 0, 0)])
        q.set("ready", .ready)
        q.promote("opened")
        q.prefer(["favorite"])
        q.set("excluded", .downloading)
        q.deferRetry("retry", error: "offline", at: t0)

        XCTAssertTrue(q.retainDownloads(Set(["selected"])), "an excluded active job needs cancellation")
        XCTAssertEqual(Set(q.jobs.map(\.id)), Set(["selected", "ready", "opened", "favorite"]))
        XCTAssertNil(q.earliestRetry(after: t0))
        XCTAssertEqual(q.nextPending()?.id, "opened")
        XCTAssertFalse(q.retainDownloads(Set(["selected"])), "unchanged work needs no cancellation")
    }

    func testNarrowingDownloadsDoesNotInterruptARetainedActiveJob() {
        var q = queue()
        q.set("near", .downloading)
        XCTAssertFalse(q.retainDownloads(Set(["near"])))
        XCTAssertEqual(q.jobs.map(\.id), ["near"])
        XCTAssertEqual(q.status("near"), .downloading)
    }

    func testIdleOnlineDownloadsOnlyStayActiveWhenQueuedOrOffline() {
        XCTAssertFalse(ChsFitService.onlineDownloadIsActive(.idle, queued: false, covered: false, online: true))
        XCTAssertTrue(ChsFitService.onlineDownloadIsActive(.idle, queued: true, covered: false, online: true))
        XCTAssertTrue(ChsFitService.onlineDownloadIsActive(.idle, queued: false, covered: false, online: false))
        XCTAssertFalse(ChsFitService.onlineDownloadIsActive(.idle, queued: false, covered: true, online: false))
        XCTAssertTrue(ChsFitService.onlineDownloadIsActive(.deferred(t0), queued: false, covered: false, online: true))
        XCTAssertFalse(ChsFitService.onlineDownloadIsActive(.deferred(t0), queued: false, covered: true, online: true),
                       "the retry skips a gate covering today, so its backoff ends in no fetch")
    }

    @MainActor
    func testManualOnlineUpdateResetsRetryBackoff() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first(where: \.isOnline))
        for _ in 0..<3 {
            service.noteOnlineFailure(gate.id, error: "offline", permanent: false, at: t0)
        }
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        service.noteOnlineFailure(gate.id, error: "offline", permanent: false, at: t0)
        XCTAssertEqual(service.onlineState(gate.id, at: t0),
                       .deferred(t0.addingTimeInterval(ChsQueue.backoff(attempts: 1))))
    }

    @MainActor
    func testManualOnlineUpdateCancelsThePreviousRetryTimer() async throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first(where: \.isOnline))
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        let dueNow = Date.now.addingTimeInterval(-ChsQueue.backoff(attempts: 1))
        service.noteOnlineFailure(gate.id, error: "offline", permanent: false, at: dueNow)
        let retry = service.onlineStates[gate.id]
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(service.onlineStates[gate.id], retry,
                       "preparation must cancel the timer even before a new fetch begins")
        service.beginOnlineFetch(gate)
        XCTAssertFalse(service.prepareOnlineUpdate(gate), "an active fetch must not be reset")
        XCTAssertEqual(service.onlineState(gate.id), .fetching,
                       "the old timer must not reset an in-flight manual update to idle")
    }

    @MainActor
    func testPreparingManualUpdateDoesNotReleaseAPendingWeekRetry() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first(where: \.isOnline))
        service.noteOnlineFailure(gate.id, error: "offline", permanent: false)
        var states: [ChsFitService.OnlineFetchState] = []
        let subscription = service.$onlineStates.sink { values in
            if let state = values[gate.id] { states.append(state) }
        }
        defer { subscription.cancel() }
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        service.beginOnlineFetch(gate)
        XCTAssertFalse(states.contains(.idle),
                       "An idle transition releases the detail's pending-week retry before the manual fetch starts")
        XCTAssertEqual(states.last, .fetching)
    }

    @MainActor
    func testEveryOnlineFetchCancelsThePreviousRetryTimer() async throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first(where: \.isOnline))
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        let dueNow = Date.now.addingTimeInterval(-ChsQueue.backoff(attempts: 1))
        service.noteOnlineFailure(gate.id, error: "offline", permanent: false, at: dueNow)
        service.beginOnlineFetch(gate)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(service.onlineState(gate.id), .fetching,
                       "A retry through any caller must cancel the old timer before it starts fetching")
    }

    @MainActor
    func testAnExpiredWindowNobodyFetchesIsOutsideTheCount() throws {
        let service = ChsFitService.shared
        try XCTSkipIf(service.allCurrentsSelected, "every online gate is fetched when all currents are selected")
        service.resetOnlineStateForTesting()
        let unwritten = ChsCurrentGateInfo.all.filter { $0.isOnline && ChsModelStore.loadOnline($0.id) == nil }
        try XCTSkipIf(unwritten.count < 2, "needs two online gates with nothing on disk")
        let (fetched, stale) = (unwritten[0], unwritten[1])
        defer {
            service.resetOnlineStateForTesting()
            try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(stale.id))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stale.tz
        let span = Timeline.window(anchor: calendar.date(byAdding: .day, value: -60, to: todayLocal(stale.tz))!)
        try ChsModelStore.saveOnline(ChsOnlineWindow(
            stationID: stale.id, iwlsName: stale.name, timezone: stale.timezone, fetchedAt: appNow(),
            start: span.start, end: span.end, floodDirection: 45, ebbDirection: 225,
            times: [span.start.timeIntervalSince1970, span.end.timeIntervalSince1970], speeds: [1, -1]))
        service.beginOnlineFetch(fetched)
        let count = service.onlineDownloads
        XCTAssertEqual(count.total, 1, "a window nothing will refresh would hold the count short of done for good")
        XCTAssertEqual(count.ready, 0)
    }

    @MainActor
    func testAnIdleGateIsNotQueuedWhileTheLoopRuns() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        let wasRunning = service.onlineRunningForTesting
        defer {
            service.onlineRunningForTesting = wasRunning
            service.resetOnlineStateForTesting()
        }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id)?.block(covering: todayLocal($0.tz)) == nil
        })
        service.beginOnlineFetch(gate)
        service.finishOnlineFetch(gate.id)
        service.onlineRunningForTesting = true
        XCTAssertFalse(service.onlineDownloads.inFlight,
                       "a gate outside the queue must not read as downloading because another one is")
        XCTAssertNil(service.onlinePosition(gate.id))
    }

    @MainActor
    func testATappedGateStaysQueuedUntilItsFetchStarts() async throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id)?.block(covering: todayLocal($0.tz)) == nil
        })
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        let ran = expectation(description: "the work ran")
        ChsFitService.startOnlineWork(for: gate) { ran.fulfill() }
        XCTAssertTrue(service.onlineDownloads.inFlight,
                      "the turn before the tap's fetch starts must not read as no work")
        XCTAssertEqual(service.onlinePosition(gate.id), 1)
        await fulfillment(of: [ran], timeout: 5)
        XCTAssertFalse(service.onlineDownloads.inFlight, "the hold must end with the work")
        XCTAssertNil(service.onlinePosition(gate.id))
    }

    @MainActor
    func testAGateStaysQueuedBetweenAnotherWeeksFetchAndTodays() async throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id)?.block(covering: todayLocal($0.tz)) == nil
        })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gate.tz
        let future = calendar.date(byAdding: .day, value: 60, to: todayLocal(gate.tz))!
        let week = onlineWindow(gate, anchor: future)
        var between: (inFlight: Bool, position: Int?)?
        _ = try await ChsFitService.fetchOnlineUpdate(for: gate, from: future) { anchor in
            if anchor == future {
                service.beginOnlineFetch(gate)
                service.finishOnlineFetch(gate.id)
                between = (service.onlineDownloads.inFlight, service.onlinePosition(gate.id))
            }
            return week
        }
        XCTAssertEqual(between?.inFlight, true,
                       "the gate must not read as no work before its follow-up fetch for today")
        XCTAssertEqual(between?.position, 1)
        XCTAssertFalse(service.onlineDownloads.inFlight, "the hold must end with the update")
    }

    @MainActor
    func testRetryingAFailedGateCountsAsWorkBeforeItsFetchStarts() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id)?.block(covering: todayLocal($0.tz)) == nil
        })
        service.noteOnlineFailure(gate.id, error: "no data", permanent: true)
        XCTAssertTrue(service.prepareOnlineUpdate(gate))
        XCTAssertFalse(service.onlineDownloads.inFlight)
        service.holdOnline(gate)
        XCTAssertEqual(service.onlineState(gate.id), .failed("no data"),
                       "preparing keeps the old state until the fetch starts")
        XCTAssertTrue(service.onlineDownloads.inFlight,
                      "a retry about to start must not read as no work")
    }

    @MainActor
    func testAHeldGateLeavesThePrefetchQueueUntilItsLastRelease() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gates = Array(ChsCurrentGateInfo.all.filter(\.isOnline).prefix(2))
        try XCTSkipIf(gates.count < 2, "needs two online gates")
        service.onlinePendingForTesting = gates
        service.holdOnline(gates[0])
        service.holdOnline(gates[0])
        XCTAssertEqual(service.onlinePendingForTesting.map(\.id), [gates[1].id],
                       "the loop must not fetch today's week ahead of the caller's own fetch")
        service.noteOnlineFailure(gates[0].id, error: "no data", permanent: true)
        service.releaseOnline(gates[0].id)
        XCTAssertEqual(service.onlinePendingForTesting.map(\.id), [gates[1].id])
        service.releaseOnline(gates[0].id)
        XCTAssertEqual(service.onlinePendingForTesting.map(\.id), [gates[1].id, gates[0].id],
                       "a failed fetch for another week must not strand the queue's fetch for today")
    }

    @MainActor
    func testThePrefetchSkipsAHeldGateAndItsReleaseQueuesIt() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gates = Array(ChsCurrentGateInfo.all.filter(\.isOnline).prefix(2))
        try XCTSkipIf(gates.count < 2, "needs two online gates")
        service.holdOnline(gates[0])
        XCTAssertEqual(service.onlineGatesDue(gates).map(\.id), [gates[1].id],
                       "the loop must not fetch today's week ahead of the caller's own fetch")
        service.releaseOnline(gates[0].id)
        XCTAssertEqual(service.onlinePendingForTesting.map(\.id), [gates[0].id],
                       "a prefetch skipped during the hold must still happen")
    }

    @MainActor
    func testADeferredGateIsLeftToItsRetryTimerAfterItsHold() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first(where: \.isOnline))
        service.onlinePendingForTesting = [gate]
        service.holdOnline(gate)
        service.noteOnlineFailure(gate.id, error: "offline", permanent: false)
        service.releaseOnline(gate.id)
        XCTAssertEqual(service.onlinePendingForTesting.map(\.id), [],
                       "queueing it now would skip its backoff")
    }

    @MainActor
    func testAGateThatWasNotQueuedStaysOutAfterItsHold() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first(where: \.isOnline))
        service.holdOnline(gate)
        service.releaseOnline(gate.id)
        XCTAssertEqual(service.onlinePendingForTesting.map(\.id), [])
    }

    @MainActor
    func testAHeldGateCoveredForTodayIsNotQueued() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id) == nil
        })
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(gate.id)) }
        try ChsModelStore.saveOnline(onlineWindow(gate, anchor: todayLocal(gate.tz)))
        service.holdOnline(gate)
        XCTAssertNil(service.onlinePosition(gate.id),
                     "a hold outlives its last fetch by a turn; a covered gate must not read as queued then")
    }

    @MainActor
    func testAnUndecodableOnlineFileIsDecodedOnceUntilItChanges() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id) == nil
        })
        let url = ChsModelStore.onlineUrl(gate.id)
        defer { try? FileManager.default.removeItem(at: url) }
        let span = Timeline.window(anchor: todayLocal(gate.tz))
        try ChsModelStore.saveOnline(ChsOnlineWindow(
            stationID: gate.id, iwlsName: gate.name, timezone: gate.timezone, fetchedAt: appNow(),
            start: span.start, end: span.end, floodDirection: 45, ebbDirection: 225,
            times: [span.start.timeIntervalSince1970, span.end.timeIntervalSince1970], speeds: [1, -1]))
        let valid = try Data(contentsOf: url)
        var broken = valid
        broken[0] = UInt8(ascii: "x")
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let fm = FileManager.default
        try broken.write(to: url)
        try fm.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        XCTAssertNil(ChsModelStore.loadOnline(gate.id))
        // Same size and date: only a cached failure can still answer nil.
        try valid.write(to: url)
        try fm.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        XCTAssertNil(ChsModelStore.loadOnline(gate.id), "a failed decode must be cached, not retried per call")
        try fm.setAttributes([.modificationDate: stamp.addingTimeInterval(1)], ofItemAtPath: url.path)
        XCTAssertNotNil(ChsModelStore.loadOnline(gate.id), "a changed file must be decoded again")
    }

    @MainActor
    func testAnUnreadableOnlineFileIsReadAgainOnceItOpens() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id) == nil
        })
        let url = ChsModelStore.onlineUrl(gate.id)
        let fm = FileManager.default
        defer {
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? fm.removeItem(at: url)
        }
        let span = Timeline.window(anchor: todayLocal(gate.tz))
        try ChsModelStore.saveOnline(ChsOnlineWindow(
            stationID: gate.id, iwlsName: gate.name, timezone: gate.timezone, fetchedAt: appNow(),
            start: span.start, end: span.end, floodDirection: 45, ebbDirection: 225,
            times: [span.start.timeIntervalSince1970, span.end.timeIntervalSince1970], speeds: [1, -1]))
        let stamp = Date(timeIntervalSince1970: 1_700_100_000)
        try fm.setAttributes([.modificationDate: stamp, .posixPermissions: 0], ofItemAtPath: url.path)
        try XCTSkipIf(fm.isReadableFile(atPath: url.path), "the runner can read a 000 file")
        XCTAssertNil(ChsModelStore.loadOnline(gate.id))
        // Readable again with the same date and size, as after first unlock.
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertNotNil(ChsModelStore.loadOnline(gate.id), "a failed read must not be cached as no window")
    }

    @MainActor
    func testCachedCoverageDoesNotHideAnOnlineRefresh() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id) == nil
        })
        defer {
            service.resetOnlineStateForTesting()
            try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(gate.id))
        }
        let span = Timeline.window(anchor: todayLocal(gate.tz))
        try ChsModelStore.saveOnline(ChsOnlineWindow(
            stationID: gate.id, iwlsName: gate.name, timezone: gate.timezone, fetchedAt: appNow(),
            start: span.start, end: span.end, floodDirection: 45, ebbDirection: 225,
            times: [span.start.timeIntervalSince1970, span.end.timeIntervalSince1970], speeds: [1, -1]))
        XCTAssertNotNil(ChsModelStore.loadOnline(gate.id)?.block(covering: todayLocal(gate.tz)))
        service.beginOnlineFetch(gate)
        XCTAssertTrue(service.onlineDownloads.active, "cached predictions must not hide an in-flight refresh")
    }

    @MainActor
    func testBackgroundProgressIncludesOnlineOnlyWork() throws {
        let service = ChsFitService.shared
        service.resetOnlineStateForTesting()
        defer { service.resetOnlineStateForTesting() }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first {
            $0.isOnline && ChsModelStore.loadOnline($0.id)?.block(covering: todayLocal($0.tz)) == nil
        })
        service.beginOnlineFetch(gate)
        service.setOnlineProgress(gate.id, done: 1, total: 2)
        let progress = service.onlineDownloads
        XCTAssertEqual(progress.total, 1)
        XCTAssertEqual(progress.ready, 0)
        XCTAssertTrue(progress.active, "online-only work must keep the background task alive")
        XCTAssertEqual(progress.requestsCompleted, progress.requestsRemaining)
        service.noteOnlineFailure(gate.id, error: "no predictions", permanent: true)
        XCTAssertFalse(service.onlineDownloads.active, "a terminal failure must not hold the task open")
    }

    @MainActor
    func testStationProgressUsesAZeroToTenScale() {
        var station = job("a", 48.4, -123.3)
        XCTAssertEqual(station.downloadProgress, 0)
        station.total = 20
        for (done, expected) in [(-1, 0.0), (8, 4.0), (20, 10.0), (21, 10.0)] {
            station.done = done
            XCTAssertEqual(station.downloadProgress, expected)
            ChsFitService.shared.setOnlineProgress(station.id, done: done, total: station.total)
            XCTAssertEqual(ChsFitService.shared.onlineProgress[station.id], expected)
        }
        station.total = 0
        station.status = .ready
        XCTAssertEqual(station.downloadProgress, 10)
        ChsFitService.shared.resetOnlineStateForTesting()
    }

    func testQueueProgressWeightsStationsByPlannedRequests() {
        var tide = job("tide", 48.4, -123.3)
        tide.status = .ready
        var current = ChsJob(id: "current", name: "Current", region: "BC", isCurrent: true,
                             latitude: 48.5, longitude: -123.4, fitDays: 60,
                             status: .downloading)
        current.done = 10
        current.total = 21

        let progress = ChsQueue([tide, current]).requestProgress
        XCTAssertEqual(progress.completed, 20)
        XCTAssertEqual(progress.total, 31)
    }

    func testOnlyNamedCausesArePermanent() {
        XCTAssert(ChsError.isPermanent(ChsError.permanent("no IWLS station serves wlp")))
        XCTAssertFalse(ChsError.isPermanent(ChsError.transient("HTTP 503")))
        XCTAssertFalse(ChsError.isPermanent(URLError(.timedOut)))
        XCTAssertFalse(ChsError.isPermanent(NSError(domain: NSPOSIXErrorDomain, code: 54)))
        XCTAssertFalse(ChsError.isPermanent(DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "IWLS served nonsense"))))
    }

    func testServiceKeepsAReadableFailureReason() {
        XCTAssertEqual(ChsFitService.reason(ChsError.permanent("no station")), "no station")
        XCTAssertEqual(ChsFitService.reason(ChsError.transient("HTTP 503")), "HTTP 503")
        XCTAssertEqual(ChsFitService.reason(ChsError.networkDisabled), "no connection")
    }

    func testDownloadPriorityOrdersActivityThenUrgency() {
        let states: [(String, ManagedDownloadState, Int?)] = [
            ("permanent", .permanent, nil),
            ("valid-20", .available, 20),
            ("expired", .expired, 0),
            ("not-downloaded", .notDownloaded, nil),
            ("queued", .queued, nil),
            ("valid-5", .available, 5),
            ("failed", .failed, nil),
            ("expiring", .available, 2),
            ("downloading", .downloading, nil),
        ]

        XCTAssertEqual(states.enumerated().sorted {
            let left = downloadSortRank($0.element.1, remainingDays: $0.element.2)
            let right = downloadSortRank($1.element.1, remainingDays: $1.element.2)
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element.0),
        ["downloading", "queued", "expired", "not-downloaded", "failed", "expiring",
         "valid-5", "valid-20", "permanent"])
    }

    func testRowStatusSaysWhatIsHappening() {
        var q = ChsQueue([job("a", 48.4, -123.3)])
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0), "Waiting")
        XCTAssertEqual(rowStatus(q.job("a")!, online: false, at: t0), "Queued")

        q.set("a", .downloading)
        q.setProgress("a", done: 12, total: 31)
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0), "Downloading…")

        q.deferRetry("a", error: "dropped", at: t0)
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0), "Retrying in 1 min")

        q.set("a", .failed)
        q.note("a", error: "IWLS serves no wlp here")
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0),
                       "Download failed")

        q.set("a", .ready)
        XCTAssertEqual(rowStatus(q.job("a")!, online: true, at: t0), "Available offline")
    }

    func testRetryingSortsWithQueuedWork() {
        XCTAssertEqual(downloadSortRank(.retrying, remainingDays: nil),
                       downloadSortRank(.queued, remainingDays: nil))
        XCTAssertLessThan(downloadSortRank(.retrying, remainingDays: nil),
                          downloadSortRank(.failed, remainingDays: nil))
    }

    func testRetryingCardStatusReadsAsWorkInProgress() {
        let status = CardStatus.retrying
        XCTAssertEqual(status.label, "Retrying")
        XCTAssertEqual(status.tint, SN.foam.opacity(0.85))
        XCTAssert(status.showsPlaceholder)
        XCTAssert(status.accessibilityLabel.contains("on its own"))
    }

    func testOnlineGateCardUsesTheServiceFetchState() {
        XCTAssertEqual(onlineGateStatus(nil, online: true, state: .fetching), .downloading)
        XCTAssertEqual(onlineGateStatus(nil, online: true,
                                        state: .deferred(t0.addingTimeInterval(60))), .retrying)
        XCTAssertEqual(onlineGateStatus(nil, online: true, state: .failed("no data")), .failed)
    }
    func testADownloadThatLosesItsSignalSaysOffline() {
        var q = ChsQueue([job("a", 48.4, -123.3)])
        q.set("a", .downloading)
        XCTAssertEqual(cardStatus(q.job("a"), online: true, now: t0), .downloading)
        XCTAssertEqual(cardStatus(q.job("a"), online: false, now: t0), .offline)
        XCTAssertEqual(rowStatus(q.job("a")!, online: false, at: t0), "Queued")
        q.set("a", .failed)
        XCTAssertEqual(cardStatus(q.job("a"), online: false, now: t0), .failed)
    }

    private func job(_ id: String, _ lat: Double, _ lon: Double,
                     current: Bool = false, days: Double = 60) -> ChsJob {
        ChsJob(id: id, name: id, region: "test", isCurrent: current,
               latitude: lat, longitude: lon, fitDays: days)
    }

    /// Victoria-ish origin, and three stations at increasing distance.
    private func queue() -> ChsQueue {
        ChsQueue([job("far", 50.5, -126.9), job("near", 48.43, -123.37), job("mid", 49.3, -123.1)])
    }

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    /// The span a fetch for `anchor` would store, with two samples.
    private func onlineWindow(_ gate: ChsCurrentGateInfo, anchor: Date) -> ChsOnlineWindow {
        let span = Timeline.window(anchor: anchor)
        return ChsOnlineWindow(stationID: gate.id, iwlsName: gate.name, timezone: gate.timezone,
                               fetchedAt: appNow(), start: span.start, end: span.end,
                               floodDirection: 45, ebbDirection: 225,
                               times: [span.start.timeIntervalSince1970, span.end.timeIntervalSince1970],
                               speeds: [1, -1])
    }

    func testADeferredJobIsSkippedUntilItsClockRunsOut() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.set("near", .downloading)
        q.deferRetry("near", error: "HTTP 503", at: t0)

        XCTAssertEqual(q.job("near")?.status, .pending)
        XCTAssertEqual(q.job("near")?.attempts, 1)
        XCTAssertEqual(q.job("near")?.lastError, "HTTP 503")
        XCTAssertEqual(q.nextPending(at: t0)?.id, "mid")
        XCTAssertEqual(q.nextPending(at: t0.addingTimeInterval(61))?.id, "near")
        XCTAssertEqual(q.deferred(at: t0), 1)
        XCTAssertEqual(q.deferred(at: t0.addingTimeInterval(61)), 0)
    }

    func testBackoffDoublesToAFifteenMinuteCeiling() {
        XCTAssertEqual(ChsQueue.backoff(attempts: 1), 60)
        XCTAssertEqual(ChsQueue.backoff(attempts: 2), 120)
        XCTAssertEqual(ChsQueue.backoff(attempts: 3), 240)
        XCTAssertEqual(ChsQueue.backoff(attempts: 4), 480)
        XCTAssertEqual(ChsQueue.backoff(attempts: 5), 900)
        XCTAssertEqual(ChsQueue.backoff(attempts: 50), 900)
    }

    func testAJobCarriesProgressForItsCurrentAttempt() {
        var q = queue()
        q.set("near", .downloading)
        q.setProgress("near", done: 3, total: 11)
        XCTAssertEqual(q.job("near")?.done, 3)
        XCTAssertEqual(q.job("near")?.total, 11)
        q.deferRetry("near", error: "dropped", at: t0)
        XCTAssertEqual(q.job("near")?.done, 0)
    }

    func testTheEstimateScalesWithObservedRequestTime() {
        let port = job("port", 48.4, -123.3)
        XCTAssertEqual(port.estimatedSeconds(perRequest: 10),
                       port.estimatedSeconds(perRequest: 2.5) * 4,
                       accuracy: 0.001)
    }

    func testEarliestRetryIsTheNextJobDue() {
        var q = queue()
        q.set("far", .downloading)
        q.deferRetry("far", error: "dropped", at: t0)
        q.set("near", .downloading)
        q.deferRetry("near", error: "dropped", at: t0.addingTimeInterval(30))
        XCTAssertEqual(q.earliestRetry(after: t0), t0.addingTimeInterval(60))
        XCTAssertNil(q.earliestRetry(after: t0.addingTimeInterval(120)))
    }

    func testPromoteReconnectAndRetryNowClearTheRightFailures() {
        var q = queue()
        q.set("far", .downloading)
        q.deferRetry("far", error: "dropped", at: t0)
        q.promote("far")
        XCTAssertNil(q.job("far")?.retryAfter)
        XCTAssertEqual(q.job("far")?.attempts, 0)

        q.set("mid", .downloading)
        q.deferRetry("mid", error: "dropped", at: t0)
        q.set("near", .failed)
        q.clearBackoffs()
        XCTAssertNil(q.job("mid")?.retryAfter)
        XCTAssertEqual(q.job("near")?.status, .failed)

        q.retryNow()
        XCTAssertEqual(q.job("near")?.status, .pending)
    }

    func testPrioritizeOrdersClosestFirst() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        XCTAssertEqual(q.jobs.map(\.id), ["near", "mid", "far"])
    }

    func testPromoteJumpsToTheFrontAheadOfProximity() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.promote("far")
        XCTAssertEqual(q.jobs.map(\.id), ["far", "near", "mid"])
        XCTAssertTrue(q.isPromoted("far"))
        XCTAssertEqual(q.position("far"), 1, "the station you opened is next up")
    }

    /// The iOS-only rule: a fix landing after you opened a station must not
    /// demote it (the web re-sorts everything and would).
    func testPromotionSurvivesALaterPrioritize() {
        var q = queue()
        q.promote("far")
        q.prioritize(lat: 48.4235, lon: -123.3705)
        XCTAssertEqual(q.jobs.map(\.id), ["far", "near", "mid"])
    }

    func testFavoritesSitBetweenTheViewedStationAndNearbyStations() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.prefer(["mid", "far"])
        q.promote("near")
        XCTAssertEqual(q.jobs.map(\.id), ["near", "mid", "far"])

        q.prefer(["far", "mid"])
        XCTAssertEqual(q.jobs.map(\.id), ["near", "far", "mid"],
                       "a later iCloud reconciliation preserves the new favorite order")
    }

    @MainActor
    func testFavoriteDownloadsMapToTheirRequiredArtifacts() throws {
        let port = try XCTUnwrap(ChsStationInfo.all.first)
        let derived = try XCTUnwrap(ChsGateInfo.all.first)
        let online = try XCTUnwrap(ChsCurrentGateInfo.all.first(where: \.isOnline))
        let noaa = try XCTUnwrap(StationItem.all.first { if case .tide = $0 { true } else { false } })

        let downloads = ChsFitService.favoriteDownloads(
            [port.id, derived.id, online.id, noaa.id, derived.id])

        XCTAssertEqual(downloads.jobIDs, [port.id, derived.reference])
        XCTAssertEqual(downloads.online.map(\.id), [online.id])
    }

    @MainActor
    func testAutoFitTakesEverythingInReachWithAvailableBudgetedJobsFirst() {
        let victoria = (lat: 48.4235, lon: -123.3705)
        let full = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon, constrained: false)
        let near = ChsFitService.autoFitSet(lat: victoria.lat, lon: victoria.lon, constrained: true)

        let availablePorts = full.filter { !$0.isCurrent }.count
        let availableGates = full.filter(\.isCurrent).count
        XCTAssertEqual(near.count, min(availablePorts, ChsFitService.autoFitPorts)
                       + min(availableGates, ChsFitService.autoFitGates))
        XCTAssertGreaterThan(full.count, near.count)
        XCTAssertEqual(Array(full.prefix(near.count)).map(\.id), near.map(\.id))
        XCTAssert(full.allSatisfy {
            distanceKm($0.latitude, $0.longitude, victoria.lat, victoria.lon)
                <= ChsFitService.autoFitRadiusKm
        })
        XCTAssertEqual(Set(full.map(\.id)).count, full.count)

        let tail = Array(full.dropFirst(near.count))
        let firstPort = tail.firstIndex { !$0.isCurrent } ?? tail.count
        let lastGate = tail.lastIndex { $0.isCurrent } ?? -1
        XCTAssertLessThan(lastGate, firstPort)
        XCTAssert(ChsFitService.autoFitSet(lat: 42.3601, lon: -71.0589,
                                           constrained: false).isEmpty)
    }

    @MainActor
    func testOnlinePrefetchAlsoTakesEverythingInReachUnlessConstrained() {
        let full = ChsFitService.autoPrefetchGates(lat: 48.4235, lon: -123.3705,
                                                   constrained: false)
        let near = ChsFitService.autoPrefetchGates(lat: 48.4235, lon: -123.3705,
                                                   constrained: true)
        XCTAssertGreaterThan(full.count, near.count)
        XCTAssertEqual(near.count, ChsFitService.autoFitGates)
        XCTAssertEqual(Array(full.prefix(near.count)).map(\.id), near.map(\.id))
    }

    @MainActor
    func testAnOnlineGateFailureIsRememberedAndDeferred() throws {
        let service = ChsFitService.shared
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.isOnline })
        service.resetOnlineStateForTesting()
        XCTAssertEqual(service.onlineState(gate.id), .idle)

        service.noteOnlineFailure(gate.id, error: "dropped", permanent: false, at: t0)
        XCTAssertEqual(service.onlineState(gate.id, at: t0),
                       .deferred(t0.addingTimeInterval(60)))
        XCTAssertEqual(service.onlineState(gate.id, at: t0.addingTimeInterval(61)), .idle)

        service.noteOnlineFailure(gate.id, error: "no flood axis", permanent: true, at: t0)
        XCTAssertEqual(service.onlineState(gate.id, at: t0.addingTimeInterval(3600)),
                       .failed("no flood axis"))
    }

    func testPromotingAFailedStationRequeuesIt() {
        var q = queue()
        q.set("far", .failed)
        q.promote("far")
        XCTAssertEqual(q.status("far"), .pending)
        XCTAssertEqual(q.nextPending()?.id, "far")
    }

    /// A ready station has nothing to download — promoting it would only
    /// shuffle the manager's list.
    func testPromotingAReadyStationIsANoOp() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.set("far", .ready)
        q.promote("far")
        XCTAssertEqual(q.jobs.map(\.id), ["near", "mid", "far"])
        XCTAssertFalse(q.isPromoted("far"))
    }

    func testNextPendingIsTheHeadAndSkipsClaimedOrFinishedJobs() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        XCTAssertEqual(q.nextPending()?.id, "near")
        q.set("near", .downloading)
        XCTAssertEqual(q.nextPending()?.id, "mid", "a claimed job is never handed out twice")
        q.set("mid", .ready)
        q.set("far", .failed)
        XCTAssertNil(q.nextPending(), "a failed job stays failed until it is retried")
    }

    func testCounts() {
        var q = queue()
        XCTAssertEqual(q.total, 3)
        XCTAssertTrue(q.active)
        XCTAssertFalse(q.complete)
        q.set("near", .ready)
        q.set("mid", .ready)
        q.set("far", .failed)
        XCTAssertEqual(q.ready, 2)
        XCTAssertEqual(q.failed, 1)
        XCTAssertFalse(q.active, "nothing pending or downloading — the run is over")
        q.set("far", .ready)
        XCTAssertTrue(q.complete)
    }

    /// Web restartAll: retry the incomplete ones, leave the ready ones alone.
    func testRetryFailedRequeuesOnlyFailures() {
        var q = queue()
        q.set("near", .ready)
        q.set("mid", .failed)
        q.set("far", .failed)
        q.retryNow()
        XCTAssertEqual(q.status("near"), .ready)
        XCTAssertEqual(q.status("mid"), .pending)
        XCTAssertEqual(q.status("far"), .pending)
    }

    /// The FTUE number: with proximity ordering the nearest station's wait is
    /// its own fetch, not the whole queue's.
    func testWaitSecondsCountsOnlyWhatIsAheadPlusItself() {
        var q = ChsQueue([job("near", 48.43, -123.37),
                          job("gate", 48.5, -123.5, current: true, days: 210)])
        q.prioritize(lat: 48.4235, lon: -123.3705)
        // A 60-day tide port is 10 paced requests; the 210-day gate behind it
        // adds 31 chunks × 2 series + 1 metadata.
        XCTAssertEqual(q.waitSeconds("near"), 10 * 2.5, accuracy: 0.01)
        XCTAssertEqual(q.waitSeconds("gate"), 10 * 2.5 + 63 * 2.5, accuracy: 0.01)
        q.set("near", .ready)
        XCTAssertEqual(q.waitSeconds("gate"), 63 * 2.5, accuracy: 0.01,
                       "a finished station no longer holds anyone up")
        XCTAssertEqual(q.waitSeconds("near"), 0)
    }

    /// M51: the window is the job's own, so a 60-day gate is roughly a third of
    /// a 210-day one — the whole reason four gates skip the provisional stage.
    func testA60DayGateCostsAThirdOfA210DayGate() {
        let fast = job("fast", 48.9, -123.3, current: true, days: 60)
        let full = job("full", 49.1, -123.8, current: true, days: 210)
        XCTAssertEqual(fast.estimatedSeconds(), 21 * 2.5, accuracy: 0.01)   // 10 chunks × 2 + metadata
        XCTAssertEqual(full.estimatedSeconds(), 63 * 2.5, accuracy: 0.01)   // 31 chunks × 2 + metadata
    }

    func testPromotionReordersPendingWorkWithoutInterruptingTheActiveJob() {
        var q = queue()
        q.prioritize(lat: 48.4235, lon: -123.3705)
        q.set("near", .downloading)
        q.promote("far")
        XCTAssertEqual(q.status("near"), .downloading)
        XCTAssertEqual(q.nextPending()?.id, "far")
    }

    func testDurationPhraseIsCoarse() {
        XCTAssertEqual(durationPhrase(22), "under a minute")
        XCTAssertEqual(durationPhrase(155), "about 3 minutes")
        XCTAssertEqual(durationPhrase(3600), "about an hour")
    }

    func testOrdinal() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22]
            .map { ordinal($0, locale: Locale(identifier: "en_US")) },
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])
        XCTAssertEqual([1, 2, 22].map { ordinal($0, locale: Locale(identifier: "fr_CA")) },
                       ["1er", "2e", "22e"])
    }
}
