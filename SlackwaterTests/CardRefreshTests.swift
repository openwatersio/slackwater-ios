import SwiftUI
import UIKit
import XCTest
@testable import Slackwater

final class CardRefreshTests: XCTestCase {
    func testPredictionRunsOffTheMainThread() async {
        let onMain = await cardPrediction { Thread.isMainThread }
        XCTAssertEqual(onMain, false)
    }

    func testCancelledPredictionDoesNotPublishAResult() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await cardPrediction { 42 }
        }
        let result = await task.value
        XCTAssertNil(result)
    }

    func testCachedSeedKeepsItsCalculationTime() {
        let cache = SeedCache<Int>()
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = cache.value(for: "station", now: start) { 1 }
        let reused = cache.value(for: "station", now: start.addingTimeInterval(55)) { 2 }
        XCTAssertEqual(reused.value, 1)
        XCTAssertEqual(reused.at, start)
        XCTAssertFalse(cardCalculationIsCurrent(reused.at, refreshTime: start.addingTimeInterval(5)))
        let expired = cache.value(for: "station", now: start.addingTimeInterval(60)) { 3 }
        XCTAssertEqual(expired.value, 3)
        XCTAssertEqual(expired.at, start.addingTimeInterval(60))
        let reversed = cache.value(for: "station", now: start.addingTimeInterval(-1)) { 4 }
        XCTAssertEqual(reversed.value, 4)
    }

    func testEagerCalculationSurvivesAnOlderClockUntilTheNextTick() {
        let opened = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(cardCalculationIsCurrent(opened, refreshTime: opened.addingTimeInterval(-55)))
        XCTAssertFalse(cardCalculationIsCurrent(opened, refreshTime: opened.addingTimeInterval(5)))
        XCTAssertFalse(cardCalculationIsCurrent(opened, refreshTime: opened.addingTimeInterval(-60)))
        XCTAssertFalse(cardCalculationIsCurrent(nil, refreshTime: opened))
        XCTAssertTrue(cardCalculationIsCurrent(opened, refreshTime: nil))
    }

    @MainActor
    func testClockRefreshesImmediatelyOnResume() async {
        let first = Date(timeIntervalSince1970: 1_760_000_000)
        let morning = first.addingTimeInterval(43_200)
        var current = first
        var observed: Date?
        let started = expectation(description: "initial active refresh")
        let resumed = expectation(description: "immediate morning refresh")
        func page(_ phase: ScenePhase) -> some View {
            CardTimeProbe { time in
                observed = time
                if time == first { started.fulfill() }
                if time == morning { resumed.fulfill() }
            }
            .modifier(CardRefreshModifier(interval: .seconds(60), now: { current }))
            .environment(\.scenePhase, phase)
        }
        let host = UIHostingController(rootView: page(.active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [started], timeout: 2)
        host.rootView = page(.background)
        try? await Task.sleep(for: .milliseconds(100))
        current = morning
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observed, first)
        host.rootView = page(.active)
        await fulfillment(of: [resumed], timeout: 2)
    }

    @MainActor
    func testPeriodicClockIsCancelledInBackground() async throws {
        var tick = 0
        let updated = expectation(description: "active ticks")
        func page(_ phase: ScenePhase) -> some View {
            CardTimeProbe { time in
                if time == Date(timeIntervalSince1970: 3) { updated.fulfill() }
            }
            .modifier(CardRefreshModifier(interval: .milliseconds(30), now: {
                tick += 1
                return Date(timeIntervalSince1970: Double(tick))
            }))
            .environment(\.scenePhase, phase)
        }
        let host = UIHostingController(rootView: page(.active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [updated], timeout: 2)
        host.rootView = page(.background)
        try await Task.sleep(for: .milliseconds(100))
        let stopped = tick
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(tick, stopped, "The clock kept calculating in the background")
    }

    @MainActor
    func testMountedCardsRedrawWhenTimeAdvances() async throws {
        let tide = try XCTUnwrap(TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID })
        let current = CurrentStationRecord(
            id: "noaa/clock-test", name: "Test current", region: "Test", aliases: [],
            latitude: 48, longitude: -123, timezone: "UTC",
            floodDirection: 90, ebbDirection: 270, meanFlow: 0, tideReference: nil,
            constituents: [.init(name: "M2", amplitude: 2, phase: 0)])
        let evening = appNow().addingTimeInterval(7 * 86_400)
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.isOnline })
        let start = evening.addingTimeInterval(-86_400)
        let offsets = stride(from: 0.0, through: 3 * 86_400, by: 900).map { $0 }
        let online = ChsOnlineWindow(
            stationID: gate.id, iwlsName: gate.name, timezone: "UTC", fetchedAt: evening,
            start: start, end: start.addingTimeInterval(3 * 86_400),
            floodDirection: 90, ebbDirection: 270,
            times: offsets.map { start.timeIntervalSince1970 + $0 },
            speeds: offsets.map { 2 * sin($0 / (6.21 * 3600) * .pi) })
        let derived = DerivedGateRecord(gate: try XCTUnwrap(ChsGateInfo.all.first), port: tide)
        for eager in [false, true] {
            for card in [AnyView(StationCardView(record: tide, imperial: true, eager: eager)),
                         AnyView(CurrentCardView(record: current, eager: eager)),
                         AnyView(DerivedGateCardView(record: derived)),
                         AnyView(OnlineGateCardView(gate: gate, window: online))] {
                func page(_ time: Date) -> some View {
                    card.environment(\.cardRefreshTime, time)
                        .frame(width: 364, height: 168).background(SN.canvas)
                }
                let host = UIHostingController(rootView: page(evening))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 364, height: 168))
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                try await Task.sleep(for: .milliseconds(300))
                host.view.layoutIfNeeded()
                let before = snapshot(host.view)
                host.rootView = page(evening.addingTimeInterval(21_600))
                try await Task.sleep(for: .milliseconds(300))
                host.view.layoutIfNeeded()
                XCTAssertGreaterThan(differingFraction(before, snapshot(host.view)), 0.005,
                                     "The mounted \(eager ? "eager" : "lazy") card kept its evening reading and curve")
            }
        }
    }

    @MainActor
    func testOnlineCardDropsExpiredCachedWindowAfterDayRollover() async throws {
        let gate = ChsCurrentGateInfo(id: "chs-clock-\(UUID().uuidString)", name: "Test", region: "Test",
                                     aliases: [], latitude: 49, longitude: -123, timezone: "UTC",
                                     tideReference: nil, fitDays: 0, provisionalSlackMinutes: nil, online: true)
        let day = dayLocal(appNow().addingTimeInterval(7 * 86_400), gate.tz)
        let span = Timeline.window(anchor: day)
        let offsets = stride(from: 0.0, through: span.end.timeIntervalSince(span.start), by: 900).map { $0 }
        let cached = ChsOnlineWindow(
            stationID: gate.id, iwlsName: gate.name, timezone: "UTC", fetchedAt: day,
            start: span.start, end: span.end, floodDirection: 90, ebbDirection: 270,
            times: offsets.map { span.start.timeIntervalSince1970 + $0 },
            speeds: offsets.map { sin($0 / (6.21 * 3600) * .pi) })
        try ChsModelStore.saveOnline(cached)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl(gate.id)) }
        XCTAssertNotNil(ChsModelStore.loadOnline(gate.id)?.block(covering: day))
        XCTAssertNil(ChsModelStore.loadOnline(gate.id)?.block(covering: day.addingTimeInterval(86_400)))
        func page(_ time: Date) -> some View {
            ChsCurrentGateCardView(gate: gate).environment(\.cardRefreshTime, time)
                .frame(width: 364, height: 168).background(SN.canvas)
        }
        let host = UIHostingController(rootView: page(day.addingTimeInterval(43_200)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 364, height: 168))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let before = snapshot(host.view)
        host.rootView = page(day.addingTimeInterval(86_400 + 43_200))
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(differingFraction(before, snapshot(host.view)), 0.01,
                             "The online card kept yesterday's reading after its cached coverage expired")
    }

    @MainActor
    func testExpiredTidePreviewRemovesItsReadingAndGraph() async throws {
        let tide = try XCTUnwrap(TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID })
        let start = appNow().addingTimeInterval(7 * 86_400)
        let preview = ChsTidePreview(stationID: tide.id, fetchedAt: start, samples:
            (0...96).map { .init(time: start.addingTimeInterval(Double($0) * 900),
                                height: 2 + sin(Double($0) * .pi / 24)) })
        func page(_ time: Date) -> some View {
            StationCardView(record: tide, imperial: true, preview: preview)
                .environment(\.cardRefreshTime, time)
                .frame(width: 364, height: 168).background(SN.canvas)
        }
        let blank = StationCard(name: tide.name, region: tide.region) { EmptyView() }
            .frame(width: 364, height: 168).background(SN.canvas)
        let host = UIHostingController(rootView: AnyView(blank))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 364, height: 168))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutIfNeeded()
        let empty = snapshot(host.view)
        host.rootView = AnyView(page(start.addingTimeInterval(43_200)))
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(differingFraction(empty, snapshot(host.view)), 0.005,
                             "The valid preview must load before checking expiry")
        host.rootView = AnyView(page(start.addingTimeInterval(86_401)))
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        XCTAssertLessThan(differingFraction(empty, snapshot(host.view)), 0.001,
                          "An expired preview must not invent a zero-height reading")
    }

    @MainActor
    private func snapshot(_ view: UIView) -> UIImage {
        UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    @MainActor
    func testClockTicksWhileActive() async {
        var tick = 0
        let updated = expectation(description: "periodic refresh")
        let page = CardTimeProbe { time in
            if time == Date(timeIntervalSince1970: 3) { updated.fulfill() }
        }
        .modifier(CardRefreshModifier(interval: .milliseconds(30), now: {
            tick += 1
            return Date(timeIntervalSince1970: Double(tick))
        }))
        .environment(\.scenePhase, .active)
        let host = UIHostingController(rootView: page)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [updated], timeout: 2)
    }
}

private struct CardTimeProbe: View {
    @Environment(\.cardRefreshTime) private var time
    var changed: (Date?) -> Void

    var body: some View {
        Color.clear.onChange(of: time, initial: true) { _, time in changed(time) }
    }
}
