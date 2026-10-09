// Slackwater — GPL v3. The watch's App Store set: four frames on the largest
// watch App Store Connect takes (Ultra, 422×514), which it scales for the
// rest. Gated on SLACKWATER_SHOTS and driven by scripts/screenshots.sh, like
// the phone's AppStoreScreenshots, and pinned the same way: the phone walk's
// clock (09:41 Pacific on the 2026-09-26 full moon) and fix, so the two sets
// show the same water at the same moment. The corner clock is the host's —
// watchOS simulators take no status-bar override.
import XCTest

@MainActor final class WatchAppStoreScreenshots: XCTestCase {
    private let shotDir = ProcessInfo.processInfo.environment["M1_SHOT_DIR"] ?? "/tmp"

    override func setUp() {
        continueAfterFailure = false
    }

    func testWatchAppStoreShots() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SLACKWATER_SHOTS"] == nil,
                      "generator — run scripts/screenshots.sh")
        let app = XCUIApplication()
        // Friday Harbor's fix, as on the phone. It is near enough to Canada
        // to queue CHS downloads, which the kill switch would leave as a
        // Downloads card on top of the list; `-chsFitOnly none` queues none.
        app.launchArguments = ["-resetRecents", "-noCloudSync", "-networkKillSwitch",
                               "-chsResetModels", "-chsFitOnly", "none",
                               "-resetFavorites",
                               "-nowEpoch", "1790440860",
                               "-fixLat", "48.545", "-fixLon", "-123.013"]
        app.launch()

        let rows = app.buttons.matching(identifier: "place-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        settle(app)
        save("01-list.png")

        // The first row is the place the wearer is at.
        open(app, rows.firstMatch)
        save("02-tide.png")

        // The crown parks the strip hours off now; the title turns into the
        // scrubbed time and the X appears.
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.4)
        XCTAssertTrue(app.buttons["return-to-now"].firstMatch.waitForExistence(timeout: 5),
                      app.debugDescription)
        settle(app)
        save("03-crown.png")
        app.buttons["return-to-now"].firstMatch.tap()
        let list = app.buttons["back-to-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        list.tap()

        // The second row is the current beside it, Point George.
        open(app, rows.element(boundBy: 1))
        save("04-current.png")
    }

    /// Taps until the detail is up — a list tap right after launch is
    /// sometimes dropped on the watch simulator (WatchUITests.tap).
    private func open(_ app: XCUIApplication, _ row: XCUIElement) {
        let card = app.buttons["reading-card"]
        for _ in 0..<3 where !card.exists {
            row.tap()
            _ = card.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(card.waitForExistence(timeout: 10), app.debugDescription)
        settle(app)
    }

    /// Rows and the strip draw their readings after they appear.
    private func settle(_ app: XCUIApplication) {
        sleep(2)
    }

    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: shotDir + "/" + name))
    }
}
