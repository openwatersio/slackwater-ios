// Slackwater — GPL v3. A long press on the strip offers an alert for the moment under it (docs/alerts.md §7.1–§7.2).
import XCTest

final class AlertPopupTests: ScreenshotTestCase {
    /// Press and hold the middle of the strip, where the plot is.
    private func pressStrip(_ app: XCUIApplication) {
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            .press(forDuration: 1.0)
    }

    func testALongPressOnATideStripOffersAnAlert() {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        pressStrip(app)

        XCTAssert(app.buttons["alert-popup-once"].appears(within: 5))
        XCTAssert(app.buttons["alert-popup-every"].exists)
    }

    /// The pressed moment decides which of the three current phrasings comes back — whichever
    /// of a nearby turn or the slack fallback the magnet actually lands on (both are already
    /// exhaustively covered at the pure-function level: AlertOfferTests.testCurrentAndDerivedOffers,
    /// testTheEveryLabelReadsAsASentence). What this proves is the wiring: a current detail's
    /// press reaches the popup with a current-flavored offer, never a tide one.
    func testALongPressOnACurrentStripOffersACurrentAlert() {
        let app = launch("-seedGate")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        pressStrip(app)

        XCTAssert(app.buttons["alert-popup-every"].appears(within: 5))
        let everyLabel = app.buttons["alert-popup-every"].label
        XCTAssertTrue(everyLabel.contains("slack window") || everyLabel.contains("max flood")
            || everyLabel.contains("max ebb"), "unexpected current label: \(everyLabel)")
    }

    func testAFreeUsersTapOpensTheTierSheet() {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        pressStrip(app)
        XCTAssert(app.buttons["alert-popup-once"].appears(within: 5))
        app.buttons["alert-popup-once"].tap()

        XCTAssert(app.navigationBars["Slackwater Premium"].appears(within: 5))
    }

    func testTheStripIsStillScrubbableAfterThePopupCloses() {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        pressStrip(app)
        XCTAssert(app.buttons["alert-popup-once"].appears(within: 5))
        // The popup's own close control. A tap outside the popover dismisses it too, but on
        // iPad that tap lands somewhere in a split layout and XCUITest can spend minutes
        // retrying it — several times the whole rest of this suite.
        app.descendants(matching: .any)["alert-popup-close"].firstMatch.tap()
        XCTAssert(app.buttons["alert-popup-once"].disappears(within: 5),
                  "the popup stayed open after its close control was tapped")

        let reading = app.descendants(matching: .any)["detail-reading"].firstMatch
        let before = reading.label
        app.otherElements["timeline-strip"].firstMatch.swipeLeft()

        XCTAssertNotEqual(reading.label, before)
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
        let app = launch("-seedGate")
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
        let app = launch("-seedGate")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))

        let before = scrubClock(app)
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6)).tap()
        settleScrub(app)

        XCTAssertNotEqual(scrubClock(app), before, "a tap on the strip left the centerline unmoved")
    }

    /// A tap on the day row still opens the week picker rather than a press-and-hold popup —
    /// `handlePress` and `tapTarget` read the same row split in opposite senses (fiddly point 2).
    /// The centerline has to be parked on a day's own noon first — that's where its date label
    /// draws — or the nearest label under a raw coordinate can be a sunrise/sunset instead
    /// (DetailAndScrubTests's own day-row test sets up the same way).
    func testATapOnTheDayRowStillOpensTheWeekPicker() {
        let app = launch("-seedGate")
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
        XCTAssertFalse(app.buttons["alert-popup-once"].exists, "a day-row tap must not open the alert popup")
    }
}
