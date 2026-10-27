// Slackwater — GPL v3. Spoken answers and widget curves for nearby places.
import XCTest
import SwiftUI
import SlackwaterKit
import CoreLocation
@testable import Slackwater

@MainActor final class TideShortcutTests: XCTestCase {
    func testSuggestedPlacesStayWithinSirisExpandedPhraseBudget() throws {
        let service = LocationService.shared
        let savedStatus = service.status
        let defaults = AppGroup.defaults
        let favorites = defaults.object(forKey: AppGroup.favoritesKey)
        let recents = defaults.object(forKey: AppGroup.recentsKey)
        defer {
            service.status = savedStatus
            defaults.set(favorites, forKey: AppGroup.favoritesKey)
            defaults.set(recents, forKey: AppGroup.recentsKey)
        }
        service.status = .denied
        let savannah = "noaa/8670870"
        defaults.set([savannah, savannah, "current:noaa/PUG1701"], forKey: AppGroup.favoritesKey)
        defaults.set([savannah], forKey: AppGroup.recentsKey)
        let tides = ShortcutPlaceQuery.suggestions(kind: .tide)
        let currents = ShortcutPlaceQuery.suggestions(kind: .current)
        XCTAssertEqual(tides.first?.id, savannah)
        XCTAssertEqual(tides.filter { $0.id == savannah }.count, 1)
        XCTAssertEqual(tides.map(\.id), [savannah])
        XCTAssertEqual(currents.map(\.id), ["current:noaa/PUG1701"])
        XCTAssertTrue(currents.allSatisfy { $0.series == .current })
        // Each named action has both “at” and “in” phrases; seven phrases have no place.
        XCTAssertLessThanOrEqual(4 * tides.count + 2 * currents.count + 7, 1_000)
        let tideIDs = StationItem.all.filter { ShortcutPlaceQuery.accepts($0, kind: .tide) }.prefix(150).map(\.id)
        defaults.set(Array(tideIDs), forKey: AppGroup.favoritesKey)
        let many = ShortcutPlaceQuery.suggestions(kind: .tide)
        XCTAssertEqual(many.map(\.id), Array(tideIDs.prefix(100)))
        XCTAssertFalse(ShortcutPlaceQuery.matches("Savannah", kind: .tide).isEmpty)
    }

    func testNamedPlaceUsesLocalThenFavoritesThenRecentsBeforeTheCatalog() throws {
        let choices = ShortcutPlaceQuery.matches("Savannah", kind: .tide)
        XCTAssertGreaterThanOrEqual(choices.count, 4)
        let local = choices[3], favorite = choices[2], recent = choices[1]
        let order = [local.id, favorite.id, recent.id]
        let ranked = ShortcutPlaceQuery.matches("Savannah", kind: .tide, preferredIDs: order)
        XCTAssertEqual(Array(ranked.prefix(3).map(\.id)), order)
        let withoutLocal = ShortcutPlaceQuery.matches("Savannah", kind: .tide,
            preferredIDs: [favorite.id, recent.id])
        XCTAssertEqual(withoutLocal.first?.id, favorite.id)
        let withoutFavorite = ShortcutPlaceQuery.matches("Savannah", kind: .tide, preferredIDs: [recent.id])
        XCTAssertEqual(withoutFavorite.first?.id, recent.id)
        let specific = ShortcutPlaceQuery.matches("Fort Pulaski", kind: .tide, preferredIDs: order)
        XCTAssertTrue(specific.allSatisfy { $0.name == "Fort Pulaski" })
        XCTAssertEqual(Set(ranked.map(\.id)), Set(choices.map(\.id)))
    }

