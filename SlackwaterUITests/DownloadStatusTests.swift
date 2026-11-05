import UIKit
import XCTest

final class DownloadStatusTests: ScreenshotTestCase {
    func testOfflineDownloadStatusHasNoUpdateAction() {
        checkDownloadStatus(online: false)
    }

    func testOnlineDownloadStatusOffersTheSameUpdateActionInBothPlaces() {
        checkDownloadStatus(online: true)
    }

    /// A fresh month reads as a date in the station's own card, and Downloads
    /// says up front that the data is free.
    func testAFreshDownloadNamesTheDateItLastsUntil() {
        let app = launch(["-chsResetModels", "-networkKillSwitch", "-connectivityOnline",
                          "-seedOnlineMonth", "chs-sechelt-rapids",
                          "-fixLat", "48.4235", "-fixLon", "-123.3705"])
        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        let card = app.descendants(matching: .any)["download-status-chs-sechelt-rapids"].firstMatch
        XCTAssert(card.appears(within: 5))
        scrollTo(card, in: app)
        XCTAssert(card.staticTexts["Offline available"].exists)
        let reach = card.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Through '")).firstMatch
        XCTAssert(reach.exists, "a fresh download names its last date")
        XCTAssert(card.buttons["download-update-chs-sechelt-rapids"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'more days'")).firstMatch.exists)
        app.swipeUp(velocity: .slow)
        save(app, "download-detail-fresh.png")
        goBack(app)
        openDownloads(app)
        XCTAssert(app.staticTexts["Station data is always free."].appears(within: 5))
        save(app, "download-manager-top.png")
    }

    func testChangingDatesDuringAnUpdateLoadsTheSelectedWeek() {
        let token = UUID().uuidString
        let app = launch(["-chsResetModels", "-networkKillSwitch",
                          "-seedOnlineWindow", "chs-sechelt-rapids",
                          "-chsFixture", token, "-chsFixtureScenario", "hold-first",
                          "-fixLat", "48.4235", "-fixLon", "-123.3705"])
        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        let footer = app.descendants(matching: .any)["download-status-chs-sechelt-rapids"].firstMatch
        scrollTo(footer, in: app)
        footer.buttons["download-update-chs-sechelt-rapids"].tap()
        XCTAssert(footer.progressIndicators.firstMatch.appears(within: 5))
        let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
        scrollTo(bar, in: app)
        bar.tap()
        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.appears(within: 5))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        let target = calendar.date(byAdding: .day, value: 60, to: Self.fixtureDate)!
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        formatter.timeZone = calendar.timeZone
        let day = app.collectionViews.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", formatter.string(from: target))).firstMatch
        for _ in 0..<3 {
            if day.appears(within: 1) { break }
            stepMonth(app, "Next Month")
        }
        XCTAssert(day.exists)
        tapDay(day)
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()
        XCTAssert(app.descendants(matching: .any)["online-honesty-card"].firstMatch.appears(within: 5))
        releaseFixture(token, "chs-sechelt-rapids-first-chunk")
        XCTAssert(app.otherElements["timeline-strip"].appears(within: 30),
                  "Finishing today's update must fetch the newly selected uncached week")
    }

    func testQueuedDownloadCanUpdateEarly() {
        let token = UUID().uuidString
        let app = launch(["-chsResetModels", "-resetFavorites", "-resetRecents",
                          "-seedOnlineWindow", "chs-sechelt-rapids",
                          "-chsFixture", token, "-chsFixtureScenario", "hold-first",
                          "-chsFitOnly", "chs-great-bras-dor",
                          "-fixLat", "42.3601", "-fixLon", "-71.0589"])
        openDownloads(app)
        tapDownloadChoice(app.buttons["download-all-currents"].firstMatch)
        let held = app.descendants(matching: .any)["download-row-chs-great-bras-dor"].firstMatch
        XCTAssert(held.staticTexts["Downloading…"].appears(within: 10))
        app.buttons["Done"].tap()
        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        XCUIDevice.shared.press(.home)
        app.activate()
        let footer = app.descendants(matching: .any)["download-status-chs-sechelt-rapids"].firstMatch
        scrollTo(footer, in: app)
        XCTAssert(footer.staticTexts["Queued"].appears(within: 5),
                  "Foreground resume must queue this cached station behind the held download")
        let update = footer.buttons["download-update-chs-sechelt-rapids"]
        guard update.appears(within: 5) else {
            XCTFail("A queued station must still allow an early update")
            return
        }
        let before = footer.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Through '")).firstMatch.label
        update.tap()
        XCTAssert(footer.progressIndicators.firstMatch.appears(within: 5))
        releaseFixture(token, "chs-sechelt-rapids-first-chunk")
        XCTAssert(footer.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'Through ' AND label != %@", before)).firstMatch.appears(within: 30),
                  "the update must move the date forward")
        XCTAssertFalse(footer.staticTexts["Queued"].exists,
                       "a completed manual update must leave the pending queue")
    }

    private func checkDownloadStatus(online: Bool) {
        let originalOrientation = XCUIDevice.shared.orientation
        // Landscape leaves the lazy Downloads row outside the accessibility tree.
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        defer {
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCUIDevice.shared.orientation = originalOrientation
            }
        }
        var args = ["-chsResetModels", "-networkKillSwitch",
                    "-seedOnlineWindow", "chs-sechelt-rapids",
                    "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        if online { args += ["-connectivityOnline", "-chsFixture", "download-status"] }
        let app = launch(args)
        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        let footer = app.descendants(matching: .any)["download-status-chs-sechelt-rapids"].firstMatch
        guard footer.appears(within: 5) else {
            XCTFail("The station footer must use the shared download status")
            return
        }
        scrollTo(footer, in: app)
        // The seeded copy covers only today's strip: its last day is today.
        let lastDay = NSPredicate(format: "label BEGINSWITH 'Through '")
        XCTAssert(footer.staticTexts.matching(lastDay).firstMatch.exists)
        XCTAssert(footer.staticTexts["Offline available"].exists,
                  "the download status needs its own card, apart from the disclaimer")
        XCTAssertEqual(app.images["downloader-connection"].firstMatch.value as? String,
                       online ? "Online" : "Offline")
        XCTAssertEqual(footer.buttons["download-update-chs-sechelt-rapids"].exists, online)
        XCTAssertFalse(app.buttons["Refresh"].exists)
        save(app, "download-detail-\(online ? "online" : "offline").png")
        goBack(app)
        openDownloads(app)
        let indicator = app.navigationBars["Downloads"].images["downloader-connection"].firstMatch
        XCTAssert(indicator.appears(within: 5))
        XCTAssertEqual(indicator.value as? String, online ? "Online" : "Offline")
        XCTAssert(app.staticTexts["Station data is always free."].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Waiting for signal'")).firstMatch.exists)
        let row = app.descendants(matching: .any)["download-row-chs-sechelt-rapids"].firstMatch
        scrollTo(row, in: app, within: app.scrollViews["downloads-manager"])
        let seeded = row.staticTexts.matching(lastDay).firstMatch
        XCTAssert(seeded.exists)
        let before = seeded.label
        XCTAssertEqual(row.buttons["download-update-chs-sechelt-rapids"].exists, online)
        save(app, "download-manager-\(online ? "online" : "offline").png")
        if online {
            row.buttons["download-update-chs-sechelt-rapids"].tap()
            XCTAssert(app.descendants(matching: .any)["downloads-manager"].firstMatch.exists,
                      "Updating a download must leave Downloads open")
            // Under -networkKillSwitch nothing else can land, so the fresh row sorts
            // last in the lazy list, which draws it only once scrolled to.
            let fresh = row.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH 'Through ' AND label != %@", before)).firstMatch
            let list = app.scrollViews["downloads-manager"]
            XCTAssert(eventually(within: 10) {
                if fresh.exists { return true }
                list.swipeUp(velocity: .slow)
                return false
            }, "Update now must move the download's date forward")
            scrollTo(fresh, in: app)
        }
    }
}
