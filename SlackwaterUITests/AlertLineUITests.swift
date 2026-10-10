// Slackwater — GPL v3. The line under the strip, and the sheet it opens (docs/alerts.md §7.1–§7.2).
import XCTest

final class AlertLineUITests: ScreenshotTestCase {
    /// Press and hold the middle of the strip, where the plot is.
    private func pressStrip(_ app: XCUIApplication) {
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            .press(forDuration: 1.0)
    }

    private func line(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["alert-line"].firstMatch
    }

    private func sheet(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["alert-sheet"].firstMatch
    }

    /// The notification prompt is a system alert and only appears on the first save of a fresh sim.
    private func allowNotificationsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard springboard.alerts.firstMatch.appears(within: 6) else { return }
        let alert = springboard.alerts.firstMatch
        // A permission tap can be dropped on a loaded simulator; dismissal is the landed signal (#578).
        for _ in 0..<3 {
            guard alert.exists else { return }
            let button = alert.buttons["Allow"].firstMatch
            XCTAssert(button.exists, "the notification permission alert has no Allow button")
            button.tap()
            if alert.disappears(within: 5) { return }
        }
        XCTFail("the notification permission alert did not dismiss after allowing")
    }

    func testTheLineRestsUnderATideStripAndOpensTheSheet() {
        let app = launch("-seedGate", "-resetAlerts")
        openFridayHarbor(app)

        XCTAssert(line(app).appears(within: 5))
        XCTAssertEqual(line(app).label, "Set an alert")
        save(app, "alert-line-rest.png")
        line(app).tap()

        XCTAssert(sheet(app).appears(within: 5))
        XCTAssertTrue(app.staticTexts["alert-summary"].label.contains("Low tide"),
                      "an unscrubbed tide strip offers the next low")
        save(app, "alert-sheet-new.png")
    }

    func testALongPressNamesTheMomentOnTheLineUntilTheStripMoves() {
        let app = launch("-seedGate", "-resetAlerts")
        openFridayHarbor(app)
        XCTAssert(line(app).appears(within: 5))
        pressStrip(app)
        XCTAssert(line(app).label.hasPrefix("Set alert for"), "line read: \(line(app).label)")
        save(app, "alert-line-pressed.png")

        // Review Focus 1: a scrub after the press drops the line back to Rest.
        scrubStrip(app)
        settleScrub(app)
        XCTAssertEqual(line(app).label, "Set an alert")
    }

    /// A current detail's press reaches the line with a current-flavoured offer, never a tide one.
    func testALongPressOnACurrentStripOffersACurrentAlert() {
        let app = launch("-seedGate", "-resetAlerts")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(line(app).appears(within: 5))
        pressStrip(app)

        let label = line(app).label
        XCTAssertTrue(label.contains("slack window") || label.contains("max flood") || label.contains("max ebb"),
                      "unexpected current label: \(label)")
    }

    func testAFreeUsersSaveOpensTheTierSheet() {
        // Review Focus 5.
        let app = launch("-seedGate", "-resetAlerts")
        openFridayHarbor(app)
        XCTAssert(line(app).appears(within: 5))
        line(app).tap()
        XCTAssert(app.buttons["alert-sheet-save"].appears(within: 5))
        app.buttons["alert-sheet-save"].tap()

        XCTAssert(app.navigationBars["Support Slackwater"].appears(within: 5))
        scrollTo(app.buttons["Restore purchase"], in: app)
        XCTAssert(app.buttons["Restore purchase"].isHittable)
    }

    func testSavingTurnsTheLineToSet() {
        let app = launch("-seedGate", "-resetAlerts", "-seedPremium")
        openFridayHarbor(app)
        XCTAssert(line(app).appears(within: 5))
        XCTAssertEqual(line(app).label, "Set an alert")
        line(app).tap()
        XCTAssert(app.buttons["alert-sheet-save"].appears(within: 5))
        app.buttons["alert-sheet-save"].tap()
        allowNotificationsIfAsked()

        XCTAssert(sheet(app).disappears(within: 10), "the sheet stayed open after Save")
        XCTAssertTrue(line(app).label.hasPrefix("Alert set"), "line read: \(line(app).label)")
        save(app, "alert-line-set.png")

        // Found again from where it was made: the sheet opens on the rule, with Delete.
        line(app).tap()
        XCTAssert(sheet(app).appears(within: 5))
        // Below the medium detent's fold, and a Form only materializes rows near the screen.
        scrollTo(app.buttons["Delete Alert"], in: app)
        app.buttons["Delete Alert"].tap()
        XCTAssert(sheet(app).disappears(within: 5))
        XCTAssertEqual(line(app).label, "Set an alert")
    }

    /// Not retried: a first swipe swallowed after the sheet is the bug this guards. Hosted
    /// runners have dropped strip swipes with no sheet involved (#613, #664); the native trace
    /// says whether the pan ever began.
    func testTheStripIsStillScrubbableAfterTheSheetCloses() {
        let app = launch("-seedGate", "-resetAlerts",
                         "-scrubTrace", "\(shotDir)/sheet-scrub-\(UUID().uuidString).log")
        openFridayHarbor(app)
        XCTAssert(line(app).appears(within: 5))
        line(app).tap()
        XCTAssert(app.buttons["alert-sheet-cancel"].appears(within: 5))
        app.buttons["alert-sheet-cancel"].tap()
        XCTAssert(sheet(app).disappears(within: 5), "the sheet stayed open after Cancel")

        let reading = app.descendants(matching: .any)["detail-reading"].firstMatch
        let before = reading.label
        app.otherElements["timeline-strip"].firstMatch.swipeLeft()

        XCTAssertNotEqual(reading.label, before, "the first swipe after the sheet closed did not scrub")
    }

    /// The invariant `tap.require(toFail: press)` (TimelineStrip.swift) exists to protect: a
    /// press that ends in a lift leaves the reading exactly where the press put it, with no
    /// second scrub landing on top of it. Off-centre, not `pressStrip`'s centerline — a press
    /// there is self-stabilizing (the jump parks the pressed moment ON the centerline, so a
    /// stray tap recomputed from that same now-shifted screen point lands back on the identical
    /// moment) — off-centre, a stray rescrub would land on a visibly different one. In practice
    /// removing `require(toFail:)` does not fail this test on this simulator (iOS's own
    /// continuous-vs-discrete gesture exclusivity already keeps the tap from firing once the
    /// press has begun) — kept anyway as a direct assertion of the documented invariant.
    func testAPressDoesNotAlsoFireATapScrub() {
        let app = launch("-seedGate", "-resetAlerts")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))

        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6)).press(forDuration: 1.0)
        let afterPress = scrubClock(app)
        settleScrub(app)  // let a stray tap-triggered glide land, if one fired

        XCTAssertEqual(scrubClock(app), afterPress, "a lifted press also fired a tap-triggered scrub")
    }

    /// An ordinary tap must still scrub after the press recognizer is added beside it.
    func testAnOrdinaryTapStillScrubsAfterThePressGestureIsAdded() {
        let app = launch("-seedGate", "-resetAlerts")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))

        let before = scrubClock(app)
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6)).tap()
        settleScrub(app)

        XCTAssertNotEqual(scrubClock(app), before, "a tap on the strip left the centerline unmoved")
    }

    /// A tap on the day row still opens the week picker rather than turning the line —
    /// `handlePress` and `tapTarget` read the same row split in opposite senses (fiddly point 2).
    /// The centerline has to be parked on a day's own noon first — that's where its date label
    /// draws — or the nearest label under a raw coordinate can be a sunrise/sunset instead
    /// (DetailAndScrubTests's own day-row test sets up the same way).
    func testATapOnTheDayRowStillOpensTheWeekPicker() {
        let app = launch("-seedGate", "-resetAlerts")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))

        let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
        XCTAssert(bar.appears(within: 10))
        bar.tap()
        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.appears(within: 5))
        stepMonth(app, "Next Month")
        tapDay(app.collectionViews.buttons.element(boundBy: 10))
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()
        settleScrub(app)

        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()

        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.appears(within: 5))
        XCTAssertFalse(sheet(app).exists, "a day-row tap must not open the alert sheet")
    }
}
