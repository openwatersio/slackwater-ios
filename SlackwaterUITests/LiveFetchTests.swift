// Slackwater — GPL v3. Explicit, serial IWLS compatibility smoke checks.
import XCTest

final class LiveFetchTests: ScreenshotTestCase {
    func testLiveTideFit() throws {
        try skipUnlessLive()
        let app = launchLive("-seedGate", "-chsResetModels", "-chsFitOnly", "chs-victoria")
        openSearch(app, "victoria")
        let pending = app.descendants(matching: .any)["chs-pending-chs-victoria"].firstMatch
        XCTAssert(pending.waitForExistence(timeout: 15))
        XCTAssert(pending.waitForNonExistence(timeout: 300), "Victoria never fitted from IWLS")
    }

    func testLiveCurrentFit() throws {
        try skipUnlessLive()
        let app = launchLive("-seedGate", "-chsResetModels", "-chsFitOnly", "chs-active-pass")
        openSearch(app, "active pass")
        let fitted = app.scrollViews.firstMatch.staticTexts.matching(NSPredicate(
            format: "label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK' OR label == 'Slack'"
        )).firstMatch
        XCTAssert(fitted.waitForExistence(timeout: 300), "Active Pass never fitted from IWLS")
    }

    func testLiveOnlineGateFetch() throws {
        try skipUnlessLive()
        let app = launchLive("-seedGate", "-chsResetModels")
        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        let provenance = app.staticTexts["online-provenance"].firstMatch
        XCTAssert(provenance.waitForExistence(timeout: 300), "Sechelt never fetched from IWLS")
        XCTAssert(provenance.label.contains("CHS-published"))
    }
}
