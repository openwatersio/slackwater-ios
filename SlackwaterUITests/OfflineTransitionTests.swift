// Slackwater — GPL v3. Deterministic CHS service transitions through the
// production queue, fitter, publication, and persistence paths.
import XCTest

final class OfflineTransitionTests: ScreenshotTestCase {
    func testTidePreviewStaysUsableOfflineThenFinishesInOpenDetail() {
        let (app, token) = fixture("tide-preview-final", "chs-victoria", fix: ("48.4235", "-123.3705"))
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(app.staticTexts["Downloading…"].appears(within: 10))
        save(app, "tide-waiting.png")
        releaseFixture(token, "chs-victoria-first-chunk")
        let preview = app.descendants(matching: .any)["chs-download-notice"].firstMatch
        XCTAssert(preview.appears(within: 10))
        XCTAssert(app.progressIndicators["chs-download-notice"].firstMatch.exists)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        let strip = app.descendants(matching: .any)["timeline-strip"].firstMatch
        let moon = app.descendants(matching: .any)["tile-moon"].firstMatch
        XCTAssertGreaterThanOrEqual(preview.frame.minY, strip.frame.maxY)
        XCTAssertLessThanOrEqual(preview.frame.maxY, moon.frame.minY)
        XCTAssertEqual(preview.frame.midX, strip.frame.midX, accuracy: 1)
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)
        save(app, "tide-preview.png")

