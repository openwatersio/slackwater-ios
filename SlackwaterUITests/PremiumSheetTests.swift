// Slackwater — GPL v3. The Premium sheet: its carousel, plans, and the month's free day.
import XCTest

final class PremiumSheetTests: ScreenshotTestCase {
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func testOpensOnFirstCardWithoutAFeature() {
        let app = launch("-locDenied", "-seedPremiumSheet")
        let card = element(app, "premium-card-print")
        XCTAssert(card.appears(within: 5))
        XCTAssert(waitFor(card, "isHittable == true"))
        XCTAssertFalse(element(app, "premium-card-sky").isHittable)
        save(app, "premium-sheet-print.png")
    }

    func testOpensOnTheNamedFeature() {
        let app = launch("-locDenied", "-seedPremiumSheet", "sky")
        let card = element(app, "premium-card-sky")
        XCTAssert(card.appears(within: 5))
        XCTAssert(waitFor(card, "isHittable == true"))
    }

    func testYearlyIsPreselected() {
        let app = launch("-locDenied", "-seedPremiumSheet")
        let yearly = element(app, "premium-plan-yearly")
        let lifetime = element(app, "premium-plan-lifetime")
        scrollTo(yearly, in: app)
        XCTAssertTrue(yearly.isSelected)
        XCTAssertFalse(lifetime.isSelected)
        XCTAssert(element(app, "premium-buy").exists)
        // App Review 3.1.2: the subscription states its term beside its price.
        XCTAssert(app.staticTexts["Renews every year until you cancel."].exists)
        lifetime.tap()
        XCTAssert(eventually(within: 5) { lifetime.isSelected && !yearly.isSelected })
    }

