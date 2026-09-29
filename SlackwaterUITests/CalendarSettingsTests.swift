// Slackwater — GPL v3. Settings → Calendar: subscribe a station, one at a time without Premium (notifications spec §7.4).
import XCTest

final class CalendarSettingsTests: ScreenshotTestCase {
    private func openCalendarSettings(_ app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let row = app.buttons["settings-calendar-row"].firstMatch
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssert(app.navigationBars["Calendar"].appears(within: 5))
    }

    /// One tide station and one current station: the two calendar kinds, both in the bundle.
    private let tide = "noaa/9444900"
    private let current = "current:noaa/PUG1701"

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

    func testAFreeUserTurningOneOnLeavesTheOtherOff() {
        let app = launch("-seedGate", "-resetCalendars", "-seedFavorites", "\(tide),\(current)")
        openCalendarSettings(app)
        let tideSwitch = app.switches["calendar-station-\(tide)"]
        tideSwitch.tap()
        allowCalendarIfAsked(app)

        XCTAssert(waitFor(tideSwitch, "value == '1'", timeout: 15), "turning tide on did not settle")
        XCTAssertEqual(app.switches["calendar-station-\(current)"].value as? String, "0")
    }

    /// The calendar prompt is a system alert and only appears on the first run of a fresh sim.
    private func allowCalendarIfAsked(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard springboard.alerts.firstMatch.appears(within: 6) else { return }
        for label in ["Allow Full Access", "Allow", "OK", "Continue"] {
            let button = springboard.alerts.buttons[label].firstMatch
            if button.exists { button.tap(); return }
        }
    }

    /// Turning a station off is destructive — its calendar and events go too — so it reads
    /// through the same confirmation the free tier's swap does (global constraint: nothing
    /// synced vanishes without the user reading the cost first). Dismissing leaves the toggle
    /// exactly where it was; confirming turns it off.
    func testTurningAStationOffAsksFirst() {
        let app = launch("-seedGate", "-resetCalendars", "-seedFavorites", tide)
        openCalendarSettings(app)
        let toggle = app.switches["calendar-station-\(tide)"]
        toggle.tap()
        allowCalendarIfAsked(app)
        XCTAssert(waitFor(toggle, "value == '1'", timeout: 15), "turning on did not settle")

        toggle.tap()
        XCTAssert(app.buttons["Turn Off"].appears(within: 15))
        // On this simulator's confirmationDialog presentation the explicit Cancel role is
        // omitted — Apple's own documented popover behavior: tapping outside the dialog
        // serves as cancel, so an explicit Cancel row would be redundant. Dismiss the same
        // way AlertPopupTests does for its own popover, off-center so the tap can't land on
        // the dialog itself.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertEqual(toggle.value as? String, "1", "dismissing outside the dialog must leave the toggle on")

        toggle.tap()
        XCTAssert(app.buttons["Turn Off"].appears(within: 15))
        app.buttons["Turn Off"].tap()
        XCTAssert(waitFor(toggle, "value == '0'"), "confirming did not turn the station off")
    }
}
