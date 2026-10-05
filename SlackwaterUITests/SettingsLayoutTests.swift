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
        checkSettings(language: "en", settingsTitle: "Settings", aboutTitle: "About", restoreTitle: "Restore purchase")
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

    private func checkSettings(language: String, settingsTitle: String, aboutTitle: String, restoreTitle: String) {
        let app = launch("-seedGate", "-locDenied", "-AppleLanguages", "(\(language))", "-AppleLocale", language)
        // Use the gear's identifier-independent location in translated runs.
        if language == "en" {
            openSettings(app)
        } else {
            let settings = app.buttons[settingsTitle].firstMatch
            scrollTo(settings, in: app)
            settings.tap()
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
