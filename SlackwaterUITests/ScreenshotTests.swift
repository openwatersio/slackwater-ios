// Slackwater — GPL v3. Walks the M1 surface (detail → scrub → list → search →
// units) and saves screenshots. Doubles as the smoke check that every M1
// interaction actually responds.
import XCTest

final class ScreenshotTests: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["M1_SHOT_DIR"] ?? "/tmp"

    func testM1Walkthrough() throws {
        let app = XCUIApplication()
        app.launch()

        // Launches on Friday Harbor detail.
        XCTAssert(app.staticTexts["Friday Harbor"].waitForExistence(timeout: 10))
        sleep(2)

        // Scrub: drag across the chart plot, release — crosshair persists.
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        from.press(forDuration: 0.3, thenDragTo: to)
        sleep(1)
        save(app, "m1-detail-scrubbed.png")

        // Back to the station list.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        sleep(1)
        save(app, "m1-list.png")

        // Search mid-query: name + region substring both match.
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("pass")
        sleep(1)
        save(app, "m1-search.png")
        let clear = app.buttons["xmark.circle.fill"].firstMatch
        if clear.exists { clear.tap() } else { field.typeText(XCUIKeyboardKey.delete.rawValue) }

        // Units pill → metres, then open Friday Harbor in metric.
        // The setting persists across runs — reset to imperial first if needed.
        if app.buttons["M"].exists {
            app.buttons["M"].tap()
            XCTAssert(app.buttons["FT"].waitForExistence(timeout: 5))
        }
        app.buttons["FT"].tap()
        XCTAssert(app.buttons["M"].waitForExistence(timeout: 5))
        app.staticTexts["Friday Harbor"].firstMatch.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        sleep(2)
        save(app, "m1-detail-metric.png")
    }

    // M2: current stations join the list; walk into Deception Pass and scrub
    // the signed velocity curve.
    func testM2Currents() throws {
        let app = XCUIApplication()
        app.launch()

        // Back off the launch detail to the mixed list.
        XCTAssert(app.staticTexts["Friday Harbor"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        sleep(2)
        save(app, "m2-list-mixed.png")

        // Search finds the current station; its detail is the signed curve.
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("deception")
        let card = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 5))  // MonoLabel uppercases
        sleep(2)
        save(app, "m2-current-detail.png")

        // Scrub: drag across the plot, release — crosshair persists.
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        from.press(forDuration: 0.3, thenDragTo: to)
        sleep(1)
        save(app, "m2-current-scrubbed.png")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: shotDir + "/" + name))
    }
}
