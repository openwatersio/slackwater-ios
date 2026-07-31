// Slackwater — GPL v3. Walks the M1–M4 surfaces and saves screenshots.
// Doubles as the smoke check that every interaction actually responds.
// M4 launch flow: the app opens on the first-run gate, then the list — tests
// seed or reset that state explicitly (-seedGate / -resetGate) because a
// UserDefaults value passed as a launch argument would mask in-app writes.
import XCTest

final class ScreenshotTests: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["M1_SHOT_DIR"] ?? "/tmp"

    func testM1Walkthrough() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        // M4: launches on the list — when located it ranks by distance, so
        // reach Friday Harbor through search (deterministic either way).
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openFridayHarbor(app)
        sleep(2)

        // Scrub: drag across the chart plot, release — crosshair persists.
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        from.press(forDuration: 0.3, thenDragTo: to)
        sleep(1)
        save(app, "m1-detail-scrubbed.png")

        // Back to the station list; clear the "friday" query.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        if app.buttons["xmark.circle.fill"].firstMatch.exists {
            app.buttons["xmark.circle.fill"].firstMatch.tap()
        }
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
        openFridayHarbor(app)
        sleep(2)
        save(app, "m1-detail-metric.png")
    }

    /// Search "friday" → tap the tide card → detail; clears the query on the
    /// way in so the list is clean when the caller navigates back.
    private func openFridayHarbor(_ app: XCUIApplication) {
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("friday")
        let card = app.staticTexts["Friday Harbor"].firstMatch
        XCTAssert(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
    }

    // M2: current stations join the list; walk into Deception Pass and scrub
    // the signed velocity curve.
    func testM2Currents() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
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
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.35))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
        from.press(forDuration: 0.3, thenDragTo: to)
        sleep(1)
        save(app, "m2-current-scrubbed.png")
    }

    // M3: Canadian (CHS) stations — pending state, a REAL end-to-end fit
    // against live IWLS, then the airplane-mode day-after relaunch. One test,
    // in order, because the offline half depends on the fit half's stored model.
    func testM3ChsPendingFitOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels", "-seedGate"]  // clean first-run
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

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
        app.launchArguments = ["-networkKillSwitch", "-nowOffsetDays", "1", "-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
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

    // M4: first-run gate — the search bypass lands on the fully usable list,
    // and the choice sticks across relaunch. (The Use-My-Location path needs
    // the system permission dialog; exercised manually via simctl privacy.)
    func testM4Gate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGate"]
        app.launch()

        XCTAssert(app.staticTexts["See tides near you"].waitForExistence(timeout: 10))
        XCTAssert(app.buttons["Use My Location"].exists)
        save(app, "m4-ftue-gate.png")
        app.buttons["Or search for a harbor, bay, or channel."].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Friday Harbor"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
    }

    // M4: pin map — opens from the floating button, land + pins render, and a
    // tap on the Deception Pass (Narrows) pin opens its detail. The pin's
    // screen point is pure web-mercator math from the fixed camera
    // (center 48.6,-123.4 · zoom 7 · 512pt world tiles).
    func testM4MapPinToDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        app.buttons["Map"].tap()
        XCTAssert(app.staticTexts["MAP"].waitForExistence(timeout: 5))
        sleep(5)  // let tiles (and Seascape, when reachable) come in
        save(app, "m4-map.png")

        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 5))
        let frame = map.frame
        let world = 512.0 * pow(2.0, 7)  // zoom 7
        func mercator(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
            let x = (lon + 180) / 360 * world
            let phi = lat * .pi / 180
            let y = (1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2 * world
            return (x, y)
        }
        let c = mercator(48.6, -123.4)                            // camera center
        let p = mercator(48.40618896484375, -122.64311981201172)  // Deception Pass (Narrows)
        let nx = (frame.midX + (p.x - c.x) - frame.minX) / frame.width
        let ny = (frame.midY + (p.y - c.y) - frame.minY) / frame.height
        map.coordinate(withNormalizedOffset: CGVector(dx: nx, dy: ny)).tap()

        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5),
                  "map pin tap did not open a station detail")
        XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch.waitForExistence(timeout: 5))
    }

    // M4: the paired current→tide detail on Deception Pass — the pane exists,
    // and every one of the reference port's schedule numbers (time + height of
    // each high/low today) appears verbatim in the gate's merged view: same
    // engine path, same values (current-detail spec §2).
    func testM4PairedTide() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // First: the reference port's own detail — collect today's H/L numbers.
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("deception")
        let port = app.staticTexts["Deception Pass State Park"].firstMatch
        XCTAssert(port.waitForExistence(timeout: 5))
        port.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        sleep(1)
        let portTimes = clockLabels(app)
        let portHeights = heightLabels(app)
        XCTAssert(!portTimes.isEmpty && !portHeights.isEmpty, "no schedule rows read from the port detail")

        // Then: the gate's detail — paired pane present, port numbers verbatim.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let gate = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(gate.waitForExistence(timeout: 5))
        gate.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["TIDE AT DECEPTION PASS STATE PARK"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["↑ HIGH"].firstMatch.waitForExistence(timeout: 5)
                  || app.staticTexts["↓ LOW"].firstMatch.waitForExistence(timeout: 5),
                  "paired tide rows missing from the events table")
        sleep(1)
        save(app, "m4-paired-detail.png")

        let gateTimes = clockLabels(app)
        let gateHeights = heightLabels(app)
        for t in portTimes {
            XCTAssert(gateTimes.contains(t), "port extreme at \(t) missing from paired view (has \(gateTimes))")
        }
        for h in portHeights {
            XCTAssert(gateHeights.contains(h), "port height \(h) missing from paired view (has \(gateHeights))")
        }
    }

    // M4: settings — units share the pill's store; the statement + licenses show.
    func testM4Settings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssert(app.staticTexts["Not for navigation."].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'OpenStreetMap'")).firstMatch.exists)
        sleep(1)
        save(app, "m4-settings.png")
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
    }

    /// All "HH:mm" labels on screen — chart annotations + schedule rows. The
    /// tide detail's set must be a subset of the paired view's merged set.
    private func clockLabels(_ app: XCUIApplication) -> Set<String> {
        let all = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d{2}:\\d{2}$")).allElementsBoundByIndex
        return Set(all.compactMap { $0.exists ? $0.label : nil })
    }

    /// All "N.N ft/m" height labels on screen.
    private func heightLabels(_ app: XCUIApplication) -> Set<String> {
        let all = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d+\\.\\d+ (ft|m)$")).allElementsBoundByIndex
        return Set(all.compactMap { $0.exists ? $0.label : nil })
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: shotDir + "/" + name))
    }
}
