// Slackwater — GPL v3. Settings keeps widgets inline and app information one page away.
import XCTest

final class SettingsLayoutTests: ScreenshotTestCase {
    func testSlackWindowPreviewChangesWithComfortCurrent() {
        let app = launch("-seedGate", "-locDenied")
        openSettings(app)
        save(app, "slack-window-settings-before.png")
        let preview = app.descendants(matching: .any)["slack-window-preview"].firstMatch
        XCTAssert(preview.appears(within: 5))
        let before = preview.value as? String
        let stepper = app.steppers.firstMatch
        stepper.buttons["Increment"].tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before ?? ""), object: preview)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed)
        save(app, "slack-window-settings-expanded.png")
    }

    func testWidgetsAndAboutAreInSettings() {
        checkSettings(language: "en", settingsTitle: "Settings", aboutTitle: "About", restoreTitle: "Restore purchase", previewTitle: "Example slack window", calendarSummary: "Publish a station's tides or slack windows to your calendar")
    }

    func testSettingsInFrench() {
        checkSettings(language: "fr-CA", settingsTitle: "Réglages", aboutTitle: "À propos", restoreTitle: "Restaurer l’achat")
    }

    func testSettingsInSpanish() {
        checkSettings(language: "es-ES", settingsTitle: "Ajustes", aboutTitle: "Acerca de", restoreTitle: "Restaurar compra")
    }

    func testSettingsInJapanese() {
        checkSettings(language: "ja", settingsTitle: "設定", aboutTitle: "このアプリについて", restoreTitle: "購入を復元")
    }

    func testSettingsInGerman() {
        checkSettings(language: "de", settingsTitle: "Einstellungen", aboutTitle: "Über", restoreTitle: "Kauf wiederherstellen")
    }

    func testSettingsInPortuguese() {
        checkSettings(language: "pt-BR", settingsTitle: "Ajustes", aboutTitle: "Sobre", restoreTitle: "Restaurar compra")
    }

    func testSettingsInDutch() {
        checkSettings(language: "nl", settingsTitle: "Instellingen", aboutTitle: "Info", restoreTitle: "Aankoop herstellen")
    }

    func testSettingsInNorwegian() {
        checkSettings(language: "nb", settingsTitle: "Innstillinger", aboutTitle: "Om", restoreTitle: "Gjenopprett kjøp")
    }

    func testSettingsInDanish() {
        checkSettings(language: "da", settingsTitle: "Indstillinger", aboutTitle: "Om", restoreTitle: "Gendan køb", previewTitle: "Eksempel på strømstille periode", calendarSummary: "Føj en stations tidevand eller strømstille perioder til din kalender")
    }

    func testSettingsInFinnish() {
        checkSettings(language: "fi", settingsTitle: "Asetukset", aboutTitle: "Tietoja", restoreTitle: "Palauta osto", previewTitle: "Esimerkki heikon virtauksen jaksosta", calendarSummary: "Lisää aseman vuorovedet tai heikon virtauksen jaksot kalenteriisi")
    }

    func testSettingsInItalian() {
        checkSettings(language: "it", settingsTitle: "Impostazioni", aboutTitle: "Informazioni", restoreTitle: "Ripristina acquisto", previewTitle: "Esempio di finestra di stanca", calendarSummary: "Aggiungi al calendario le maree o le finestre di stanca di una stazione")
    }

    func testSettingsInKorean() {
        checkSettings(language: "ko", settingsTitle: "설정", aboutTitle: "정보", restoreTitle: "구매 복원", previewTitle: "정조 시간대 예시", calendarSummary: "관측소의 조석이나 정조 시간대를 캘린더에 추가")
    }

    func testSettingsInEuropeanPortuguese() {
        checkSettings(language: "pt-PT", settingsTitle: "Definições", aboutTitle: "Sobre", restoreTitle: "Restaurar compra", previewTitle: "Exemplo de período de estofo", calendarSummary: "Adicione as marés ou períodos de estofo de uma estação ao calendário")
    }

    func testSettingsInSwedish() {
        checkSettings(language: "sv", settingsTitle: "Inställningar", aboutTitle: "Om", restoreTitle: "Återställ köp", previewTitle: "Exempel på strömstilla period", calendarSummary: "Lägg till en stations tidvatten eller strömstilla perioder i kalendern")
    }

    func testMacSettingsShowsDesktopWidgets() {
        let app = launch("-seedGate", "-locDenied", "-settingsPlatform", "mac")
        openSettings(app)
        XCTAssert(app.staticTexts["Desktop — free"].exists)
        XCTAssertFalse(app.staticTexts["Home screen — free"].exists)
        XCTAssertFalse(app.staticTexts["Lock screen — Premium"].exists)
        let about = app.buttons["settings-about-row"].firstMatch
        scrollTo(about, in: app)
        XCTAssert(app.buttons["Restore purchase"].exists)
        save(app, "settings-mac-policy.png")
    }

    func testMacWidgetInstructionsInFrenchAndSpanish() {
        for (language, settingsTitle, desktopTitle, supportTitle) in [
            ("fr-CA", "Réglages", "Bureau — gratuit", "Soutenez le développement de Slackwater."),
            ("es-ES", "Ajustes", "Escritorio — gratis", "Apoya el desarrollo de Slackwater.")
        ] {
            let app = launch("-seedGate", "-locDenied", "-settingsPlatform", "mac",
                             "-AppleLanguages", "(\(language))", "-AppleLocale", language)
            let settings = app.buttons[settingsTitle].firstMatch
            scrollTo(settings, in: app)
            settings.tap()
            XCTAssert(app.staticTexts[desktopTitle].exists)
            let about = app.buttons["settings-about-row"].firstMatch
            scrollTo(about, in: app)
            XCTAssert(app.staticTexts[supportTitle].exists)
            save(app, "settings-mac-\(language).png")
            app.terminate()
        }
    }

    func testTVSettingsOmitsWidgetInstructions() {
        let app = launch("-seedGate", "-locDenied", "-settingsPlatform", "tv")
        openSettings(app)
        XCTAssertFalse(app.staticTexts["Desktop — free"].exists)
        XCTAssertFalse(app.staticTexts["Home screen — free"].exists)
        XCTAssertFalse(app.staticTexts["Lock screen — Premium"].exists)
        let about = app.buttons["settings-about-row"].firstMatch
        scrollTo(about, in: app)
        XCTAssert(app.buttons["Restore purchase"].exists)
        save(app, "settings-tv-policy.png")
    }

    private func checkSettings(language: String, settingsTitle: String, aboutTitle: String, restoreTitle: String, previewTitle: String? = nil, calendarSummary: String? = nil) {
        let app = launch("-seedGate", "-locDenied", "-AppleLanguages", "(\(language))", "-AppleLocale", language)
        // Use the gear's identifier-independent location in translated runs.
        if language == "en" {
            openSettings(app)
        } else {
            let settings = app.buttons[settingsTitle].firstMatch
            scrollTo(settings, in: app)
            settings.tap()
        }
        if let previewTitle {
            let preview = app.descendants(matching: .any)["slack-window-preview"].firstMatch
            XCTAssert(preview.appears(within: 5))
            XCTAssertEqual(preview.label, previewTitle)
            XCTAssertFalse((preview.value as? String ?? "").isEmpty)
            save(app, "settings-slack-window-\(language).png")
        }
        if let calendarSummary {
            let calendar = app.buttons["settings-calendar-row"].firstMatch
            scrollTo(calendar, in: app)
            XCTAssertTrue(calendar.label.contains(calendarSummary))
            if language != "en" {
                XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Alerts")).firstMatch.exists)
            }
        }
        XCTAssertFalse(app.staticTexts["Not for navigation."].exists)
        XCTAssertFalse(app.staticTexts["Offline downloads"].exists)
        if language == "en" {
            XCTAssert(app.staticTexts["Home screen — free"].exists)
            XCTAssert(app.staticTexts["Lock screen — Premium"].exists)
            let home = app.staticTexts["Home screen — free"].firstMatch
            scrollTo(home, in: app)
            save(app, "settings-home-en.png")
        }
        let about = app.buttons["settings-about-row"].firstMatch
        scrollTo(about, in: app)
        let restore = app.buttons[restoreTitle].firstMatch
        XCTAssert(restore.exists)
        save(app, "settings-after-\(language).png")
        about.tap()
        XCTAssert(app.navigationBars[aboutTitle].appears(within: 5))
        save(app, "settings-about-\(language).png")
        if language == "en" {
            XCTAssert(app.staticTexts["Not for navigation."].exists)
            XCTAssert(app.staticTexts["Privacy"].exists)
            XCTAssert(app.staticTexts["License"].exists)
            XCTAssert(app.staticTexts["Version"].exists)
        }
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'NOAA CO-OPS'")).firstMatch.exists)
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'OpenFreeMap'")).firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssert(about.appears(within: 5))
    }

    func testPremiumSupporterSeesTheirEntitlementInline() {
        let app = launch("-seedGate", "-locDenied", "-seedPremium")
        openSettings(app)
        let about = app.buttons["settings-about-row"].firstMatch
        scrollTo(about, in: app)
        XCTAssert(app.staticTexts["You have Premium — thank you."].exists)
        XCTAssertFalse(app.buttons["Restore purchase"].exists)
    }
}
