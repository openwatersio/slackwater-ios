// Slackwater — GPL v3. The widget deep link's RECEIVING half (#167).
// DeepLinkTests proves the URL a widget emits round-trips through
// `url.pathComponents`; nothing proved the app ACTS on it. The handler sits on
// a view (`StationListView`), not on the scene, and on a first run it races
// that view's own tour push — which is why the first run gets its own case
// here.
//
// Scope is the receiving half on purpose: driving a real home-screen widget
// means automating the widget gallery, and the emit side is already covered by
// DeepLinkTests. `system.open` delivers the same URL `.widgetURL` does.
import XCTest

final class DeepLinkUITests: ScreenshotTestCase {
    /// "noaa/9449880" percent-encoded exactly as `deepLink(forStationID:)`
    /// encodes it — the "/"-bearing shape, which is every id but CHS.
    private let fridayHarbor = URL(string: "slackwater://station/noaa%2F9449880")!
    private let seattle = URL(string: "slackwater://station/noaa%2F9447130")!
    private let removedStation = URL(string: "slackwater://station/chs-north-galiano")!

    /// `system.open` routes through SpringBoard, which asks before handing a
    /// custom scheme to an app. Tap through it so the test measures the app and
    /// not the confirmation. `if` rather than an assert: the prompt is a
    /// SpringBoard policy, not ours, and it is not shown on every runtime.
    private func openDeepLink(_ url: URL) {
        XCUIDevice.shared.system.open(url)
        let confirm = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .buttons["Open"].firstMatch
        if confirm.appears(within: 5) { confirm.tap() }
    }

    /// A cold launch: the app has to be gone, or the URL arrives at an already
    /// built view hierarchy and proves nothing about scene setup.
    private func primeThenTerminate(_ args: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = testArguments(args)
        app.launch()
        XCTAssert(stationList(app).appears(within: 10),
                  "app did not finish launching before the deep link")
        app.terminate()
        return app
    }

    private func assertStationDetail(_ app: XCUIApplication, _ message: String) {
        XCTAssert(eventually(within: 20) { app.state == .runningForeground },
                  "the deep link did not launch the app")
        XCTAssert(app.buttons["detail-back"].firstMatch.appears(within: 20), message)
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.appears(within: 5),
                  "\(message) — landed on a detail, but not this station's")
    }

    /// The reported case: a returning user taps a home widget.
    func testDeepLinkColdOpensTheStationDetail() {
        let app = primeThenTerminate()
        openDeepLink(fridayHarbor)
        assertStationDetail(app, "widget deep link opened the list, not the station detail")
    }

    /// A first run cold-launched by a link: the list's first appear pushes
    /// the tour station, and SwiftUI does not order that against the link.
    /// The prime launch begins the tour on Friday Harbor and is killed before
    /// it finishes, so the cold launch arms it again. Whichever lands second,
    /// the user ends on the linked station, with the tour there.
    func testFirstRunDeepLinkWinsOverTheTourStation() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-resetTour", "-locDenied"])
            .filter { $0 != "-seedTour" }
        app.launch()
        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15),
                  "the prime launch did not begin the tour")
        app.terminate()

        openDeepLink(seattle)
        XCTAssert(eventually(within: 20) { app.state == .runningForeground },
                  "the deep link did not launch the app")
        XCTAssert(app.staticTexts["Seattle"].firstMatch.appears(within: 20),
                  "the tour station replaced the linked one")
        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15),
                  "the tour did not follow the link to its station")
    }

    func testDeepLinkToRemovedStationShowsItsExplanation() {
        let app = primeThenTerminate("-resetFavorites", "-resetRecents")
        openDeepLink(removedStation)

        XCTAssert(eventually(within: 20) { app.state == .runningForeground },
                  "the deep link did not launch the app")
        XCTAssert(app.descendants(matching: .any)["removed-station-card"].firstMatch
            .appears(within: 10), "the removed station deep link opened an unexplained list")
        XCTAssert(app.staticTexts["North Galiano"].firstMatch.exists,
                  "the removed station explanation did not use its tombstone")
    }

    func testDeepLinkToRemovedStationClosesSearch() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-resetFavorites", "-resetRecents"])
        app.launch()
        openSearch(app, "Friday")

        openDeepLink(removedStation)

        XCTAssert(app.textFields.firstMatch.disappears(within: 10),
                  "search stayed over the removed station explanation")
        XCTAssert(app.descendants(matching: .any)["removed-station-card"].firstMatch
            .appears(within: 10), "the warm deep link did not reveal the removed station")
    }
}
