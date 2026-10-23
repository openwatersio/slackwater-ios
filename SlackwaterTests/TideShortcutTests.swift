// Slackwater — GPL v3. Spoken answers and widget curves for nearby places.
import XCTest
import SwiftUI
import SlackwaterKit
import CoreLocation
@testable import Slackwater

@MainActor final class TideShortcutTests: XCTestCase {
    func testNoWindowNamesTheNearestPlaceWithoutTryingAFartherOne() throws {
        let record = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/KOD0926" })
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let nearest = try XCTUnwrap(LocalStationQuery.nearest(.current,
            to: (record.latitude, record.longitude), at: now))
        guard case .current(let selected, _) = nearest else { return XCTFail("expected current") }
        XCTAssertEqual(selected.id, record.id)
        XCTAssertNil(SlackWindowShortcutQuery.next(at: nearest, after: now))
        let answer = SlackWindowShortcutQuery.noWindow(at: nearest)
        XCTAssertTrue(answer.contains(record.name), answer)
        XCTAssertTrue(answer.contains("48 hours"), answer)
    }

    func testQueryReturnsTheRequestedTideKind() throws {
        let savedUnits = AppGroup.defaults.object(forKey: unitsKey)
        defer { AppGroup.defaults.set(savedUnits, forKey: unitsKey) }
        AppGroup.defaults.set("imperial", forKey: unitsKey)
        let station = try XCTUnwrap(WidgetStationLoader.loadRecord(id: TideStationRecord.fridayHarborID))
        let now = Date(timeIntervalSince1970: 1_755_800_000)

        let low = try XCTUnwrap(TideShortcutQuery.next(.low, at: station, after: now))
        let high = try XCTUnwrap(TideShortcutQuery.next(.high, at: station, after: now))

        XCTAssertEqual(low.extreme.kind, .low)
        XCTAssertEqual(high.extreme.kind, .high)
        XCTAssertGreaterThan(low.extreme.time, now)
        XCTAssertGreaterThan(high.extreme.time, now)
        XCTAssertTrue(low.spoken.contains("low tide at Friday Harbor"))
        XCTAssertTrue(low.detail.hasSuffix("ft"))

        AppGroup.defaults.set("metric", forKey: unitsKey)
        let metric = try XCTUnwrap(TideShortcutQuery.next(.low, at: station, after: now))
        XCTAssertTrue(metric.detail.hasSuffix("m"))
        XCTAssertTrue(low.detail.hasSuffix("ft"))
        XCTAssertEqual(low.spoken, metric.spoken)
        for result in [low, high] {
            let graph = try XCTUnwrap(result.card.graph)
            XCTAssertEqual(graph.highlight, result.extreme.time...result.extreme.time)
            XCTAssertEqual(graph.now, result.queriedAt)
            XCTAssertEqual(graph.tz, result.timeZone)
            XCTAssertTrue(graph.extremes.contains {
                abs($0.time.timeIntervalSince(result.extreme.time)) < 60
                    && $0.high == (result.extreme.kind == .high)
            })
        }
    }

    func testSpokenTideAnswerUsesRelativeTimingInsteadOfTheDateAndHeight() throws {
        let station = try XCTUnwrap(WidgetStationLoader.loadRecord(id: TideStationRecord.fridayHarborID))
        let result = try XCTUnwrap(TideShortcutQuery.next(.high, at: station,
            after: Date(timeIntervalSince1970: 1_755_800_000)))
        XCTAssertTrue(result.spoken.contains("is in about"), result.spoken)
        XCTAssertFalse(result.spoken.contains("2025"), result.spoken)
        XCTAssertFalse(result.spoken.contains("feet"), result.spoken)
        XCTAssertFalse(result.spoken.contains("metres"), result.spoken)
    }

