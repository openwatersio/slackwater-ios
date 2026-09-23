// Slackwater — GPL v3. The website's screenshot walk: what it saves becomes
// slackwater.xyz/public/shots. A generator, not a guard — it skips itself
// unless SLACKWATER_SHOTS reaches the runner, which scripts/screenshots.sh
// arranges along with a 9:41 status bar. The day, the location fix and the
// favorites it shoots in are `ShotWalk`'s; the App Store sets shoot in the
// same world (AppStoreScreenshots.swift).
import XCTest

final class WebsiteScreenshots: ShotWalk {
    func testWebsiteShots() throws {
        try skipUnlessShooting()

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

        // Map: opened on the fix, then a plain wait for the tiles. Nothing
        // the map draws reaches the accessibility tree, so there is no
        // element to wait on — and a predicate aimed at one that does not
        // exist reads its empty label and passes at t=0, which is a wait that
        // never waits.
        app = launchShots(["-openMap"])
        XCTAssert(app.otherElements["map-canvas"].firstMatch.appears(within: 10))
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
