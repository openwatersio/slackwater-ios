import XCTest

final class DownloadStatusTests: ScreenshotTestCase {
    func testOfflineDownloadStatusHasNoUpdateAction() {
        checkDownloadStatus(online: false)
    }

    func testOnlineDownloadStatusOffersTheSameUpdateActionInBothPlaces() {
        checkDownloadStatus(online: true)
    }

    private func checkDownloadStatus(online: Bool) {
        var args = ["-seedGate", "-chsResetModels", "-networkKillSwitch",
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
        }
    }
}
