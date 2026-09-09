// Slackwater — GPL v3. Explicit, serial IWLS compatibility smoke checks.
import XCTest

final class LiveFetchTests: ScreenshotTestCase {
    func testLiveTideFit() throws {
        try skipUnlessLive()
        let app = launchLive("-seedGate", "-chsResetModels", "-chsFitOnly", "chs-victoria")
        openSearch(app, "victoria")
        let pending = app.descendants(matching: .any)["chs-pending-chs-victoria"].firstMatch
        XCTAssert(pending.appears(within: 15))
        XCTAssert(pending.disappears(within: 300), "Victoria never fitted — IWLS unreachable?")
    }

    func testLiveCurrentFit() throws {
        try skipUnlessLive()
        let app = launchLive("-seedGate", "-chsResetModels", "-chsFitOnly", "chs-active-pass")
        openSearch(app, "active pass")
        let fitted = app.scrollViews.firstMatch.staticTexts.matching(NSPredicate(
            format: "label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK' OR label == 'Slack'"
        )).firstMatch
        XCTAssert(fitted.appears(within: 300), "Active Pass never fitted — IWLS unreachable?")
    }

    /// Sechelt Rapids is a fit-reject gate (ChsCurrentGate.swift): the app
    /// fetches CHS's published predictions instead of fitting. A timeout here
    /// means IWLS stopped resolving or serving wcsp1/wcdp1 for it, and Sechelt
    /// may need dropping from the online set — a human call.
    func testLiveOnlineGateFetch() throws {
        try skipUnlessLive()
        let app = launchLive("-seedGate", "-chsResetModels")
        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        let provenance = app.staticTexts["online-provenance"].firstMatch
        XCTAssert(provenance.appears(within: 300),
                  "Sechelt never fetched — check whether IWLS resolves/serves this gate")
        XCTAssert(app.otherElements["timeline-strip"].appears(within: 5),
                  "the live fetch did not render the strip")
        XCTAssert(provenance.label.contains("CHS-published"),
                  "the fetched footer must say CHS-published — never claim an on-device computation")
        XCTAssert(provenance.label.range(of: "covers to [A-Z][a-z]{2} \\d{1,2}",
                                          options: .regularExpression) != nil,
                  "provenance must carry a real covers-to date, not a placeholder")
    }
}
