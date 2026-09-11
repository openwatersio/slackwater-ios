// Slackwater — GPL v3. The website's screenshot walk: what it saves becomes
// slackwater.xyz/public/shots (and the App Store sets). A generator, not a
// guard — it skips itself unless SLACKWATER_SHOTS reaches the runner, which
// scripts/screenshots.sh arranges along with a 9:41 status bar.
import XCTest

final class WebsiteScreenshots: ScreenshotTestCase {
    /// The day every detail is scrubbed on: a full moon (2026-09-26), so the
    /// night sky has a moon in it. The app clock is shifted there
    /// (`-nowOffsetDays`) so the schedule still says Today.
    private let day = DateComponents(year: 2026, month: 9, day: 26)
    /// Friday Harbor — the located list is shot from here: all-NOAA
    /// neighbours, so every Near Me reading lands without a fit.
    private let fix = ["-fixLat", "48.545", "-fixLon", "-123.013"]

    private func launchShots(_ extra: [String] = [], scrubTo time: String? = nil) -> XCUIApplication {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let target = cal.date(from: day)!
        let offset = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: target).day!
        var args = ["-seedGate", "-resetRecents", "-noCloudSync", "-mapSettleSignal",
                    "-seedFavorites", "noaa/9444900,current:noaa/PUG1701",
                    "-nowOffsetDays", String(offset)] + fix + extra
        if let time {
            args += ["-scrubInstant", String(format: "%04d-%02d-%02dT%@:00-07:00",
                                             day.year!, day.month!, day.day!, time)]
        }
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        // -openMap replaces the list, and its "Slackwater" title, with the map.
        let first = extra.contains("-openMap")
            ? app.otherElements["map-canvas"].firstMatch : app.staticTexts["Slackwater"]
        XCTAssert(first.appears(within: 20), "app did not reach its first screen")
        return app
    }

    /// The scrubbed detail has parked on `clock` and its lead has stopped
    /// rewriting itself.
    private func settleScrub(_ app: XCUIApplication, at clock: String) {
        XCTAssert(leadReading(app).appears(within: 10), "no lead reading")
        XCTAssert(waitFor(leadReading(app), "label CONTAINS '\(clock)'"),
                  "detail did not scrub to \(clock): \(leadReading(app).label)")
        _ = settled { leadReading(app).label }
    }

    func testWebsiteShots() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SLACKWATER_SHOTS"] == nil,
                      "generator — run scripts/screenshots.sh")

        // List: My Location → Favorites → Near Me, every reading landed.
        var app = launchShots()
        XCTAssert(app.staticTexts["MY LOCATION"].appears(within: 10))
        XCTAssert(app.staticTexts["NEAR ME"].appears(within: 10))
        settleLayout(app.staticTexts["NEAR ME"].firstMatch)
        save(app, "list.png")

        // Search: a query with tide and current hits.
        openSearch(app, "pass")
        XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch.appears(within: 10))
        _ = settled { app.staticTexts.count }
        save(app, "search.png")

        // Map: opened on the fix. Tiles never reach the accessibility tree,
        // so the settle signal is followed by a plain wait for them to draw.
        app = launchShots(["-openMap"])
        XCTAssert(app.otherElements["map-canvas"].firstMatch.appears(within: 10))
        XCTAssert(waitFor(app.staticTexts["map-settles"].firstMatch, "label != '0'"),
                  "map never settled")
        sleep(5)
        save(app, "map.png")

        // Tides: Friday Harbor at noon and at night under the full moon.
        for (time, clock, name) in [("13:00", "1:00pm", "tides-day.png"),
                                    ("23:30", "11:30pm", "tides-night.png")] {
            app = launchShots(scrubTo: time)
            openFridayHarbor(app)
            settleScrub(app, at: clock)
            save(app, name)
        }

        // Currents: Deception Pass at noon and at sunrise.
        for (time, clock, name) in [("13:00", "1:00pm", "currents-day.png"),
                                    ("07:10", "7:10am", "currents-sunrise.png")] {
            app = launchShots(scrubTo: time)
            openSearch(app, "deception")
            pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
            assertCurrentDetailRendered(app)
            settleScrub(app, at: clock)
            save(app, name)
        }
    }
}
