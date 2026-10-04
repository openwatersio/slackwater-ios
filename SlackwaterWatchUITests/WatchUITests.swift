// Slackwater — GPL v3. The watch list and Add Place, driven on a watch
// simulator (#521).
import XCTest

final class WatchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Isolate favorites, recents, and downloaded models; keep the location
        // prompt and real network traffic out of these fixture tests.
        app.launchArguments = ["-resetFavorites", "-resetRecents", "-locDenied", "-noCloudSync", "-networkKillSwitch", "-chsResetModels"]
        app.launch()
    }

    func testNoLocationShowsTheLocationCardAndPlacesStill() {
        XCTAssertTrue(app.descendants(matching: .any)["location-card"].waitForExistence(timeout: 15),
                      app.debugDescription)
        XCTAssertTrue(app.buttons["place-row"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
    }

    func testTypedQueryShowsResults() {
        search("port angeles")
        XCTAssertTrue(app.buttons["search-result"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
    }

    func testQueryWithNoMatchesSaysSo() {
        search("zzqqxx")
        XCTAssertTrue(app.staticTexts["search-empty"].waitForExistence(timeout: 10),
                      app.debugDescription)
    }

    func testSwipesStarAndUnstarAPlace() {
        let first = app.buttons["place-row"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let name = first.label.components(separatedBy: ",").first ?? first.label

        first.swipeRight()
        tapButton("Favorite")
        let starred = app.buttons.matching(NSPredicate(
            format: "identifier == 'place-row' AND label BEGINSWITH %@ AND label CONTAINS 'Favorites'", name))
        XCTAssertTrue(starred.firstMatch.waitForExistence(timeout: 5), app.debugDescription)

        starred.firstMatch.swipeLeft()
        tapButton("Unfavorite")
        // It goes back to Near Me, which outranks Recents (the phone's ListGroups).
        let unstarred = NSPredicate(format: "count == 0")
        expectation(for: unstarred, evaluatedWith: starred)
        waitForExpectations(timeout: 5)
    }

    private func openFirstPlace() {
        let row = app.buttons["place-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        tap(row, until: app.buttons["back-to-list"].firstMatch)
        XCTAssertTrue(app.buttons["reading-card"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testCrownScrubShowsTheX() {
        openFirstPlace()
        XCUIDevice.shared.rotateDigitalCrown(delta: 2.0)
        XCTAssertTrue(app.buttons["return-to-now"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testXReturnsToNowAndThenTheList() {
        openFirstPlace()
        XCUIDevice.shared.rotateDigitalCrown(delta: 8.0)   // far enough to leave the loaded day
        // The toolbar repeats an item's identifier on its nested elements.
        let x = app.buttons["return-to-now"].firstMatch
        XCTAssertTrue(x.waitForExistence(timeout: 5))
        x.tap()
        let list = app.buttons["back-to-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), app.debugDescription)
        list.tap()
        XCTAssertTrue(app.buttons["add-place-row"].exists || app.buttons["place-row"].firstMatch.waitForExistence(timeout: 5))
    }

    func testCardOpensTheSheet() {
        openFirstPlace()
        let card = app.buttons["reading-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["sheet-favorite"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testDetailOffersHandoffToPhone() {
        openFirstPlace()
        app.buttons["reading-card"].tap()
        let phone = app.buttons["open-on-phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5), app.debugDescription)
        scrollIntoView(phone)
        snapshot("watch-phone-action")
        phone.tap()
        XCTAssertTrue(app.staticTexts["To continue, open the app switcher on your iPhone and tap Slackwater."].waitForExistence(timeout: 5))
    }

    func testCanadianDownloadAppearsAfterFitAndSurvivesRelaunch() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-networkKillSwitch" }
        app.launchArguments += ["-chsResetModels", "-chsFitOnly", "chs-victoria",
                                "-chsFixture", UUID().uuidString, "-seedFavorites", "chs-victoria"]
        app.launch()
        let victoria = app.buttons.matching(NSPredicate(
            format: "identifier == 'place-row' AND label CONTAINS 'Victoria' AND label CONTAINS 'Favorites'"))
        XCTAssertTrue(victoria.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        app.terminate()
        app.launchArguments = ["-locDenied", "-networkKillSwitch", "-noCloudSync"]
        app.launch()
        XCTAssertTrue(victoria.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        tap(victoria.firstMatch, until: app.buttons["reading-card"])
    }

    func testInterruptedDownloadStaysHiddenAndReportsInlineStatus() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-networkKillSwitch" }
        app.launchArguments += ["-chsResetModels", "-chsFitOnly", "chs-victoria",
                                "-chsFixture", UUID().uuidString,
                                "-chsFixtureScenario", "hold-first", "-seedFavorites", "chs-victoria"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["watch-download-status"].firstMatch.waitForExistence(timeout: 15),
                      app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.2, thenDragTo:
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        snapshot("watch-download-progress")
        XCTAssertFalse(app.buttons.matching(NSPredicate(
            format: "identifier == 'place-row' AND label CONTAINS 'Victoria' AND label CONTAINS 'Favorites'"))
            .firstMatch.exists)
        app.terminate()
        app.launchArguments = ["-locDenied", "-noCloudSync", "-chsFitOnly", "chs-victoria", "-chsFixture", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "identifier == 'place-row' AND label CONTAINS 'Victoria' AND label CONTAINS 'Favorites'"))
            .firstMatch.waitForExistence(timeout: 30), app.debugDescription)
    }

    func testInterruptedRefinementKeepsItsUsableModel() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-networkKillSwitch" }
        app.launchArguments += ["-chsResetModels", "-chsFitOnly", "chs-dodd-narrows",
                                "-chsFixture", UUID().uuidString,
                                "-chsFixtureScenario", "provisional-final", "-seedFavorites", "chs-dodd-narrows"]
        app.launch()
        let dodd = app.buttons.matching(NSPredicate(
            format: "identifier == 'place-row' AND label CONTAINS 'Dodd Narrows'"))
        for _ in 0..<6 where !dodd.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            _ = dodd.firstMatch.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(dodd.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        app.terminate()
        app.launchArguments = ["-locDenied", "-noCloudSync", "-networkKillSwitch"]
        app.launch()
        for _ in 0..<6 where !dodd.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        XCTAssertTrue(dodd.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(dodd.firstMatch.label.contains("Refining"), dodd.firstMatch.label)
        dodd.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        XCTAssertTrue(app.buttons["reading-card"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testPhoneActionInFrench() {
        checkPhoneAction(language: "fr-CA", label: "Ouvrir sur l’iPhone")
    }

    func testPhoneActionInSpanish() {
        checkPhoneAction(language: "es-ES", label: "Abrir en el iPhone")
    }

    private func checkPhoneAction(language: String, label: String) {
        app.terminate()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        openFirstPlace()
        app.buttons["reading-card"].tap()
        let phone = app.buttons["open-on-phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(phone.label.contains(label), phone.label)
        scrollIntoView(phone)
        snapshot("watch-phone-action-\(language)")
    }

    private func scrollIntoView(_ element: XCUIElement) {
        for _ in 0..<6 {
            let above = element.exists && element.frame.minY < 35
            if element.exists, !above, element.frame.maxY < app.frame.maxY - 10 { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.35 : 0.75))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.65 : 0.35)))
        }
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func search(_ query: String) {
        let field = app.textFields["place-search-field"]
        let addPlace = app.buttons["add-place-row"]
        XCTAssertTrue(app.buttons["place-row"].firstMatch.waitForExistence(timeout: 15))
        // Add Place is the last row, below every card, and the list only
        // builds a row once it scrolls into view.
        for _ in 0..<10 where !(addPlace.exists && addPlace.isHittable) { app.swipeUp() }
        tap(addPlace, until: field)
        field.tap()
        app.typeText(query)
        // The watch's text input is a sheet; nothing reaches the field until Done.
        app.buttons["Done"].tap()
    }

    private func tapButton(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
    }

    /// Taps until `destination` appears. On the watch simulator a tap on a
    /// list row right after launch is sometimes dropped: the second tap
    /// navigates where the first did not, seen in about half of fresh runs.
    /// Whether a device drops it too is a device check (#549).
    private func tap(_ element: XCUIElement, until destination: XCUIElement) {
        for _ in 0..<3 where !destination.exists {
            element.tap()
            _ = destination.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(destination.exists, app.debugDescription)
    }
}