        app.terminate()
        app.launchArguments = testArguments(["-seedGate", "-nowOffsetDays", "1"])
        app.launch()
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(preview.appears(within: 5))
        XCTAssert(app.staticTexts["More data will download when you reconnect"].exists)
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)

        app.terminate()
        app.launchArguments = testArguments(["-seedGate", "-chsFitOnly", "chs-victoria", "-chsFixture", UUID().uuidString,
                                            "-chsFixtureScenario", "tide-preview-fail"])
        app.launch()
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(preview.appears(within: 5))
        XCTAssert(app.staticTexts["Additional download failed. Your downloaded predictions remain available."].appears(within: 10))
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)

        app.terminate()
        let resumeToken = UUID().uuidString
        app.launchArguments = testArguments(["-seedGate", "-chsFitOnly", "chs-victoria", "-chsFixture", resumeToken,
                                            "-chsFixtureScenario", "hold-first"])
        app.launch()
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(preview.appears(within: 5))
        scrubStrip(app)
        settleScrub(app)
        let selectedTime = leadReading(app).value as? String
        releaseFixture(resumeToken, "chs-victoria-first-chunk")
        XCTAssert(preview.disappears(within: 30))
        XCTAssertEqual(leadReading(app).value as? String, selectedTime)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.exists)
        save(app, "tide-full-model.png")
    }

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
        XCTAssert(pending.appears(within: 10))
        XCTAssert(app.progressIndicators["chs-pending-chs-victoria"].firstMatch.exists)
        releaseFixture(token, "chs-victoria-first-chunk")
        XCTAssert(pending.disappears(within: 30), "fixture tide fit never landed")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)

        app.terminate()
        app.launchArguments = testArguments(["-seedGate", "-nowOffsetDays", "1"])
        app.launch()
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)
    }

    func testValidatedGateGoesStraightToFinal() {
        // Fixed AT the gate (its own coordinates, DownloadTier.swift): the
        // `.inView` tier only auto-downloads the stations the list renders,
        // and putting the fix here makes Active Pass the nearest station —
        // the hero card — so it lands in that cohort with no tap required.
        let (app, _) = fixture("terminal", "chs-active-pass", fix: ("48.8604", "-123.3128"))
        openSearch(app, "active pass")
        let fitted = app.scrollViews.firstMatch.staticTexts.matching(NSPredicate(
            format: "label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK' OR label == 'Slack'"
        )).firstMatch
        XCTAssert(fitted.appears(within: 30))
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

    func testCurrentDownloadStaysUsableAndFinishesInOpenDetail() {
        let (app, token) = fixture("provisional-final", "chs-dodd-narrows",
                                   fix: ("49.1344", "-123.8171"))
        openSearch(app, "dodd")
        let reading = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '~'")).firstMatch
        XCTAssert(reading.appears(within: 30))
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Downloading'")).firstMatch.exists)
        save(app, "current-download.png")
        let tildeReading = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '~'")).firstMatch
        let tildeCurve = app.descendants(matching: .any).matching(
            NSPredicate(format: "value CONTAINS '~'")).firstMatch
        XCTAssert(tildeReading.exists || tildeCurve.exists)
        pickSearchResult(app, app.staticTexts["Dodd Narrows"].firstMatch)
        let warning = app.staticTexts.matching(NSPredicate(
            format: "label == 'Slack at Dodd Narrows can be off by 35 min.'"
        )).firstMatch
        XCTAssert(warning.appears(within: 5))
        XCTAssert(app.staticTexts["Additional data is required to improve accuracy"].exists)
        let strip = app.descendants(matching: .any)["timeline-strip"].firstMatch
        let moon = app.descendants(matching: .any)["tile-moon"].firstMatch
        let notice = app.descendants(matching: .any)["chs-download-notice"].firstMatch
        let progress = app.progressIndicators["chs-download-notice"].firstMatch
        XCTAssert(progress.exists)
        XCTAssertGreaterThanOrEqual(notice.frame.minY, strip.frame.maxY)
        XCTAssertLessThanOrEqual(notice.frame.maxY, moon.frame.minY)
        XCTAssertEqual(notice.frame.midX, strip.frame.midX, accuracy: 1)
        save(app, "current-detail.png")
        releaseFixture(token, "after-provisional")
        XCTAssert(warning.disappears(within: 30))
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

    func testPromotionReordersQueueWithoutInterruptingDownload() {
        let (app, token) = fixture("no-interrupt", "chs-dodd-narrows,chs-tofino",
                                   fix: ("49.1344", "-123.8171"))
        openDownloads(app)
        let dodd = app.descendants(matching: .any)["download-row-chs-dodd-narrows"].firstMatch
        // The status in the predicate, not read off the row once it appears:
        // the row can exist a frame before its label says Downloading (#341).
        XCTAssert(waitFor(dodd, "label CONTAINS 'Downloading'"),
                  "Dodd Narrows never showed as downloading: \(dodd.label)")
        app.buttons["Done"].tap()
        openSearch(app, "tofino")
        pickSearchResult(app, app.staticTexts["Tofino"].firstMatch)
        goBack(app)
        openDownloads(app)
        let tofino = app.descendants(matching: .any)["download-row-chs-tofino"].firstMatch
        releaseFixture(token, "dodd-first-chunk")
        XCTAssert(waitFor(dodd, "label CONTAINS 'Available offline'", timeout: 30),
                  "Dodd did not become available offline: \(dodd.label)")
        XCTAssert(tofino.label.contains("Downloading"))
        releaseFixture(token, "tofino-first-chunk")
        XCTAssert(waitFor(tofino, "label CONTAINS 'Available offline'", timeout: 30),
                  "Tofino did not become available offline")
    }

    func testDownloadsManagerOrdersAndPromotesRealQueue() {
        let (app, _) = fixture("hold-first", "chs-victoria,chs-race-passage,chs-porlier-pass,chs-weynton-passage",
                               fix: ("48.4235", "-123.3705"))
        let indicator = app.buttons["offline-status"].firstMatch
        scrollTo(indicator, in: app)
        XCTAssert(indicator.appears(within: 5))
        waitFor(indicator, "value BEGINSWITH 'Downloading'", timeout: 10)
        let gear = app.buttons["Settings"].firstMatch
        XCTAssert(indicator.frame.maxY <= gear.frame.minY + 1)
        openDownloads(app)
        // Race Passage (18 km) and Porlier Pass (68 km) sit outside the
        // `.inView` cohort, so they only join the queue once the widest tier
        // is accepted (DownloadTier.swift) — this test is about queue order
        // and promotion, not tier gating, so pull the whole fixture set in.
        let everything = app.descendants(matching: .any)["download-tier-everything-toggle"].firstMatch
        XCTAssert(everything.appears(within: 5))
        everything.tap()
        // The widest tier has been accepted when the card stops offering it.
        // Asserted here rather than left to the row waits below, so a tap that
        // does not land fails as itself instead of as four missing stations —
        // which is how the Toggle this replaced hid a real bug (#462).
        XCTAssert(app.descendants(matching: .any)["download-tier-everything-on"]
            .firstMatch.appears(within: 5), "the widest tier never took")
        let rows = app.descendants(matching: .any)
        let victoria = rows["download-row-chs-victoria"].firstMatch
        let race = rows["download-row-chs-race-passage"].firstMatch
        let porlier = rows["download-row-chs-porlier-pass"].firstMatch
        XCTAssert(victoria.appears(within: 5))
        XCTAssert(race.appears(within: 5))
        XCTAssert(porlier.appears(within: 5))
        let ordered = settled { [victoria.frame, race.frame, porlier.frame] }
        XCTAssert(ordered[0].minY < ordered[1].minY && ordered[1].minY < ordered[2].minY)
        // `.everything` still stops at ChsFitService.autoFitRadiusKm (150 km):
        // Weynton Passage at 347 km stays out of the queue until it is opened
        // by hand below, which pins that ceiling.
        XCTAssertFalse(rows["download-row-chs-weynton-passage"].firstMatch.exists)
        XCTAssertFalse(rows["download-row-chs-sooke"].firstMatch.exists)
        app.buttons["Done"].tap()
        openSearch(app, "weynton")
        pickSearchResult(app, app.staticTexts["Weynton Passage"].firstMatch)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'first in line'"
        )).firstMatch.appears(within: 5))
        goBack(app)
        openDownloads(app)
        let promoted = rows["download-row-chs-weynton-passage"].firstMatch
        XCTAssert(promoted.appears(within: 5))
        XCTAssert(app.staticTexts["You opened"].firstMatch.exists)
        let promotedOrder = settled { [promoted.frame, porlier.frame] }
        XCTAssert(promotedOrder[0].minY < promotedOrder[1].minY)
    }

    func testOnDemandStationFillsOpenDetail() {
        let (app, token) = fixture("hold-first", "chs-halifax")
        openSearch(app, "halifax")
        pickSearchResult(app, app.descendants(matching: .any)["chs-pending-chs-halifax"].firstMatch)
        XCTAssert(app.staticTexts["Downloading…"].appears(within: 10))
        XCTAssert(app.progressIndicators["chs-waiting-warning"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'requests downloaded'"
        )).firstMatch.exists)
        releaseFixture(token, "chs-halifax-first-chunk")
        XCTAssert(app.staticTexts["Today"].appears(within: 30))
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
        openDownloads(app)
        let row = app.descendants(matching: .any)["download-row-chs-dodd-narrows"].firstMatch
        XCTAssert(row.appears(within: 10))
        XCTAssert(row.label.contains("Waiting for signal"))
        XCTAssertFalse(row.label.contains("Fast answer"))
    }
}
