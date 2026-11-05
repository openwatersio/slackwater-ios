// Slackwater — GPL v3. The Printable tables row at the end of the schedule card, and its sheet (docs/detail.md §8.6).
import XCTest

final class PrintableTablesUITests: ScreenshotTestCase {
    private func row(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["printable-tables-row"].firstMatch
    }

    private func openSheet(_ app: XCUIApplication) {
        let row = row(app)
        XCTAssert(row.appears(within: 10), "no Printable tables row on the detail")
        scrollTo(row, in: app)
        row.tap()
    }

    /// The share button is enabled once the page for the switch's position is built.
    private func waitForPage(_ app: XCUIApplication) -> XCUIElement {
        let share = app.buttons["printable-share"].firstMatch
        XCTAssert(share.appears(within: 10), "the printable sheet has no share button")
        XCTAssert(waitFor(share, "isEnabled == true", timeout: 30), "the page was never built")
        return share
    }

    /// A share-sheet action, wherever iOS puts it (a cell in the action list or a button).
    private func shareAction(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
                        label, XCUIElement.ElementType.cell.rawValue,
                        XCUIElement.ElementType.button.rawValue)).firstMatch
    }

    func testAFreeUserGetsTheSupportSheet() {
        let app = launch("-locDenied")
        openFridayHarbor(app)
        openSheet(app)
        XCTAssert(app.navigationBars["Support Slackwater"].appears(within: 5))
        XCTAssertFalse(app.buttons["printable-share"].exists)
    }

    func testPremiumOpensTheWeekAndMonthAndOffersPrintAndSave() {
        let app = launch("-locDenied", "-seedPremium")
        openFridayHarbor(app)
        openSheet(app)
        _ = waitForPage(app)
        XCTAssert(app.descendants(matching: .any)["printable-preview"].appears(within: 5),
                  "the week has no preview")
        save(app, "printable-week.png")

        app.segmentedControls["printable-span"].buttons["Month"].tap()
        let share = waitForPage(app)
        XCTAssert(app.descendants(matching: .any)["printable-preview"].appears(within: 5),
                  "the month has no preview")
        // A bundled tide predicts any month, so there is nothing to say about coverage.
        XCTAssertFalse(app.staticTexts["printable-coverage"].exists)
        save(app, "printable-month.png")

        share.tap()
        XCTAssert(shareAction(app, "Print").appears(within: 10), "the share sheet offers no Print")
        XCTAssert(shareAction(app, "Save to Files").appears(within: 5),
                  "the share sheet offers no Save to Files")
        save(app, "printable-share.png")
    }

    /// The header's share button is unchanged: it still sends the link, which
    /// iOS offers to copy and has nothing to print.
    func testTheDetailShareButtonStillSendsTheLink() {
        let app = launch("-locDenied", "-seedPremium")
        openFridayHarbor(app)
        let share = app.buttons["detail-share"].firstMatch
        XCTAssert(share.appears(within: 5), "no share button on the tide detail")
        share.tap()
        XCTAssert(shareAction(app, "Copy").appears(within: 10), "the header share sheet did not open")
        XCTAssertFalse(shareAction(app, "Print").exists, "the header share sheet offers Print")
        XCTAssertFalse(app.buttons["printable-share"].exists)
    }

    /// Every constituent-backed detail kind closes its schedule card on the row.
    func testTheRowClosesTheCurrentAndDerivedGateSchedules() {
        let app = launch("-locDenied", "-networkKillSwitch", "-seedTideModel", "chs-point-atkinson")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        XCTAssert(row(app).appears(within: 10), "no Printable tables row on the current detail")
        goBack(app)

        openSearch(app, "malibu")
        pickSearchResult(app, app.staticTexts["Malibu Rapids"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 10))
        XCTAssert(row(app).appears(within: 10), "no Printable tables row on the derived-gate detail")
    }

    /// An online gate prints only what is stored, and a month longer than the
    /// stored block says how far it goes and where to get more.
    func testAnOnlineGateMonthSaysWhatIsCovered() {
        let app = launch("-locDenied", "-seedPremium", "-networkKillSwitch", "-chsResetModels",
                         "-seedOnlineWindow", "chs-sechelt-rapids")
        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        XCTAssert(app.otherElements["timeline-strip"].appears(within: 5))
        openSheet(app)
        _ = waitForPage(app)
        XCTAssertFalse(app.staticTexts["printable-coverage"].exists,
                       "the stored block covers the week, so the week needs no note")

        app.segmentedControls["printable-span"].buttons["Month"].tap()
        _ = waitForPage(app)
        let note = app.staticTexts["printable-coverage"].firstMatch
        XCTAssert(note.appears(within: 5), "a month past the stored block has no coverage note")
        XCTAssert(note.label.hasPrefix("Predictions available"), "note read: \(note.label)")
        XCTAssert(app.staticTexts["To print more days, close this and download more below the schedule."]
            .appears(within: 5), "the online gate's note does not say where to download more")
        save(app, "printable-online-month.png")
    }

    /// No stored block, no schedule card, and so no row.
    func testAnOnlineGateWithNothingStoredHasNoRow() {
        let app = launch("-locDenied", "-seedPremium", "-networkKillSwitch", "-chsResetModels")
        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        XCTAssert(app.descendants(matching: .any)["online-honesty-card"].firstMatch.appears(within: 10))
        XCTAssertFalse(row(app).exists, "a gate with nothing stored shows the Printable tables row")
    }
}
