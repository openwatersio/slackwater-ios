// Slackwater — GPL v3. Deterministic CHS service transitions through the
// production queue, fitter, publication, and persistence paths.
import XCTest

final class OfflineTransitionTests: ScreenshotTestCase {
    private func fixture(_ scenario: String = "terminal", _ ids: String,
                         fix: (String, String)? = nil) -> (XCUIApplication, String) {
        let token = UUID().uuidString
        var args = ["-seedGate", "-chsResetModels", "-chsFitOnly", ids,
                    "-chsFixture", token, "-chsFixtureScenario", scenario]
        if let fix { args += ["-fixLat", fix.0, "-fixLon", fix.1] }
        return (launch(args), token)
    }

    func testTideFitPersistsOffline() {
        let (app, token) = fixture("hold-first", "chs-victoria", fix: ("48.4235", "-123.3705"))
        openSearch(app, "victoria")
        let pending = app.descendants(matching: .any)["chs-pending-chs-victoria"].firstMatch
        XCTAssert(pending.waitForExistence(timeout: 10))
        releaseFixture(token, "chs-victoria-first-chunk")
        XCTAssert(pending.waitForNonExistence(timeout: 30), "fixture tide fit never landed")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)

        app.terminate()
        app.launchArguments = testArguments(["-seedGate", "-nowOffsetDays", "1"])
        app.launch()
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)
    }

    func testValidatedGateGoesStraightToFinal() {
        let (app, _) = fixture("terminal", "chs-active-pass", fix: ("48.4235", "-123.3705"))
        openSearch(app, "active pass")
        let fitted = app.scrollViews.firstMatch.staticTexts.matching(NSPredicate(
            format: "label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK' OR label == 'Slack'"
        )).firstMatch
        XCTAssert(fitted.waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Refining'")).firstMatch.exists)
        pickSearchResult(app, app.staticTexts["Active Pass"].firstMatch)
        assertCurrentDetailRendered(app)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'can be off by up to'"
        )).firstMatch.exists)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)
    }

    func testProvisionalGateRefinesInOpenDetail() {
        let (app, token) = fixture("provisional-final", "chs-dodd-narrows",
                                   fix: ("49.1344", "-123.8171"))
        openSearch(app, "dodd")
        let badge = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Refining'")).firstMatch
        XCTAssert(badge.waitForExistence(timeout: 30))
        XCTAssert(badge.label.contains("±35 min"))
        let tildeReading = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '~'")).firstMatch
        let tildeCurve = app.descendants(matching: .any).matching(
            NSPredicate(format: "value CONTAINS '~'")).firstMatch
        XCTAssert(tildeReading.exists || tildeCurve.exists)
        pickSearchResult(app, app.staticTexts["Dodd Narrows"].firstMatch)
        let warning = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'slack at Dodd Narrows can be off by up to ~35 min'"
        )).firstMatch
        XCTAssert(warning.waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'Stay connected'"
        )).firstMatch.exists)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS '60 of 210 days downloaded'"
        )).firstMatch.exists)
        releaseFixture(token, "after-provisional")
        XCTAssert(warning.waitForNonExistence(timeout: 30))
        assertCurrentDetailRendered(app)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Refining'")).firstMatch.exists)

        app.terminate()
        app.launchArguments = testArguments(["-seedGate", "-nowOffsetDays", "1"])
        app.launch()
        openSearch(app, "dodd")
        pickSearchResult(app, app.staticTexts["Dodd Narrows"].firstMatch)
        assertCurrentDetailRendered(app)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)
    }

    func testPromotionYieldsAndThenResumesDownload() {
        let (app, token) = fixture("yield-resume", "chs-dodd-narrows,chs-tofino",
                                   fix: ("49.1344", "-123.8171"))
        app.buttons["offline-status"].firstMatch.tap()
        let dodd = app.descendants(matching: .any)["download-row-chs-dodd-narrows"].firstMatch
        XCTAssert(dodd.waitForExistence(timeout: 10))
        XCTAssert(dodd.label.contains("Downloading"))
        app.buttons["Done"].tap()
        openSearch(app, "tofino")
        pickSearchResult(app, app.staticTexts["Tofino"].firstMatch)
        app.buttons["detail-back"].firstMatch.tap()
        app.buttons["offline-status"].firstMatch.tap()
        let tofino = app.descendants(matching: .any)["download-row-chs-tofino"].firstMatch
        releaseFixture(token, "dodd-first-chunk")
        waitFor(tofino, "label CONTAINS 'Downloading'", timeout: 10)
        XCTAssert(tofino.label.contains("Downloading"))
        XCTAssert(dodd.label.contains("Waiting"))
        releaseFixture(token, "tofino-first-chunk")
        waitFor(dodd, "label CONTAINS 'Downloading'", timeout: 20)
        XCTAssert(dodd.label.contains("Downloading"))
        releaseFixture(token, "dodd-resumed")
        waitFor(dodd, "label CONTAINS 'Available offline'", timeout: 30)
        XCTAssert(dodd.label.contains("Available offline"))
    }

    func testDownloadsManagerOrdersAndPromotesRealQueue() {
        let (app, _) = fixture("hold-first", "chs-victoria,chs-race-passage,chs-porlier-pass,chs-weynton-passage",
                               fix: ("48.4235", "-123.3705"))
        let indicator = app.buttons["offline-status"].firstMatch
        XCTAssert(indicator.waitForExistence(timeout: 5))
        waitFor(indicator, "value BEGINSWITH 'Downloading'", timeout: 10)
        let gear = app.buttons["Settings"].firstMatch
        XCTAssert(indicator.frame.maxX <= gear.frame.minX + 1)
        XCTAssertEqual(indicator.frame.midY, gear.frame.midY, accuracy: 2)
        indicator.tap()
        let rows = app.descendants(matching: .any)
        let victoria = rows["download-row-chs-victoria"].firstMatch
        let race = rows["download-row-chs-race-passage"].firstMatch
        let porlier = rows["download-row-chs-porlier-pass"].firstMatch
        XCTAssert(victoria.waitForExistence(timeout: 5))
        let ordered = settled { [victoria.frame, race.frame, porlier.frame] }
        XCTAssert(ordered[0].minY < ordered[1].minY && ordered[1].minY < ordered[2].minY)
        XCTAssertFalse(rows["download-row-chs-sooke"].firstMatch.exists)
        app.buttons["Done"].tap()
        openSearch(app, "weynton")
        pickSearchResult(app, app.staticTexts["Weynton Passage"].firstMatch)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'first in line'"
        )).firstMatch.waitForExistence(timeout: 5))
        app.buttons["detail-back"].firstMatch.tap()
        app.buttons["offline-status"].firstMatch.tap()
        let promoted = rows["download-row-chs-weynton-passage"].firstMatch
        XCTAssert(promoted.waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["YOU OPENED"].firstMatch.exists)
        let promotedOrder = settled { [promoted.frame, porlier.frame] }
        XCTAssert(promotedOrder[0].minY < promotedOrder[1].minY)
    }

    func testOnDemandStationFillsOpenDetail() {
        let (app, token) = fixture("hold-first", "chs-halifax")
        openSearch(app, "halifax")
        pickSearchResult(app, app.descendants(matching: .any)["chs-pending-chs-halifax"].firstMatch)
        XCTAssert(app.staticTexts["Downloading…"].waitForExistence(timeout: 10))
        releaseFixture(token, "chs-halifax-first-chunk")
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 30))
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)
    }

    func testSeededFinalCurrentModelRendersOffline() {
        let app = launch("-seedGate", "-seedCurrentModel", "chs-dodd-narrows")
        openSearch(app, "dodd")
        pickSearchResult(app, app.staticTexts["Dodd Narrows"].firstMatch)
        assertCurrentDetailRendered(app)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Refining'")).firstMatch.exists)
    }

    func testSeededProvisionalModelAppearsInManager() {
        let app = launch("-seedGate", "-seedCurrentModel", "chs-dodd-narrows",
                         "-seedCurrentProvisional", "-fixLat", "49.1344", "-fixLon", "-123.8171")
        app.buttons["offline-status"].firstMatch.tap()
        let row = app.descendants(matching: .any)["download-row-chs-dodd-narrows"].firstMatch
        XCTAssert(row.waitForExistence(timeout: 10))
        XCTAssert(row.label.contains("Refining"))
        XCTAssert(row.label.contains("FAST ANSWER ±35 MIN"))
    }
}
