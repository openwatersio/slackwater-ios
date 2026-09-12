// Slackwater — GPL v3. The Calendar / Live row sits under tide and current strips, and Live offers Premium to a free user.
import XCTest

final class AlertRowTests: ScreenshotTestCase {
    func testTheRowSitsUnderATideStrip() {
        let app = launch("-seedGate")
        openFridayHarbor(app)

        XCTAssert(app.buttons["alert-calendar-button"].firstMatch.appears(within: 5), "no Calendar button on a tide detail")
        XCTAssert(app.buttons["alert-live-button"].firstMatch.exists, "no Live button on a tide detail")
        save(app, "alert-row-tide.png")
    }

    func testTheRowSitsUnderACurrentStrip() {
        let app = launch("-seedGate")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))

        XCTAssert(app.buttons["alert-calendar-button"].firstMatch.appears(within: 5), "no Calendar button on a current detail")
        XCTAssert(app.buttons["alert-live-button"].firstMatch.exists, "no Live button on a current detail")
    }

    func testLiveOffersPremiumToAFreeUserOnceTheStripRests() {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        let live = app.buttons["alert-live-button"].firstMatch
        XCTAssert(live.appears(within: 5))

        // The strip opens with a slide into place; a tap only counts once it has come to rest.
        sleep(2)
        live.tap()

        XCTAssert(app.navigationBars["Slackwater Premium"].appears(within: 5), "Live did not open the tier sheet")
    }
}
