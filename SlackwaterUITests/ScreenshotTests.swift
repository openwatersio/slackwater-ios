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

    // M3: Canadian (CHS) stations — pending state, a REAL end-to-end fit
    // against live IWLS, then the airplane-mode day-after relaunch. One test,
    // in order, because the offline half depends on the fit half's stored model.
    // Offline mechanism: `-networkKillSwitch` (every IWLS request throws before
    // the socket) + `-nowOffsetDays 1` (the app clock reads tomorrow).
    func testM3ChsPendingFitOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels"]  // clean first-run
        app.launch()

        // Back off the launch detail (Friday Harbor, NOAA — unaffected throughout).
        XCTAssert(app.staticTexts["Friday Harbor"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))

        // Victoria is pending (or already mid-fit): identity + honest message, no numbers.
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("victoria")
        let pending = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'signal' OR label CONTAINS 'Fitting'")).firstMatch
        XCTAssert(pending.waitForExistence(timeout: 10))
        sleep(1)
        save(app, "m3-pending.png")

        // Live IWLS fetch (10 polite requests) + JSCore fit. The card becomes
        // a navigable tide card when the model lands.
        let fitted = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Victoria'")).firstMatch
        XCTAssert(fitted.waitForExistence(timeout: 300), "Victoria never fitted — IWLS unreachable?")
        sleep(1)
        fitted.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        // The provenance marking (fitted-model vs authoritative-harmonic).
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'fitted on this device'")).firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        save(app, "m3-fitted-detail.png")

        // Airplane-mode day-after: relaunch offline, clock shifted to tomorrow.
        app.terminate()
        app.launchArguments = ["-networkKillSwitch", "-nowOffsetDays", "1"]
        app.launch()
        XCTAssert(app.staticTexts["Friday Harbor"].waitForExistence(timeout: 10))  // NOAA still fine
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let field2 = app.textFields.firstMatch
        field2.tap()
        field2.typeText("victoria")
        let offlineCard = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Victoria'")).firstMatch
        XCTAssert(offlineCard.waitForExistence(timeout: 10), "stored model did not survive relaunch")
        offlineCard.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["↑ HIGH"].firstMatch.waitForExistence(timeout: 5)
                  || app.staticTexts["↓ LOW"].firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        save(app, "m3-offline.png")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: shotDir + "/" + name))
    }
}