    func testNamedPlaceResolutionUsesSavedListAndOnlyAFreshAuthorizedLocalPlace() throws {
        let suite = "siri-ranking-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = LocationService.shared
        let savedStatus = service.status, savedLocation = service.location
        defer { service.status = savedStatus; service.location = savedLocation }
        let local = try XCTUnwrap(StationItem.byId["noaa/8670870"])
        let favorite = "noaa/8670678", recent = "noaa/8669277"
        defaults.set([favorite], forKey: AppGroup.favoritesKey)
        defaults.set([recent], forKey: AppGroup.recentsKey)
        service.status = .authorizedWhenInUse
        service.location = CLLocation(latitude: local.latitude, longitude: local.longitude)
        XCTAssertEqual(ShortcutPlaceQuery.resolveMatches("Savannah", kind: .tide, defaults: defaults).map(\.id), [local.id])
        service.status = .denied
        XCTAssertEqual(ShortcutPlaceQuery.resolveMatches("Savannah", kind: .tide, defaults: defaults).map(\.id), [favorite])
        defaults.removeObject(forKey: AppGroup.favoritesKey)
        XCTAssertEqual(ShortcutPlaceQuery.resolveMatches("Savannah", kind: .tide, defaults: defaults).map(\.id), [recent])
        service.status = .authorizedWhenInUse
        service.location = CLLocation(coordinate: .init(latitude: local.latitude, longitude: local.longitude),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10,
            timestamp: Date.now.addingTimeInterval(-601))
        XCTAssertEqual(ShortcutPlaceQuery.resolveMatches("Savannah", kind: .tide, defaults: defaults).map(\.id), [recent])
        defaults.removeObject(forKey: AppGroup.recentsKey)
        XCTAssertGreaterThan(ShortcutPlaceQuery.resolveMatches("Savannah", kind: .tide, defaults: defaults).count, 1)
    }

    func testNamedPlaceBestGuessUsesMatchingQualityThenDistance() throws {
        let local = try XCTUnwrap(StationItem.byId["noaa/8670870"])
        let choices = ShortcutPlaceQuery.matches("Savannah", kind: .tide,
            near: (local.latitude, local.longitude))
        XCTAssertEqual(choices.first?.name, "Savannah")
        let regionMatches = choices.filter { $0.searchRank("savannah") == 1 }
        XCTAssertEqual(regionMatches.first?.id, local.id)
    }

