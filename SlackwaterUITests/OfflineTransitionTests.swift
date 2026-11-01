// Slackwater — GPL v3. Deterministic CHS service transitions through the
// production queue, fitter, publication, and persistence paths.
import UIKit
import XCTest

final class OfflineTransitionTests: ScreenshotTestCase {
    func testOpeningAnOnlineGateDuringItsBulkDownloadKeepsItSelected() {
        let (app, _) = fixture("hold-first", "chs-great-bras-dor", fix: ("42.3601", "-71.0589"))
        openDownloads(app)
        let currents = app.buttons["download-all-currents"].firstMatch
        let row = app.descendants(matching: .any)["download-row-chs-great-bras-dor"].firstMatch
        currents.tap()
        XCTAssert(row.staticTexts["Downloading…"].appears(within: 10))
        row.staticTexts["Great Bras d'Or"].tap()
        XCTAssert(app.descendants(matching: .any)["detail-title"].firstMatch.appears(within: 10))
        goBack(app)
        openDownloads(app)
        currents.tap()
        XCTAssert(waitFor(currents, "isSelected == false"))
        XCTAssert(row.staticTexts["Downloading…"].exists, "opening the gate must retain a fetch already in flight")
    }

    func testDeselectedPartialPredictionsStayUsableWithoutResumingAfterRelaunch() {
        let (app, _) = fixture("provisional-final", "chs-johnstone-strait-central", fix: ("42.3601", "-71.0589"))
        openDownloads(app)
        let currents = app.buttons["download-all-currents"].firstMatch
        let row = app.descendants(matching: .any)["download-row-chs-johnstone-strait-central"].firstMatch
        currents.tap()
        XCTAssert(row.staticTexts["Downloading…"].appears(within: 10))
        let readyPreview = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '~'"))
        app.buttons["Done"].tap()
        openSearch(app, "johnstone")
        XCTAssert(readyPreview.firstMatch.appears(within: 30), "the partial current model must be saved")
        // Search alone does not promote a download; opening its detail does.
        app.buttons["Close search"].firstMatch.tap()
        openDownloads(app)
        currents.tap()
        XCTAssert(row.disappears(within: 5))

        app.terminate()
        app.launchArguments.removeAll { $0 == "-chsResetModels" }
        app.launch()
        openDownloads(app)
        XCTAssertFalse(currents.isSelected)
        XCTAssertFalse(row.exists, "the saved partial model must not restart a deselected download")
        app.buttons["Done"].tap()
        openSearch(app, "johnstone")
        XCTAssert(readyPreview.firstMatch.appears(within: 10), "deselection must retain usable partial predictions")
        pickSearchResult(app, app.staticTexts["Johnstone Strait - Central"].firstMatch)
        assertCurrentDetailRendered(app)

        app.terminate()
        app.launch()
        openDownloads(app)
        currents.tap()
        XCTAssert(waitFor(currents, "isSelected == true"))
        currents.tap()
        XCTAssert(waitFor(currents, "isSelected == false"))
        XCTAssert(row.staticTexts["Downloading…"].exists, "a directly opened partial download stays protected after relaunch")
    }

    func testDeselectingCurrentsCancelsAnActiveDownloadAndKeepsCompletedData() {
        let (app, token) = fixture("hold-first", "chs-johnstone-strait-central", fix: ("42.3601", "-71.0589"))
        openDownloads(app)
        let currents = app.buttons["download-all-currents"].firstMatch
        let row = app.descendants(matching: .any)["download-row-chs-johnstone-strait-central"].firstMatch
        currents.tap()
        XCTAssert(row.staticTexts["Downloading…"].appears(within: 10))
        currents.tap()
        XCTAssert(waitFor(currents, "isSelected == false"))
        XCTAssert(row.disappears(within: 5), "the active deselected download must leave the queue")

        currents.tap()
        releaseFixture(token, "chs-johnstone-strait-central-first-chunk")
        let completed = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of ' AND label ENDSWITH ' ready'"))
        XCTAssert(completed.firstMatch.appears(within: 30),
                  "selecting again must restart the cancelled worker")
        // Deselecting removes the unfinished rows above the completed one.
        currents.tap()
        XCTAssert(waitFor(currents, "isSelected == false"))
        XCTAssert(row.staticTexts["Available offline"].exists, "deselection must retain completed predictions")

        app.terminate()
        app.launchArguments.removeAll { $0 == "-chsResetModels" }
        app.launch()
        openDownloads(app)
        XCTAssertFalse(currents.isSelected)
        XCTAssert(row.staticTexts["Available offline"].appears(within: 5))
    }