    func testAnOpenSlackWindowIsStillReturnedAfterItsSlackInstant() throws {
        let record = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/PUG1701" })
        let station = WidgetRecord.current(record, station: record.engineStation)
        let next = try XCTUnwrap(SlackWindowShortcutQuery.next(at: station,
            after: Date(timeIntervalSince1970: 1_755_800_000)))
        let inside = next.slack.time.addingTimeInterval(next.end.timeIntervalSince(next.slack.time) / 2)
        let active = try XCTUnwrap(SlackWindowShortcutQuery.next(at: station, after: inside))
        XCTAssertEqual(active.slack.time.timeIntervalSince1970,
                       next.slack.time.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(active.spoken.contains("is open now"), active.spoken)
    }

    func testMissingLocationDoesNotFallBackToARecentOrDefaultPlace() async throws {
        XCTAssertNil(LocalStationQuery.nearest(.tide, to: nil))
        XCTAssertNil(LocalStationQuery.nearest(.current, to: nil))
        let service = LocationService.shared
        let savedStatus = service.status
        let savedLocation = service.location
        defer {
            service.status = savedStatus
            service.location = savedLocation
        }
        service.status = .denied
        service.location = CLLocation(latitude: 48.5, longitude: -123.0)
        for kind in [LocalStationKind.tide, .current] {
            do {
                _ = try await LocalStationQuery.resolve(kind) {
                    XCTFail("Denied location must not request foreground continuation")
                }
                XCTFail("A denied location must not select a place, even with a cached fix")
            } catch is ShortcutLocationError {
            }
        }
    }

    func testARecentLocationDoesNotRequireForegroundContinuation() async throws {
        let service = LocationService.shared
        let savedStatus = service.status
        let savedLocation = service.location
        defer { service.status = savedStatus; service.location = savedLocation }
        service.status = .authorizedWhenInUse
        service.location = CLLocation(latitude: 48.5, longitude: -123.0)
        let result = try await LocalStationQuery.resolve(.tide) {
            XCTFail("A recent fix should answer directly in Siri")
        }
        XCTAssertNotNil(result)
    }

    func testAStaleLocationRequestsForegroundBeforeStartingLocation() async throws {
        struct ForegroundRequested: Error {}
        let service = LocationService.shared
        let savedStatus = service.status
        let savedLocation = service.location
        let savedLocating = service.locating
        defer { service.status = savedStatus; service.location = savedLocation; service.locating = savedLocating }
        service.status = .authorizedWhenInUse
        service.location = CLLocation(coordinate: .init(latitude: 48.5, longitude: -123.0),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10,
            timestamp: Date.now.addingTimeInterval(-601))
        service.locating = false
        var requested = false
        do {
            _ = try await LocalStationQuery.resolve(.tide) {
                requested = true
                throw ForegroundRequested()
            }
            XCTFail("A stale fix must require foreground preparation")
        } catch is ForegroundRequested {}
        XCTAssertTrue(requested)
        XCTAssertFalse(service.locating, "Do not start Core Location before the system permits foreground execution")
    }

    func testLocationRefreshWaitsForItsOwnDeadlineDespiteSceneActivation() async throws {
        let service = LocationService.shared
        let savedStatus = service.status
        let savedLocation = service.location
        let savedLocating = service.locating
        defer { service.status = savedStatus; service.location = savedLocation; service.locating = savedLocating }
        service.status = .authorizedWhenInUse
        service.location = CLLocation(coordinate: .init(latitude: 48.5, longitude: -123.0),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10,
            timestamp: Date.now.addingTimeInterval(-601))
        let activation = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(150))
            service.refreshIfAuthorized()
            try await Task.sleep(for: .milliseconds(250))
            service.status = .authorizedWhenInUse
            service.location = CLLocation(latitude: 48.5, longitude: -123.0)
        }
        defer { activation.cancel() }
        let result = try await LocalStationQuery.resolve(.tide) {}
        XCTAssertNotNil(result)
    }

    func testOpenWindowCardCountdownAgreesWithTheSpokenClosing() throws {
        let selected = try XCTUnwrap(WidgetStationLoader.loadRecord(id: "current:noaa/PUG1701"))
        let next = try XCTUnwrap(SlackWindowShortcutQuery.next(at: selected,
            after: Date(timeIntervalSince1970: 1_755_800_000)))
        let now = next.slack.time.addingTimeInterval(60)
        let active = try XCTUnwrap(SlackWindowShortcutQuery.next(at: selected, after: now))
        XCTAssertLessThan(active.end.timeIntervalSince(now), 7_200)
        XCTAssertEqual(active.card.countdownEnd, active.end)
        guard case .current(_, _, _, _, let inWindow) = active.card.reading else {
            return XCTFail("expected a current reading")
        }
        XCTAssertTrue(inWindow)
    }

    func testHighlightPreservesAMergedWindowWithObservedBoundaries() throws {
        let saved = AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey)
        defer { AppGroup.defaults.set(saved, forKey: AppGroup.slackWindowSpeedKey) }
        AppGroup.defaults.set(0.5, forKey: AppGroup.slackWindowSpeedKey)
        guard case .current(let record, _) = try XCTUnwrap(
            WidgetStationLoader.loadRecord(id: "current:noaa/PUG1701")) else { return XCTFail("expected current") }
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let hours = [-12.0, 0, 1, 2, 3, 4, 5, 24]
        let online = ChsOnlineWindow(stationID: record.id, iwlsName: record.name,
            timezone: record.tz.identifier, fetchedAt: now,
            start: now.addingTimeInterval(-12 * 3_600), end: now.addingTimeInterval(24 * 3_600),
            floodDirection: 0, ebbDirection: 180,
            times: hours.map { now.addingTimeInterval($0 * 3_600).timeIntervalSince1970 },
            speeds: [1, 1, 1, 0.4, -0.4, 0.4, 1, 1])
        let result = try XCTUnwrap(SlackWindowShortcutQuery.next(
            at: .current(record, station: online), after: now))
        XCTAssertTrue(result.hasOpeningBoundary)
        XCTAssertTrue(result.hasClosingBoundary)
        let graph = try XCTUnwrap(result.card.graph)
        let slacks = graph.slacks.filter { $0 > now }
        XCTAssertEqual(slacks.count, 2)
        XCTAssertTrue(graph.windows.contains { run in slacks.allSatisfy { run.contains($0) } })
    }

    func testSavedCurrentCurveStopsAtItsPredictionBoundary() throws {
        guard case .current(let record, _) = try XCTUnwrap(
            WidgetStationLoader.loadRecord(id: "current:noaa/PUG1701")) else { return XCTFail("expected current") }
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let hours = Array(stride(from: -6.0, through: 54.0, by: 1.0 / 6))
        let online = ChsOnlineWindow(stationID: record.id, iwlsName: record.name,
            timezone: record.tz.identifier, fetchedAt: now,
            start: now.addingTimeInterval(-6 * 3_600), end: now.addingTimeInterval(54 * 3_600),
            floodDirection: 0, ebbDirection: 180,
            times: hours.map { now.addingTimeInterval($0 * 3_600).timeIntervalSince1970 },
            speeds: hours.map { max(-0.1, 48 - $0) })
        let result = try XCTUnwrap(SlackWindowShortcutQuery.next(
            at: .current(record, station: online), after: now))
        XCTAssertFalse(result.hasClosingBoundary)
        XCTAssertFalse(result.spoken.contains("lasts"))
        XCTAssertEqual(try XCTUnwrap(result.card.graph?.highlight).lowerBound, result.start)
        XCTAssertLessThanOrEqual(try XCTUnwrap(result.card.graph).forward,
                                 online.end.timeIntervalSince(now))
    }

    func testWaitsRoundToMinutesWithoutSpeakingZero() {
        XCTAssertEqual(shortcutDuration(10), "1 minute")
        XCTAssertEqual(shortcutDuration(25 * 60), "25 minutes")
        XCTAssertEqual(shortcutDuration(6 * 3_600), "6 hours")
        XCTAssertEqual(shortcutDuration(6 * 3_600 + 25 * 60), "6 hours")
        XCTAssertEqual(shortcutDuration(59 * 60), "59 minutes")
        XCTAssertEqual(shortcutDuration(3_600), "1 hour")
    }

    func testAnUnobservedClosingDoesNotInventRemainingTime() throws {
        let saved = AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey)
        defer { AppGroup.defaults.set(saved, forKey: AppGroup.slackWindowSpeedKey) }
        AppGroup.defaults.set(2.0, forKey: AppGroup.slackWindowSpeedKey)
        guard case .current(let record, _) = try XCTUnwrap(
            WidgetStationLoader.loadRecord(id: "current:noaa/PUG1701")) else { return XCTFail("expected current") }
        let engine = CurrentStation(constituents: [.init(name: "M2", amplitude: 1, phase: 0)],
                                    floodDirection: 0, ebbDirection: 180)
        let result = try XCTUnwrap(SlackWindowShortcutQuery.next(at: .current(record, station: engine),
            after: Date(timeIntervalSince1970: 1_755_800_000)))
        let graph = try XCTUnwrap(result.card.graph)
        let laterSlack = try XCTUnwrap(graph.slacks.last)
        XCTAssertTrue(graph.windows.contains { $0.holdsSlack(at: laterSlack.addingTimeInterval(60)) },
                      "Highlighting the answer must not erase the green band around a neighbouring slack")
        XCTAssertFalse(result.spoken.contains("remaining"), "A sampling limit is not a measured closing")
        XCTAssertNil(result.detail, "Do not display a sampling limit as a real window boundary")
    }

    func testNearestCurrentWaitsForACompleteProvisionalModel() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.offersProvisional })
        let url = ChsModelStore.currentUrl(gate.id)
        let saved = try? Data(contentsOf: url)
        defer {
            if let saved { try? saved.write(to: url) }
            else { try? FileManager.default.removeItem(at: url) }
        }
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        var model = ChsModel(stationID: gate.id, iwlsID: "fixture", iwlsName: gate.name,
                             fittedAt: now, fitStartMs: 0, fitEndMs: 1,
                             fitDays: 60, floodDirection: 0, ebbDirection: 180,
                             offset: 0, rms: 0, constituents: [.init(name: "M2", amplitude: 1, phase: 0)])
        try ChsModelStore.saveCurrent(model)
        guard case .current(let provisional, _) = try XCTUnwrap(WidgetStationLoader.loadRecord(id: gate.id)) else {
            return XCTFail("the saved provisional model must load through the normal widget path")
        }
        XCTAssertEqual(provisional.id, gate.id)
        guard case .current(let selected, _) = try XCTUnwrap(LocalStationQuery.nearest(
            .current, to: (gate.latitude, gate.longitude), at: now)) else { return XCTFail("expected current") }
        XCTAssertNotEqual(selected.id, gate.id, "Siri must not present provisional speeds without their warning")
        model.fitDays = gate.fitDays
        try ChsModelStore.saveCurrent(model)
        guard case .current(let complete, _) = try XCTUnwrap(LocalStationQuery.nearest(
            .current, to: (gate.latitude, gate.longitude), at: now)) else { return XCTFail("expected current") }
        XCTAssertEqual(complete.id, gate.id)
    }

    func testTomorrowUsesThePlacesCalendarAcrossTheSpringDSTChange() throws {
        let station = try XCTUnwrap(WidgetStationLoader.loadRecord(id: TideStationRecord.fridayHarborID))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 8, hour: 23, minute: 59)))
        let result = try XCTUnwrap(TideShortcutQuery.next(.high, at: station, after: now))
        XCTAssertEqual(calendar.component(.day, from: result.extreme.time), 9)
        XCTAssertTrue(result.detail.hasPrefix("Tomorrow"), result.detail)
        XCTAssertFalse(result.detail.contains("2025"), result.detail)
    }

    func testHighTideAfterAnInterveningLowFitsBeyondTheUsualWidgetSpan() throws {
        guard case .tide(let record, _) = try XCTUnwrap(
            WidgetStationLoader.loadRecord(id: TideStationRecord.fridayHarborID)) else {
            return XCTFail("expected tide metadata")
        }
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let engine = Station(constituents: [.init(name: "K1", amplitude: 1, phase: 0)])
        let firstHigh = try XCTUnwrap(engine.extremes(from: now, to: now.addingTimeInterval(172_800))
            .first { $0.kind == .high })
        let queryTime = firstHigh.time.addingTimeInterval(60)
        let result = try XCTUnwrap(TideShortcutQuery.next(.high, at: .tide(record, station: engine), after: queryTime))
        let graph = try XCTUnwrap(result.card.graph)
        XCTAssertGreaterThan(result.extreme.time.timeIntervalSince(queryTime), StationCardGraph.forwardWindow)
        XCTAssertLessThan(try XCTUnwrap(graph.extremes.first { $0.time > queryTime }).time, result.extreme.time)
        XCTAssertGreaterThan(try XCTUnwrap(graph.points.last).time, result.extreme.time)
        XCTAssertGreaterThan(graph.forward, result.extreme.time.timeIntervalSince(queryTime))
        XCTAssertEqual(graph.highlight?.lowerBound, result.extreme.time)
    }

    func testTideAndCurrentSnippetsRenderWithTheSharedWidgetCurves() throws {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let tide = try XCTUnwrap(WidgetStationLoader.loadRecord(id: TideStationRecord.fridayHarborID))
        let current = try XCTUnwrap(WidgetStationLoader.loadRecord(id: "current:noaa/PUG1701", at: now))
        let high = try XCTUnwrap(TideShortcutQuery.next(.high, at: tide, after: now))
        let slack = try XCTUnwrap(SlackWindowShortcutQuery.next(at: current, after: now))
        for locale in [Bundle.main.preferredLocalizations.first ?? "en"] {
            for largeText in [false, true] {
                for (answer, detail, card, name) in [
                    (high.spoken, high.detail, high.card, "tide"),
                    (slack.spoken, slack.detail, slack.card, "current")
                ] {
                    let renderer = ImageRenderer(content:
                        TideShortcutSnippetView(answer: answer, detail: detail, card: card)
                            .frame(width: 350)
                            .environment(\.locale, Locale(identifier: locale))
                            .environment(\.dynamicTypeSize, largeText ? .accessibility1 : .large)
                            .environment(\.colorScheme, .light)
                            .background(Color.white))
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 10_000)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "siri-\(name)-\(locale)-\(largeText ? "large" : "standard")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testNearestStationSeparatesTidesFromCurrents() throws {
        let tide = try XCTUnwrap(TideStationRecord.all.first {
            $0.id == TideStationRecord.fridayHarborID
        })
        let nearestTide = try XCTUnwrap(LocalStationQuery.nearest(
            .tide, to: (tide.latitude, tide.longitude)))
        guard case .tide(let tideRecord, _) = nearestTide else {
            return XCTFail("expected a tide station")
        }
        XCTAssertEqual(tideRecord.name, tide.name)

        let current = CurrentStationRecord.all.first!
        let nearestCurrent = try XCTUnwrap(LocalStationQuery.nearest(
            .current, to: (current.latitude, current.longitude)))
        guard case .current(let currentRecord, _) = nearestCurrent else {
            return XCTFail("expected a current station")
        }
        XCTAssertEqual(currentRecord.name, current.name)
    }

    func testSlackQueryReturnsTheNextMeasuredWindow() throws {
        let record = CurrentStationRecord.all.first!
        let station = WidgetRecord.current(record, station: record.engineStation)
        let now = Date(timeIntervalSince1970: 1_755_800_000)

        let result = try XCTUnwrap(SlackWindowShortcutQuery.next(at: station, after: now))

        XCTAssertLessThan(result.start, result.slack.time)
        XCTAssertGreaterThan(result.end, result.slack.time)
        XCTAssertTrue(result.spoken.contains("slack window at \(record.name)"))
        XCTAssertTrue(result.spoken.contains("starts in about"))
        XCTAssertTrue(result.spoken.contains("lasts about"))
        let graph = try XCTUnwrap(result.card.graph)
        XCTAssertEqual(graph.highlight, result.start...result.end)
        XCTAssertTrue(graph.windows.contains { $0.start == result.start && $0.end == result.end })

        let active = try XCTUnwrap(SlackWindowShortcutQuery.next(
            at: station, after: result.start.addingTimeInterval(60)))
        XCTAssertTrue(active.spoken.contains("is open now"))
    }
}