    func testDatedCurrentCardDoesNotCountDownFromAFutureMidnight() throws {
        let saved = AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey)
        defer { AppGroup.defaults.set(saved, forKey: AppGroup.slackWindowSpeedKey) }
        AppGroup.defaults.set(0.5, forKey: AppGroup.slackWindowSpeedKey)
        guard case .current(let record, _) = try XCTUnwrap(
            WidgetStationLoader.loadRecord(id: "current:noaa/PUG1701")) else { return XCTFail("expected current") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = record.tz
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2028, month: 10, day: 27)))
        let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: midnight))
        let hours = [-12.0, -6, -2, -1, 0, 1, 2, 6, 12, 18, 24, 30]
        let online = ChsOnlineWindow(stationID: record.id, iwlsName: record.name,
            timezone: record.tz.identifier, fetchedAt: midnight,
            start: midnight.addingTimeInterval(-12 * 3_600), end: midnight.addingTimeInterval(30 * 3_600),
            floodDirection: 0, ebbDirection: 180,
            times: hours.map { midnight.addingTimeInterval($0 * 3_600).timeIntervalSince1970 },
            speeds: [1, 1, 1, 0.4, 0, -0.4, -1, 1, -1, 1, -1, 1])
        let selected = WidgetRecord.current(record, station: online)
        XCTAssertNotNil(WidgetCard.build(selected, now: midnight).countdownEnd,
                        "The fixture must reproduce a widget countdown at the synthetic midnight")
        let result = try XCTUnwrap(SlackWindowShortcutQuery.on(day, at: selected))
        XCTAssertNil(result.card.countdownEnd, "A dated answer must not display a live countdown")
    }

    func testNamedTidePlaceResolvesWithoutLocationAndDoesNotChangeKind() throws {
        let service = LocationService.shared
        let saved = service.status
        defer { service.status = saved }
        service.status = .denied
        let matches = ShortcutPlaceQuery.matches("Savannah", kind: .tide)
        let place = try XCTUnwrap(matches.first)
        XCTAssertTrue(place.name.localizedCaseInsensitiveContains("Savannah"))
        let selected = try ShortcutPlaceQuery.record(id: place.id, kind: .tide)
        guard case .tide(let record, _) = selected else { return XCTFail("expected tide") }
        XCTAssertEqual(record.id, place.id)
        XCTAssertThrowsError(try ShortcutPlaceQuery.record(id: place.id, kind: .current))
        XCTAssertThrowsError(try ShortcutPlaceQuery.record(id: "missing-place", kind: .tide))
    }

    func testPlaceSearchKeepsNamesakesAndFindsAliasesWithoutLoadingPredictions() throws {
        let results = ShortcutPlaceQuery.matches("Friday Harbor", kind: .tide)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.series == .tide })
        let currents = ShortcutPlaceQuery.matches("Friday Harbor", kind: .current)
        XCTAssertTrue(currents.allSatisfy { $0.series == .current })
        XCTAssertTrue(ShortcutPlaceQuery.matches("xyz-no-such-place", kind: .tide).isEmpty)
        XCTAssertTrue(ShortcutPlaceQuery.matches("   ", kind: .tide).isEmpty)
        let namesakes = try XCTUnwrap(StationItem.byPlace.values.first { $0.count > 1 && $0[0].series == .tide })
        let named = ShortcutPlaceQuery.matches(namesakes[0].name, kind: .tide)
        for place in namesakes { XCTAssertTrue(named.contains { $0.id == place.id }) }
        let aliased = try XCTUnwrap(StationItem.all.first { $0.series == .tide && !$0.fields.aliases.isEmpty })
        XCTAssertTrue(ShortcutPlaceQuery.matches(aliased.fields.aliases[0], kind: .tide).contains { $0.id == aliased.id })
    }

    func testRequestedDayKeepsCalendarComponentsInThePlacesZoneAcrossDST() throws {
        var device = Calendar(identifier: .gregorian)
        device.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let selected = try XCTUnwrap(device.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let day = try XCTUnwrap(shortcutDateInterval(selected, in: zone, inputCalendar: device))
        var local = device; local.timeZone = zone
        XCTAssertEqual(local.component(.day, from: day.start), 8)
        XCTAssertEqual(local.component(.hour, from: day.start), 0)
        XCTAssertEqual(day.duration, 23 * 3_600)
        var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = device.timeZone
        XCTAssertEqual(shortcutDateInterval(selected, in: zone, inputCalendar: buddhist), day)
        let autumn = try XCTUnwrap(device.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        XCTAssertEqual(try XCTUnwrap(shortcutDateInterval(autumn, in: zone, inputCalendar: device)).duration, 25 * 3_600)
    }

    func testDatedTidesIncludeEveryMatchingExtremeOnlyInsideTheRequestedDay() throws {
        let selected = try XCTUnwrap(WidgetStationLoader.loadRecord(id: TideStationRecord.fridayHarborID))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 27)))
        let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: date))
        guard case .tide(_, let engine) = selected else { return XCTFail("expected tide") }
        let expected = engine.extremes(from: day.start, to: day.end).filter { $0.kind == .high && $0.time < day.end }
        let result = try XCTUnwrap(TideShortcutQuery.on(day, kind: .high, at: selected))
        XCTAssertGreaterThan(expected.count, 1)
        XCTAssertEqual(result.extremes.map(\.time), expected.map(\.time))
        XCTAssertFalse(result.spoken.contains("in about"), result.spoken)
        XCTAssertTrue(result.spoken.contains("Friday Harbor"), result.spoken)
        for event in expected { XCTAssertTrue(result.spoken.contains(event.time.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone)))) }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.card.graph?.points.last).time, expected.last!.time)
    }

    func testDatedSlackWindowsStayOnTheRequestedDayAndSpeakLocalTimes() throws {
        let saved = AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey)
        defer { AppGroup.defaults.set(saved, forKey: AppGroup.slackWindowSpeedKey) }
        AppGroup.defaults.set(0.5, forKey: AppGroup.slackWindowSpeedKey)
        let date = Date(timeIntervalSince1970: 1_755_800_000)
        let selected = try XCTUnwrap(WidgetStationLoader.loadRecord(id: "current:noaa/PUG1701", at: date))
        let zone = WidgetStationLoader.station(from: selected).tz
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: date))
        let result = try XCTUnwrap(SlackWindowShortcutQuery.on(day, at: selected))
        XCTAssertFalse(result.windows.isEmpty)
        for window in result.windows { XCTAssertLessThan(window.start, day.end); XCTAssertGreaterThan(window.end, day.start) }
        XCTAssertFalse(result.spoken.contains("in about"), result.spoken)
        XCTAssertFalse(result.spoken.contains("open now"), result.spoken)
        XCTAssertEqual(Set(result.windows.map(\.start)).count, result.windows.count)
    }

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
        // The comfort current is shared App Group state; Off would leave no windows to test.
        let saved = AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey)
        defer { AppGroup.defaults.set(saved, forKey: AppGroup.slackWindowSpeedKey) }
        AppGroup.defaults.set(0.5, forKey: AppGroup.slackWindowSpeedKey)
        let selected = try XCTUnwrap(WidgetStationLoader.loadRecord(id: "current:noaa/PUG1701"))
        let next = try XCTUnwrap(SlackWindowShortcutQuery.next(at: selected,
            after: Date(timeIntervalSince1970: 1_755_800_000)))
        let now = next.slack.time.addingTimeInterval(60)
        let active = try XCTUnwrap(SlackWindowShortcutQuery.next(at: selected, after: now))
        XCTAssertLessThan(active.end.timeIntervalSince(now), 7_200)
        XCTAssertEqual(active.card.countdownEnd, active.end)
        guard case .current(_, _, _, _, let isSlack) = active.card.reading else {
            return XCTFail("expected a current reading")
        }
        XCTAssertFalse(isSlack, "a minute after zero is moving water inside the comfort window")
        XCTAssertTrue(try XCTUnwrap(active.card.graph).windows.contains { $0.contains(now) })
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
        XCTAssertThrowsError(try ShortcutPlaceQuery.record(id: gate.id, kind: .current, at: now))
        model.fitDays = gate.fitDays
        try ChsModelStore.saveCurrent(model)
        guard case .current(let complete, _) = try XCTUnwrap(LocalStationQuery.nearest(
            .current, to: (gate.latitude, gate.longitude), at: now)) else { return XCTFail("expected current") }
        XCTAssertEqual(complete.id, gate.id)
        XCTAssertNoThrow(try ShortcutPlaceQuery.record(id: gate.id, kind: .current, at: now))
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
        let zone = WidgetStationLoader.station(from: tide).tz
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: now))
        let datedHigh = try XCTUnwrap(TideShortcutQuery.on(day, kind: .high, at: tide))
        let datedSlack = try XCTUnwrap(SlackWindowShortcutQuery.on(day, at: current))
        for locale in [Bundle.main.preferredLocalizations.first ?? "en"] {
            for largeText in [false, true] {
                for (answer, detail, card, name) in [
                    (high.spoken, high.detail, high.card, "tide"),
                    (slack.spoken, slack.detail, slack.card, "current"),
                    (datedHigh.spoken, datedHigh.detail, datedHigh.card, "dated-tide"),
                    (datedSlack.spoken, datedSlack.detail, datedSlack.card, "dated-current")
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
