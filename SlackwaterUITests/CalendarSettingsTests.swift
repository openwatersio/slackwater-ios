// Slackwater — GPL v3. Settings → Calendar: subscribe a station, with Premium (docs/alerts.md §7.4).
import XCTest

final class CalendarSettingsTests: ScreenshotTestCase {
    private func openCalendarSettings(_ app: XCUIApplication) {
        let settings = app.navigationBars["Settings"]
        for _ in 0..<3 {
            openSettings(app)
            if settings.appears(within: 5) { break }
        }
        XCTAssert(settings.exists, "Settings did not open after tapping its row")
        let row = app.buttons["settings-calendar-row"].firstMatch
        scrollTo(row, in: app)
        row.tap()
        XCTAssert(app.navigationBars["Favourites calendars"].appears(within: 5))
    }

    /// One tide station and one current station: the two calendar kinds, both in the bundle.
    private let tide = "noaa/9444900"
    private let current = "current:noaa/PUG1701"

    /// Authorization and subscription updates can take longer on hosted runners (#556).
    private let settle: TimeInterval = 60

    func testTheCalendarSectionListsSavedStations() {
        let app = launch("-seedGate", "-seedFavorites", "\(tide),\(current)")
        openCalendarSettings(app)

        XCTAssert(app.switches["calendar-station-\(tide)"].appears(within: 5))
        XCTAssert(app.switches["calendar-station-\(current)"].exists)
    }

    func testAStationWithNoSavedStationsExplainsItself() {
        let app = launch("-seedGate", "-resetFavorites")
        openCalendarSettings(app)

        XCTAssert(app.staticTexts["calendar-empty"].appears(within: 5))
    }

    func testAFreeUsersToggleOpensTheTierSheet() {
        let app = launch("-seedGate", "-resetCalendars", "-seedFavorites", "\(tide),\(current)")
        openCalendarSettings(app)
        let tideSwitch = app.switches["calendar-station-\(tide)"]
        tideSwitch.tap()

        XCTAssert(app.navigationBars["Support Slackwater"].appears(within: 5))
        scrollTo(app.buttons["Restore purchase"], in: app)
        XCTAssert(app.buttons["Restore purchase"].isHittable)
        XCTAssertFalse(app.buttons["settings-calendar-row"].exists)
        app.buttons["premium-done"].tap()
        XCTAssert(app.navigationBars["Favourites calendars"].appears(within: 5))
        XCTAssertEqual(tideSwitch.value as? String, "0")
        save(app, "calendar-after-premium.png")
    }

    /// The calendar prompt is a system alert and only appears on the first run of a fresh sim.
    private func allowCalendarIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard springboard.alerts.firstMatch.appears(within: 6) else { return }
        let alert = springboard.alerts.firstMatch
        // A permission tap can be dropped on a loaded simulator; dismissal is the landed signal (#578).
        for _ in 0..<3 {
            guard alert.exists else { return }
            let button = alert.buttons["Allow Full Access"].firstMatch
            XCTAssert(button.exists, "the calendar permission alert has no Allow Full Access button")
            button.tap()
            if alert.disappears(within: 5) { return }
        }
        XCTFail("the calendar permission alert did not dismiss after allowing full access")
    }

    /// Turning a station off is destructive — its calendar and events go too — so it reads
    /// through a confirmation first (global constraint: nothing synced vanishes without the
    /// user reading the cost first). Dismissing leaves the toggle exactly where it was;
    /// confirming turns it off.
    func testTurningAStationOffAsksFirst() {
        let app = launch("-seedGate", "-seedPremium", "-resetCalendars", "-seedFavorites", tide)
        openCalendarSettings(app)
        let toggle = app.switches["calendar-station-\(tide)"]
        toggle.tap()
        allowCalendarIfAsked()
        XCTAssert(waitFor(toggle, "value == '1'", timeout: settle), "turning on did not settle")

        // A brief tap can miss the iPad switch's press recognizer after permission (#619).
        toggle.press(forDuration: 0.2)
        XCTAssert(app.buttons["Turn Off"].appears(within: 15))
        // On this simulator's confirmationDialog presentation the explicit Cancel role is
        // omitted — Apple's own documented popover behavior: tapping outside the dialog
        // serves as cancel, so an explicit Cancel row would be redundant. Dismiss the same
        // way AlertPopupTests does for its own popover, off-center so the tap can't land on
        // the dialog itself. dy: 0.7, not a point near the top: on iPad, Settings presents as a
        // bounded (not full-screen) sheet and this confirmationDialog anchors as a popover near
        // the toggle — high on screen, not centered the way it renders on iPhone — so a
        // near-top point lands on the popover itself instead of past it. The lower-middle of the
        // screen is empty on both form factors, well below either popover position and still
        // inside the Calendar screen's own bounds.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        XCTAssertEqual(toggle.value as? String, "1", "dismissing outside the dialog must leave the toggle on")

        toggle.tap()
        XCTAssert(app.buttons["Turn Off"].appears(within: 15))
        app.buttons["Turn Off"].tap()
        XCTAssert(waitFor(toggle, "value == '0'"), "confirming did not turn the station off")
    }
}
