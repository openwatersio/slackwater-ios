// Slackwater — GPL v3. The first-run tour: the walk, the skip, and the
// assertion that earns its keep — a real swipe advances the stars mark.
import XCTest

final class TourUITests: ScreenshotTestCase {
    func testTourWalksAndSticks() {
        let app = XCUIApplication()
        // ScreenshotTestCase seeds -seedTour by default so every other UI
        // test suppresses the tour; strip it here so it actually fires.
        app.launchArguments = testArguments(["-seedGate", "-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        let mark = app.otherElements["tour-mark"].firstMatch
        XCTAssert(mark.appears(within: 15), "the tour did not fire on the first detail")
        save(app, "tour-read.png")

        // Read → stars → moon → moonCard → star, then done.
        for _ in 0..<4 { app.buttons["tour-next"].tap() }
        XCTAssert(app.buttons["Done"].exists, "the last mark should offer Done")
        app.buttons["tour-next"].tap()
        XCTAssertFalse(mark.exists, "Done must end the tour")

        // One-way: the flag survives a relaunch.
        app.terminate()
        app.launchArguments = testArguments(["-seedGate", "-locAuthorizedNoFix"])
        app.launch()
        XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.appears(within: 5),
                       "a seen tour must not run again")
    }

    // The assertion this whole design rests on: the overlay hit-tests only on
    // its capsule, so the user's own drag reaches the strip underneath. If
    // this regresses the tour still "works" and silently stops teaching.
    func testARealSwipeAdvancesTheStarsMark() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-seedGate", "-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        app.buttons["tour-next"].tap()   // → .stars

        scrubStrip(app)
        settleScrub(app)
        // Advancing off .stars lands on .moon, whose mark names the moon.
        XCTAssert(app.staticTexts["And that is the real moon, at tonight's phase."]
                    .appears(within: 5),
                  "a real drag must advance the stars mark — the overlay is swallowing touches")
    }

    func testSkipEndsItFromTheFirstMark() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-seedGate", "-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        app.buttons["tour-skip"].tap()
        XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.exists)
    }
}
