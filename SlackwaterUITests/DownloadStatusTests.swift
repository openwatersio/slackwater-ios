import XCTest

final class DownloadStatusTests: ScreenshotTestCase {
    func testOfflineDownloadStatusHasNoUpdateAction() {
        checkDownloadStatus(online: false)
    }

    func testOnlineDownloadStatusOffersTheSameUpdateActionInBothPlaces() {
        checkDownloadStatus(online: true)
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
        let app = launch(["-chsResetModels",
                          "-seedOnlineWindow", "chs-sechelt-rapids",
                          "-chsFixture", token, "-chsFixtureScenario", "hold-first",
                          "-fixLat", "49.738", "-fixLon", "-123.900"])
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
        update.tap()
        XCTAssert(footer.progressIndicators.firstMatch.appears(within: 5))
        releaseFixture(token, "chs-sechelt-rapids-first-chunk")
        XCTAssert(footer.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'Available offline for'")).firstMatch.appears(within: 30))
        XCTAssertFalse(footer.staticTexts["Queued"].exists,
                       "a completed manual update must leave the pending queue")
    }

    private func checkDownloadStatus(online: Bool) {
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
        XCTAssert(footer.staticTexts["Expired"].exists)
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
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Waiting for signal'")).firstMatch.exists)
        let row = app.descendants(matching: .any)["download-row-chs-sechelt-rapids"].firstMatch
        scrollTo(row, in: app)
        XCTAssert(row.staticTexts["Expired"].exists)
        XCTAssertEqual(row.buttons["download-update-chs-sechelt-rapids"].exists, online)
        save(app, "download-manager-\(online ? "online" : "offline").png")
        if online {
            row.buttons["download-update-chs-sechelt-rapids"].tap()
            XCTAssert(app.descendants(matching: .any)["downloads-manager"].firstMatch.exists,
                      "Updating a download must leave Downloads open")
            scrollTo(row, in: app)
            XCTAssert(row.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH 'Available offline for'")).firstMatch.appears(within: 10),
                      "Update now must replace the expired download with fresh coverage")
        }
    }
}