    func testFreeDayTurnsOnPremium() {
        let app = launch("-locDenied", "-resetFreeDay", "-seedPremiumSheet")
        let freeDay = element(app, "premium-free-day")
        scrollTo(freeDay, in: app)
        XCTAssertTrue(freeDay.label.contains("Try everything free today"), freeDay.label)
        freeDay.tap()
        XCTAssert(waitFor(freeDay, "label CONTAINS 'Free day until'"), freeDay.label)
        XCTAssert(element(app, "premium-buy").exists, "a free day still offers the purchase")
        save(app, "premium-sheet-free-day.png")
        element(app, "premium-close").tap()
        XCTAssert(element(app, "premium-close").disappears(within: 5))

        openSettings(app)
        let toggle = app.switches["settings-sky-bodies"].firstMatch
        scrollTo(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssert(eventually(within: 5) { toggle.value as? String == "0" })
        XCTAssertFalse(element(app, "premium-close").exists, "the free day must open the gate, not the sheet")
        app.terminate()
        launch("-locDenied", "-resetFreeDay").terminate()
    }

    func testUsedFreeDayShowsNextDate() {
        let app = launch("-locDenied", "-seedFreeDayUsed", "-seedPremiumSheet")
        let freeDay = element(app, "premium-free-day")
        scrollTo(freeDay, in: app)
        XCTAssertTrue(freeDay.label.contains("next free day"), freeDay.label)
        save(app, "premium-sheet-free-day-used.png")
        app.terminate()
        launch("-locDenied", "-resetFreeDay").terminate()
    }

    func testPurchasedHidesPlansAndFreeDay() {
        let app = launch("-locDenied", "-seedPremium", "-seedPremiumSheet")
        XCTAssert(element(app, "premium-card-print").appears(within: 5))
        XCTAssert(app.staticTexts["You have Premium — thank you."].firstMatch.exists)
        XCTAssertFalse(element(app, "premium-plan-yearly").exists)
        XCTAssertFalse(element(app, "premium-free-day").exists)
        XCTAssertFalse(element(app, "premium-buy").exists)
        save(app, "premium-sheet-purchased.png")
    }

    func testTableListsFreeRowsThenEveryFeature() {
        let app = launch("-locDenied", "-seedPremiumSheet")
        let table = element(app, "premium-table")
        // The whole table can sit taller than the space above the pinned button; its last row can't.
        scrollTo(table.descendants(matching: .any)["Sky controls"].firstMatch, in: app)
        for label in ["Every tide and current, every date, offline", "Home screen widgets", "The watch app",
                      "Print and PDF", "Alerts", "Calendars", "Lock screen widgets", "Watch complications", "Sky controls"] {
            XCTAssert(table.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch.exists, label)
        }
        scrollToEnd(app)
        let terms = app.descendants(matching: .any)["Terms of Use"].firstMatch
        XCTAssert(app.buttons["Restore purchase"].exists)
        XCTAssert(app.descendants(matching: .any)["Privacy Policy"].firstMatch.exists)
        XCTAssertLessThanOrEqual(terms.frame.maxY, element(app, "premium-buy").frame.minY,
                                 "the pinned button must not cover the end of the sheet")
        save(app, "premium-sheet-bottom.png")
    }

    func testSwipesThroughEveryCard() {
        let app = launch("-locDenied", "-seedPremiumSheet")
        for feature in ["print", "alerts", "calendars", "lockScreen", "watch", "sky"] {
            let card = element(app, "premium-card-\(feature)")
            XCTAssert(waitFor(card, "isHittable == true"), feature)
            XCTAssert(element(app, "premium-preview-\(feature)").appears(within: 10), feature)
            save(app, "premium-card-\(feature).png")
            card.swipeLeft()
        }
    }

    func testLargestTextKeepsTheButtonWhole() {
        let app = launch("-locDenied", "-seedPremiumSheet",
                         "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL")
        XCTAssert(element(app, "premium-preview-print").appears(within: 10))
        let buy = element(app, "premium-buy")
        XCTAssert(buy.label.contains("Get Premium"), buy.label)
        save(app, "premium-sheet-xxl-top.png")
        scrollTo(element(app, "premium-plan-yearly"), in: app)
        save(app, "premium-sheet-xxl-plans.png")
        scrollToEnd(app)
        XCTAssertLessThanOrEqual(app.descendants(matching: .any)["Terms of Use"].firstMatch.frame.maxY,
                                 buy.frame.minY)
        save(app, "premium-sheet-xxl-bottom.png")
    }

    private func openSettingsRow(_ app: XCUIApplication, _ id: String) {
        openSettings(app)
        XCTAssert(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons[id].firstMatch
        scrollTo(row, in: app)
        row.tap()
    }

    func testSkySwitchOpensOnSkyCard() {
        let app = launch("-locDenied")
        openSettings(app)
        let toggle = app.switches["settings-sky-bodies"].firstMatch
        scrollTo(toggle, in: app)
        toggle.tap()
        let card = element(app, "premium-card-sky")
        XCTAssert(card.appears(within: 5))
        XCTAssert(waitFor(card, "isHittable == true"))
    }

    func testCalendarOpensOnCalendarsCard() {
        let tide = "noaa/9444900"
        let app = launch("-locDenied", "-resetCalendars", "-seedFavorites", tide)
        openSettingsRow(app, "settings-calendar-row")
        XCTAssert(app.navigationBars["Favourites calendars"].appears(within: 5))
        app.switches["calendar-station-\(tide)"].tap()
        let card = element(app, "premium-card-calendars")
        XCTAssert(card.appears(within: 5))
        XCTAssert(waitFor(card, "isHittable == true"))
    }

    func testPrintableTablesOpensOnPrintCard() {
        let app = launch("-locDenied")
        openFridayHarbor(app)
        let row = app.buttons["printable-tables-row"].firstMatch
        XCTAssert(row.appears(within: 10))
        scrollTo(row, in: app)
        row.tap()
        let card = element(app, "premium-card-print")
        XCTAssert(card.appears(within: 5))
        XCTAssert(waitFor(card, "isHittable == true"))
    }

    func testAlertRemindMeOpensOnAlertsCard() {
        let app = launch("-resetAlerts")
        openFridayHarbor(app)
        let line = element(app, "alert-line")
        XCTAssert(line.appears(within: 5))
        line.tap()
        XCTAssert(app.buttons["alert-sheet-save"].appears(within: 5))
        app.buttons["alert-sheet-save"].tap()
        let card = element(app, "premium-card-alerts")
        XCTAssert(card.appears(within: 5))
        XCTAssert(waitFor(card, "isHittable == true"))
    }

    /// A calendar a free day turned on keeps its row after the day ends, and says it stopped.
    func testEndedFreeDayCalendarSaysItStoppedAndOpensCalendars() {
        let tide = "noaa/9444900"
        let app = launch("-locDenied", "-resetCalendars", "-seedFavorites", tide,
                         "-seedFreeDayCalendar", tide)
        openSettingsRow(app, "settings-calendar-row")
        let status = element(app, "calendar-stopped-\(tide)")
        XCTAssert(status.appears(within: 5))
        XCTAssertTrue(status.label.contains("Stopped"), status.label)
        save(app, "calendar-free-day-ended.png")
        status.tap()
        let card = element(app, "premium-card-calendars")
        XCTAssert(card.appears(within: 5))
        XCTAssert(waitFor(card, "isHittable == true"))
    }

    func testPremiumRowReadsNotPurchasedDuringAFreeDay() {
        let app = launch("-locDenied", "-seedFreeDay")
        let row = app.buttons["Support Slackwater"].firstMatch
        scrollTo(row, in: app)
        XCTAssert(row.exists)
        XCTAssertFalse(app.staticTexts["You have Premium — thank you."].exists)
    }

    /// `scrollTo` counts an element under the pinned button as in reach; swipe until the end shows.
    private func scrollToEnd(_ app: XCUIApplication) {
        let terms = app.descendants(matching: .any)["Terms of Use"].firstMatch
        let buy = element(app, "premium-buy")
        for _ in 0..<10 {
            if terms.exists, terms.frame.maxY <= buy.frame.minY, terms.frame.minY > 0 { return }
            app.swipeUp()
        }
    }
}