    func testTidePreviewStaysUsableOfflineThenFinishesInOpenDetail() {
        let (app, token) = fixture("tide-preview-final", "chs-victoria", fix: ("48.4235", "-123.3705"))
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(app.staticTexts["Downloading"].appears(within: 10))
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
        app.launchArguments = testArguments(["-nowOffsetDays", "1"])
        app.launch()
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(preview.appears(within: 5))
        XCTAssert(app.staticTexts["More data will download when you reconnect"].exists)
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)

        app.terminate()
        app.launchArguments = testArguments(["-chsFitOnly", "chs-victoria", "-chsFixture", UUID().uuidString,
                                            "-chsFixtureScenario", "tide-preview-fail"])
        app.launch()
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(preview.appears(within: 5))
        XCTAssert(app.staticTexts["Additional download failed. Your downloaded predictions remain available."].appears(within: 10))
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)

        app.terminate()
        let resumeToken = UUID().uuidString
        app.launchArguments = testArguments(["-chsFitOnly", "chs-victoria", "-chsFixture", resumeToken,
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
        var args = ["-chsResetModels", "-resetRecents", "-resetFavorites", "-chsFitOnly", ids,
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
        )).firstMatch.appears(within: 30), "final tide model never replaced the downloaded preview")

        app.terminate()
        app.launchArguments = testArguments(["-nowOffsetDays", "1"])
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
            format: "label CONTAINS 'can differ from CHS'"
        )).firstMatch.exists)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)
    }

    func testCurrentDownloadStaysUsableAndFinishesInOpenDetail() {
        let (app, token) = fixture("provisional-final", "chs-johnstone-strait-central",
                                   fix: ("50.4717", "-126.1367"))
        openSearch(app, "johnstone")
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
        pickSearchResult(app, app.staticTexts["Johnstone Strait - Central"].firstMatch)
        let warning = app.staticTexts.matching(NSPredicate(
            format: "label == %@", "Slack at Johnstone Strait - Central can differ from CHS's prediction by up to 35 min."
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
        app.launchArguments = testArguments(["-nowOffsetDays", "1"])
        app.launch()
        openSearch(app, "johnstone")
        pickSearchResult(app, app.staticTexts["Johnstone Strait - Central"].firstMatch)
        assertCurrentDetailRendered(app)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'computed on this device'"
        )).firstMatch.exists)
    }

    func testPromotionReordersQueueWithoutInterruptingDownload() {
        let (app, token) = fixture("no-interrupt", "chs-johnstone-strait-central,chs-tofino",
                                   fix: ("50.4717", "-126.1367"))
        openDownloads(app)
        let johnstone = app.descendants(matching: .any)["download-row-chs-johnstone-strait-central"].firstMatch
        // The status in the predicate, not read off the row once it appears:
        // the row can exist a frame before its label says Downloading (#341).
        XCTAssert(waitFor(johnstone, "label CONTAINS 'Downloading'"),
                  "Johnstone Strait - Central never showed as downloading: \(johnstone.label)")
        app.buttons["Done"].tap()
        openSearch(app, "tofino")
        pickSearchResult(app, app.staticTexts["Tofino"].firstMatch)
        goBack(app)
        openDownloads(app)
        let tofino = app.descendants(matching: .any)["download-row-chs-tofino"].firstMatch
        releaseFixture(token, "johnstone-first-chunk")
        XCTAssert(waitFor(johnstone, "label CONTAINS 'Available offline'", timeout: 30),
                  "Johnstone did not become available offline: \(johnstone.label)")
        // The queue starts Tofino after Johnstone finishes, not in the same frame (#663).
        XCTAssert(waitFor(tofino, "label CONTAINS 'Downloading'"),
                  "Tofino did not start downloading after Johnstone: \(tofino.label)")
        releaseFixture(token, "tofino-first-chunk")
        XCTAssert(waitFor(tofino, "label CONTAINS 'Available offline'", timeout: 30),
                  "Tofino did not become available offline")
    }

    func testDownloadsManagerOrdersAndPromotesRealQueue() {
        let (app, _) = fixture("hold-first", "chs-victoria,chs-active-pass,chs-first-narrows,chs-blackney-passage",
                               fix: ("48.4235", "-123.3705"))
        let indicator = app.buttons["offline-status"].firstMatch
        scrollTo(indicator, in: app)
        XCTAssert(indicator.appears(within: 5))
        waitFor(indicator, "value BEGINSWITH 'Downloading'", timeout: 10)
        let gear = app.buttons["Settings"].firstMatch
        XCTAssert(indicator.frame.maxY <= gear.frame.minY + 1)
        openDownloads(app)
        // Active Pass (18 km) and First Narrows (68 km) sit outside the
        // `.inView` cohort, so they only join the queue once the widest tier
        // is accepted (DownloadTier.swift) — this test is about queue order
        // and promotion, not tier gating, so pull the whole fixture set in.
        let everything = app.descendants(matching: .any)["download-tier-everything-toggle"].firstMatch
        XCTAssert(everything.appears(within: 5))
        everything.tap()
        XCTAssert(waitFor(everything, "isSelected == true"), "the widest tier never took")
        let rows = app.descendants(matching: .any)
        let victoria = rows["download-row-chs-victoria"].firstMatch
        let race = rows["download-row-chs-active-pass"].firstMatch
        let porlier = rows["download-row-chs-first-narrows"].firstMatch
        XCTAssert(victoria.appears(within: 5))
        XCTAssert(race.appears(within: 5))
        XCTAssert(porlier.appears(within: 5))
        let ordered = settled { [victoria.frame, race.frame, porlier.frame] }
        XCTAssert(ordered[0].minY < ordered[1].minY && ordered[1].minY < ordered[2].minY)
        // `.everything` still stops at ChsFitService.autoFitRadiusKm (150 km):
        // Blackney Passage at 347 km stays out of the queue until it is opened
        // by hand below, which pins that ceiling.
        XCTAssertFalse(rows["download-row-chs-blackney-passage"].firstMatch.exists)
        XCTAssertFalse(rows["download-row-chs-sooke"].firstMatch.exists)
        app.buttons["Done"].tap()
        openSearch(app, "blackney")
        pickSearchResult(app, app.staticTexts["Blackney Passage"].firstMatch)
        let next = app.staticTexts.matching(identifier: "chs-waiting-warning")
            .matching(NSPredicate(format: "label == 'Next'")).firstMatch
        XCTAssert(next.appears(within: 5))
        XCTAssertEqual(next.value as? String, "Queued — Canadian predictions download once, then work offline.")
        save(app, "waiting-detail.png")
        let nearby = app.descendants(matching: .any)["nearby"].firstMatch
        scrollTo(nearby.descendants(matching: .any)["nearby-station"].firstMatch, in: app)
        XCTAssert(nearby.appears(within: 5))
        XCTAssert(nearby.descendants(matching: .any)["nearby-station"].firstMatch.exists)
        goBack(app)
        openDownloads(app)
        let promoted = rows["download-row-chs-blackney-passage"].firstMatch
        XCTAssert(promoted.appears(within: 5))
        XCTAssert(app.staticTexts["You opened"].firstMatch.exists)
        let promotedOrder = settled { [promoted.frame, porlier.frame] }
        XCTAssert(promotedOrder[0].minY < promotedOrder[1].minY)
    }

    func testOnDemandStationFillsOpenDetail() {
        let (app, token) = fixture("hold-first", "chs-halifax")
        openSearch(app, "halifax")
        pickSearchResult(app, app.descendants(matching: .any)["chs-pending-chs-halifax"].firstMatch)
        XCTAssert(app.staticTexts["Downloading"].appears(within: 10))
        XCTAssert(app.activityIndicators["chs-waiting-warning"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["chs-waiting-expectation"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'requests downloaded'"
        )).firstMatch.exists)
        save(app, "downloading-detail.png")
        let nearby = app.descendants(matching: .any)["nearby"].firstMatch
        scrollTo(nearby.descendants(matching: .any)["nearby-station"].firstMatch, in: app)
        XCTAssert(nearby.appears(within: 5))
        XCTAssert(nearby.descendants(matching: .any)["nearby-station"].firstMatch.exists)
        app.swipeDown(velocity: .fast)
        releaseFixture(token, "chs-halifax-first-chunk")
        XCTAssert(app.staticTexts["Today"].appears(within: 30))
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty)
    }

    func testSeededFinalCurrentModelRendersOffline() {
        let app = launch("-seedCurrentModel", "chs-johnstone-strait-central")
        openSearch(app, "johnstone")
        pickSearchResult(app, app.staticTexts["Johnstone Strait - Central"].firstMatch)
        assertCurrentDetailRendered(app)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Refining'")).firstMatch.exists)
    }

    func testBoundedCurrentShowsMeasuredLimitWithoutDownloadProgress() {
        let app = launch("-seedCurrentModel", "chs-blackney-passage", "-networkKillSwitch")
        openSearch(app, "blackney")
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '~'")).firstMatch.appears(within: 10))
        save(app, "bounded-current-card.png")
        pickSearchResult(app, app.staticTexts["Blackney Passage"].firstMatch)
        assertCurrentDetailRendered(app)
        XCTAssertFalse(leadReading(app).label.contains("~"), "VoiceOver should read the bound notice instead of speaking tilde")
        let notice = app.staticTexts["chs-bound-notice"].firstMatch
        XCTAssert(notice.appears(within: 5))
        XCTAssertEqual(notice.label, "Slack at Blackney Passage can differ from CHS's prediction by up to 45 min.")
        XCTAssertFalse(app.descendants(matching: .any)["chs-download-notice"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Additional data is required to improve accuracy"].exists)
        save(app, "bounded-current-detail.png")
        goBack(app)
        if app.buttons["Close search"].firstMatch.exists { closeSearch(app) }
        openDownloads(app)
        let row = app.descendants(matching: .any)["download-row-chs-blackney-passage"].firstMatch
        scrollTo(row, in: app)
        XCTAssert(row.staticTexts["Available offline"].appears(within: 5))
        XCTAssertFalse(row.progressIndicators.firstMatch.exists)
        save(app, "bounded-current-downloaded.png")
    }

    /// The notice's last words carry the bound, so its frame must hold every line the sentence
    /// needs at its laid-out width. A shorter frame means the end was cut off.
    func testBoundNoticeWrapsAtLargeText() {
        for (name, category) in [("UICTContentSizeCategoryXXXL", UIContentSizeCategory.extraExtraExtraLarge),
                                 ("UICTContentSizeCategoryAccessibilityXXXL", .accessibilityExtraExtraExtraLarge)] {
            let app = launch(["-seedCurrentModel", "chs-blackney-passage", "-networkKillSwitch",
                              "-UIPreferredContentSizeCategoryName", name])
            openSearch(app, "blackney")
            pickSearchResult(app, app.staticTexts["Blackney Passage"].firstMatch)
            assertCurrentDetailRendered(app)
            let notice = app.staticTexts["chs-bound-notice"].firstMatch
            XCTAssert(notice.appears(within: 5))
            let font = UIFont.preferredFont(forTextStyle: .caption1,
                                            compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            let needed = (notice.label as NSString).boundingRect(
                with: CGSize(width: notice.frame.width, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil).height
            XCTAssertGreaterThan(needed, font.lineHeight * 1.5, "\(name): the sentence should need more than one line")
            XCTAssertGreaterThanOrEqual(notice.frame.height, needed - font.lineHeight / 2,
                                        "\(name): the bound notice is shorter than its text and was cut off")
            save(app, "bounded-current-\(name).png")
            app.terminate()
        }
    }

    func testSeededProvisionalModelAppearsInManager() {
        let app = launch("-seedCurrentModel", "chs-johnstone-strait-central",
                         "-seedCurrentProvisional", "-fixLat", "49.1344", "-fixLon", "-123.8171")
        openDownloads(app)
        let row = app.descendants(matching: .any)["download-row-chs-johnstone-strait-central"].firstMatch
        XCTAssert(row.appears(within: 10))
        XCTAssert(row.label.contains("Queued"))
        XCTAssertFalse(row.label.contains("Fast answer"))
    }
}
