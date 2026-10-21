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
        XCTAssert(app.staticTexts["My Location"].appears(within: 10))
        XCTAssert(app.staticTexts["Near Me"].appears(within: 10))
        settleLayout(app.staticTexts["Near Me"].firstMatch)
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
        for (time, name) in [("13:00", "tides-day.png"),
                             ("23:30", "tides-night.png")] {
            app = launchShots(scrubTo: time)
            openFridayHarbor(app)
            settleScrub(app, at: localizedClock(time))
            save(app, name)
        }

        // Currents: Deception Pass at 1pm.
        app = launchShots(scrubTo: "13:00")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        assertCurrentDetailRendered(app)
        settleScrub(app, at: localizedClock("13:00"))
        save(app, "currents-day.png")

        // The same afternoon off Victoria, for readers on the Canadian side.
        // 3:30pm keeps the sun clear of the reading; at 1pm it sits on it.
        app = launchShots(scrubTo: "15:30")
        openSearch(app, "trial island")
        pickSearchResult(app, app.staticTexts["Trial Island, 4.5 nm SSW of"].firstMatch)
        assertCurrentDetailRendered(app)
        settleScrub(app, at: localizedClock("15:30"))
        save(app, "currents-victoria.png")

        // The kayak page's comfort-current frame, beside a Settings frame at
        // 1.4 kn, so its green windows are drawn at 1.4 kn too. Off Oak Bay,
        // where paddlers cross to Discovery Island, and fast enough that the
        // windows stand apart from the runs between them.
        app = launchShots(["-comfortCurrent", "1.4"], scrubTo: "15:30")
        openSearch(app, "discovery island")
        pickSearchResult(app, app.staticTexts["Discovery Island, 3.0 nm NE of"].firstMatch)
        assertCurrentDetailRendered(app)
        settleScrub(app, at: localizedClock("15:30"))
        save(app, "currents-comfort.png")

        // The boating page's pass frame: Deception Pass with the comfort
        // current at 2 knots, a cruising sailboat's limit rather than a
        // paddler's, so the green windows are the ones a boat would use.
        // 3pm sits inside the window around the 3:06pm turn; at 1pm the sun
        // is drawn over the reading.
        app = launchShots(["-comfortCurrent", "2.0"], scrubTo: "15:00")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        assertCurrentDetailRendered(app)
        settleScrub(app, at: localizedClock("15:00"))
        save(app, "currents-boat.png")

        // The tide-pool page: a fortnight's-lowest low in daylight, which the
        // walk's September day doesn't have — its lower low is at 11:35pm.
        // Friday Harbor's Sunday 6 June 2027 low at 12:31pm is the lowest of
        // that spring's daytime run. The detail at the low, then the Range
        // sheet that names it.
        app = launchShots(epoch: "1812300060", instant: "2027-06-06T12:31:00-07:00")
        openFridayHarbor(app)
        settleScrub(app, at: localizedClock("12:31"))
        save(app, "tides-lowest.png")
        let range = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Range,'")).firstMatch
        XCTAssert(range.appears(within: 10), "no Range tile on the tide detail")
        range.tap()
        XCTAssert(app.navigationBars["Range"].appears(within: 5), "the Range sheet did not open")
        let swings = app.descendants(matching: .any)["range-section-swings"]
        XCTAssert(swings.appears(within: 10))
        // The sheet opens at half height on the swing chart; the fact this
        // page quotes sits under the station's ends. Raise the sheet, then
        // scroll until the fact is on screen.
        // Drags at fixed screen points, not swipes on elements: a swipe
        // lands on an element's centre, and the ends figure's centre starts
        // below the half-height sheet, so a swipe on it scrolls nothing.
        let screen = app.windows.firstMatch
        func drag(from: CGFloat, to: CGFloat) {
            screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                .press(forDuration: 0.1,
                       thenDragTo: screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)))
        }
        let title = app.navigationBars["Range"].frame
        drag(from: (title.midY) / screen.frame.height, to: 0.08)
        let fact = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'lowest low of the fortnight'")).firstMatch
        for _ in 0..<6 where !(fact.exists && fact.isHittable) {
            drag(from: 0.75, to: 0.45)
        }
        XCTAssert(fact.exists && fact.isHittable, "the Range sheet does not call this the fortnight's lowest low")
        _ = settled { app.staticTexts.count }
        save(app, "tides-lowest-range.png")
    }
}
