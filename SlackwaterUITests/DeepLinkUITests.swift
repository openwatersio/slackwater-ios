// Slackwater — GPL v3. The widget deep link's RECEIVING half (#167).
// DeepLinkTests proves the URL a widget emits round-trips through
// `url.pathComponents`; nothing proved the app ACTS on it. The handler sits on
// a view (`StationListView`), not on the scene, so whether it fires at all
// depends on what is on screen when the URL lands — which is why the first-run
// gate gets its own case here.
//
// Scope is the receiving half on purpose: driving a real home-screen widget
// means automating the widget gallery, and the emit side is already covered by
// DeepLinkTests. `system.open` delivers the same URL `.widgetURL` does.
import XCTest

final class DeepLinkUITests: XCTestCase {
    /// "noaa/9449880" percent-encoded exactly as `deepLink(forStationID:)`
    /// encodes it — the "/"-bearing shape, which is every id but CHS.
    private let fridayHarbor = URL(string: "slackwater://station/noaa%2F9449880")!

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
        app.launchArguments = args + ["-noCloudSync", "-currentFillOff"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 10),
                  "app did not finish launching before the deep link")
        app.terminate()
        return app
    }

    private func assertStationDetail(_ app: XCUIApplication, _ message: String) {
        XCTAssert(app.wait(for: .runningForeground, timeout: 20),
                  "the deep link did not launch the app")
        XCTAssert(app.buttons["detail-back"].firstMatch.appears(within: 20), message)
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.appears(within: 5),
                  "\(message) — landed on a detail, but not this station's")
    }

    /// The reported case: a user past the first-run gate taps a home widget.
    func testDeepLinkColdOpensTheStationDetail() {
        let app = primeThenTerminate("-seedGate")
        openDeepLink(fridayHarbor)
        assertStationDetail(app, "widget deep link opened the list, not the station detail")
    }

    /// A widget can be added from the gallery before the app is ever opened, so
    /// the URL can arrive while `RootView` is still showing `GateView` — and
    /// `.onOpenURL` lives inside `StationListView`, which does not exist yet.
    func testDeepLinkColdOpensTheStationDetailBeforeTheGateIsAnswered() {
        let app = primeThenTerminate("-resetGate")
        openDeepLink(fridayHarbor)
        assertStationDetail(app, "deep link was dropped on the first-run gate")
    }
}
