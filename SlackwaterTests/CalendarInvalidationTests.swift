// Slackwater — GPL v3. Rejected models cannot leave generated current events behind.
import XCTest
@testable import Slackwater

final class CalendarInvalidationTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "calendar-invalidation-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    func testOnlyFutureEventsWithTheAffectedStationsMintedURLAreRemoved() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000), id = "chs-dodd-narrows"
        let own = deepLink(forStationID: id)
        let shared = try XCTUnwrap(shareURL(forStationID: id, at: now, tz: .gmt))
        let events: [(start: Date, url: URL?)] = [
            (now.addingTimeInterval(1), own),
            (now.addingTimeInterval(2), shared),
            (now.addingTimeInterval(-1), own),
            (now, own),
            (now.addingTimeInterval(1), nil),
            (now.addingTimeInterval(1), URL(string: "https://example.com/manual")),
            (now.addingTimeInterval(1), deepLink(forStationID: "chs-active-pass")),
        ]
        XCTAssertEqual(calendarInvalidationRemovals(events, stationID: id, now: now), [0, 1])
    }

    @MainActor func testInvalidationSurvivesFailedClearsAndAcknowledgesOnlySuccess() {
        let d = defaults()
        CurrentCalendarInvalidations.record(["chs-dodd-narrows", "chs-active-pass"], in: d)
        CurrentCalendarInvalidations.retry(in: d) { _ in false }
        XCTAssertEqual(CurrentCalendarInvalidations.pending(in: d), ["chs-dodd-narrows", "chs-active-pass"])
        CurrentCalendarInvalidations.retry(in: d) { $0 == "chs-dodd-narrows" }
        XCTAssertEqual(CurrentCalendarInvalidations.pending(in: d), ["chs-active-pass"])
        CurrentCalendarInvalidations.retry(in: d) { _ in true }
        XCTAssertTrue(CurrentCalendarInvalidations.pending(in: d).isEmpty)
    }

    @MainActor func testOldFileScanMarksAndRetainsFilesUntilRefitOrChunkSweep() throws {
        let fitted = try XCTUnwrap(ChsCurrentGateInfo.all.first { !$0.isOnline })
        let online = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.isOnline })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func legacy(_ id: String) -> ChsModel {
            ChsModel(stationID: id, iwlsID: "fixture", iwlsName: "Fixture", fittedAt: .now,
                     fitStartMs: 0, fitEndMs: 1, fitDays: 60, offset: 0, rms: 0,
                     constituents: [.init(name: "M2", amplitude: 1, phase: 0)])
        }
        let fittedName = fitted.id + "-current.json", onlineName = online.id + "-current.json"
        try JSONEncoder().encode(legacy(fitted.id)).write(to: dir.appendingPathComponent(fittedName))
        try JSONEncoder().encode(legacy(online.id)).write(to: dir.appendingPathComponent(onlineName))
        let d = defaults()
        ChsFitService.invalidateCurrentCalendars(in: [fittedName, onlineName], directory: dir, defaults: d)
        XCTAssertEqual(CurrentCalendarInvalidations.pending(in: d), [fitted.id, online.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(fittedName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(onlineName).path))
    }

    @MainActor func testMissingOnlineCoverageDoesNotInvalidateCalendars() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let d = defaults()
        ChsFitService.invalidateCurrentCalendars(in: [], directory: dir, defaults: d)
        XCTAssertTrue(CurrentCalendarInvalidations.pending(in: d).isEmpty)
    }

    @MainActor func testCompatibleStoredModelDoesNotInvalidateItsCalendar() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { !$0.isOnline })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ChsModel(stationID: gate.id, iwlsID: "fixture", iwlsName: gate.name, fittedAt: .now,
                             fitStartMs: 0, fitEndMs: 1, fitDays: gate.fitDays, recipe: gate.recipe,
                             offset: 0, rms: 0, constituents: [.init(name: "M2", amplitude: 1, phase: 0)])
        let name = gate.id + "-current.json"
        try JSONEncoder().encode(model).write(to: dir.appendingPathComponent(name))
        let d = defaults()
        ChsFitService.invalidateCurrentCalendars(in: [name], directory: dir, defaults: d)
        XCTAssertTrue(CurrentCalendarInvalidations.pending(in: d).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path))
    }
}
