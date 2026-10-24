// Slackwater — GPL v3. The first-run tour: the walk, the skip, and the
// assertion that earns its keep — a real swipe advances the stars mark.
import XCTest

final class TourUITests: ScreenshotTestCase {
    func testCachedPreviewSkipsSkyTargetsBeyondItsCoverage() {
        let token = UUID().uuidString
        let app = canadianFirstRun(["-chsFixture", token, "-chsFixtureScenario", "tide-preview-final"])
        XCTAssert(app.descendants(matching: .any)["chs-waiting-warning"].firstMatch.appears(within: 10))
        releaseFixture(token, "chs-nanaimo-harbour-first-chunk")
        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        app.terminate()

        // The saved preview ends at local midnight, one hour after this relaunch.
        app.launchArguments = testArguments(["-resetTour", "-networkKillSwitch", "-nowOffsetDays", "4.75",
            "-fixLat", "49.1659", "-fixLon", "-123.9401"])
            .filter { $0 != "-seedTour" }
        app.launch()
        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        XCTAssert(waitFor(app.buttons["tour-next"], "isHittable == true"))
        let selected = leadReading(app).value as? String
        XCTAssertNotNil(selected)
        app.buttons["tour-next"].tap()
        XCTAssert(app.staticTexts["Tap the moon for its rise, set and phase."].firstMatch.appears(within: 10),
                  "an almost-expired preview must skip unreachable stars and moon targets")
        XCTAssertEqual(leadReading(app).value as? String, selected)
        save(app, "tour-nanaimo-short-preview.png")
    }

    func testLeavingACanadianReplayWaitingPageStaysOnTheList() {
        let app = launch("-networkKillSwitch", "-chsResetModels", "-resetFavorites", "-resetRecents",
                         "-fixLat", "49.1659", "-fixLon", "-123.9401")
        openSettings(app)
        let replay = app.buttons["settings-replay-tour"].firstMatch
        scrollTo(replay, in: app)
        replay.tap()
        XCTAssert(app.staticTexts["Nanaimo Harbour"].firstMatch.appears(within: 10))
        XCTAssert(app.descendants(matching: .any)["chs-waiting-warning"].firstMatch.exists)
        app.buttons["detail-back"].firstMatch.tap()
        openSearch(app, "seattle")
        XCTAssert(app.staticTexts["Seattle"].firstMatch.appears(within: 5), "Back must leave the waiting page usable")
    }

    func testCanadianTourStartsOnThePreviewAndSurvivesTheFullModel() {
        let token = UUID().uuidString
        let app = canadianFirstRun(["-chsFixture", token, "-chsFixtureScenario", "tide-preview-final"])
        let mark = app.otherElements["tour-mark"].firstMatch
        XCTAssert(app.staticTexts["Nanaimo Harbour"].firstMatch.appears(within: 10))
        XCTAssert(app.descendants(matching: .any)["chs-waiting-warning"].firstMatch.exists)
        XCTAssertFalse(mark.exists, "the tour needs usable predictions before it can teach")
        save(app, "tour-nanaimo-waiting.png")

        releaseFixture(token, "chs-nanaimo-harbour-first-chunk")
        XCTAssert(mark.appears(within: 15), "the preview must start the tour before the full model finishes")
        XCTAssert(waitFor(app.buttons["tour-next"], "isHittable == true"))
        let notice = app.descendants(matching: .any)["chs-download-notice"].firstMatch
        XCTAssert(notice.exists)
        XCTAssert(app.progressIndicators["chs-download-notice"].firstMatch.exists)
        save(app, "tour-nanaimo-preview.png")
        app.buttons["tour-next"].tap()
        let sky = app.staticTexts["The real sky"].firstMatch
        XCTAssert(sky.appears(within: 15))
        let selected = leadReading(app).value as? String
        XCTAssertNotNil(selected)

        releaseFixture(token, "after-tide-preview")
        XCTAssert(notice.disappears(within: 30))
        XCTAssert(sky.exists, "finishing the model must preserve the tour step")
        XCTAssertEqual(leadReading(app).value as? String, selected)
        XCTAssert(app.staticTexts["Nanaimo Harbour"].firstMatch.exists)
        save(app, "tour-nanaimo-full-model.png")
    }

    func testCanadianTourWaitsOfflineAtTheLocalPlace() {
        let app = canadianFirstRun(["-networkKillSwitch"])
        XCTAssert(app.staticTexts["Nanaimo Harbour"].firstMatch.appears(within: 10))
        XCTAssert(app.descendants(matching: .any)["chs-waiting-warning"].firstMatch.exists)
        XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.appears(within: 3))
        XCTAssertFalse(app.staticTexts["Point Roberts"].exists)
        XCTAssert(app.buttons["detail-back"].firstMatch.isHittable)
        save(app, "tour-nanaimo-offline.png")
    }

    private func canadianFirstRun(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = testArguments(args + ["-resetTour", "-resetRecents", "-resetFavorites",
            "-chsResetModels", "-chsFitOnly", "chs-nanaimo-harbour",
            "-fixLat", "49.1659", "-fixLon", "-123.9401"])
            .filter { $0 != "-seedTour" }
        app.launch()
        return app
    }

    func testADeepLinkWinsWhileTheCanadianTourIsWaiting() {
        let app = canadianFirstRun(["-networkKillSwitch"])
        XCTAssert(app.staticTexts["Nanaimo Harbour"].firstMatch.appears(within: 10))
        XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.exists)
        XCUIDevice.shared.system.open(URL(string: "slackwater://station/noaa%2F9447130")!)
        let confirm = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"].firstMatch
        if confirm.appears(within: 5) { confirm.tap() }
        XCTAssert(app.staticTexts["Seattle"].firstMatch.appears(within: 20))
        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        XCTAssertFalse(app.descendants(matching: .any)["chs-waiting-warning"].firstMatch.exists)
    }

    func testTourUsesAppLanguage() {
        let translations: [(String, [(String, String)])] = [
            ("de", [
                ("Die Zeitleiste lesen", "Die Mittellinie markiert den unten angezeigten Zeitpunkt."),
                ("Der echte Himmel", "Das sind die tatsächlichen Sterne über Friday Harbor heute Nacht."),
                ("Der Mond", "Und das ist der echte Mond in seiner heutigen Phase."),
                ("Monddetails", "Tippe auf den Mond, um Aufgang, Untergang und Phase zu sehen."),
                ("Favoriten", "Markiere eine Station mit einem Stern, damit sie oben in deiner Liste bleibt.")
            ]),
            ("fi", [
                ("Aikajanan lukeminen", "Keskiviiva osoittaa alla näkyvän hetken."),
                ("Todellinen taivas", "Nuo ovat todelliset tähdet paikan Friday Harbor yllä tänä yönä."),
                ("Kuu", "Ja tuo on oikea kuu tämän yön vaiheessaan."),
                ("Kuun tiedot", "Napauta kuuta nähdäksesi sen nousun, laskun ja vaiheen."),
                ("Suosikit", "Merkitse asema tähdellä, niin se pysyy luettelosi alussa.")
            ]),
            ("ga", [
                ("An stiall a léamh", "Léiríonn an lárlíne an nóiméad a thaispeántar thíos."),
                ("An spéir fhíor", "Sin iad na fíorréaltaí os cionn Friday Harbor anocht."),
                ("An ghealach", "Agus sin í an ghealach fhíor, ina céim anocht."),
                ("Sonraí na gealaí", "Tapáil an ghealach chun a héirí, a luí agus a céim a fheiceáil."),
                ("Ceanáin", "Cuir réalta le stáisiún chun é a choinneáil ag barr do liosta.")
            ])
        ]
        for (language, cards) in translations {
            let app = XCUIApplication()
            app.launchArguments = testArguments(["-resetTour", "-locAuthorizedNoFix",
                                                 "-AppleLanguages", "(\(language))", "-AppleLocale", language])
                .filter { $0 != "-seedTour" }
            app.launch()
            XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
            save(app, "tour-\(language)-initial.png")
            for (index, card) in cards.enumerated() {
                let title = app.staticTexts[card.0].firstMatch
                let copy = app.staticTexts[card.1].firstMatch
                XCTAssert(title.appears(within: 15), "\(language) tour title \(index) is not translated")
                XCTAssert(copy.appears(within: 5), "\(language) tour copy \(index) is not translated")
                let next = app.buttons["tour-next"]
                XCTAssert(next.isHittable)
                let frames = settled { [title.frame, copy.frame, next.frame, app.frame] }
                XCTAssertLessThanOrEqual(frames[0].maxY, frames[1].minY)
                XCTAssertLessThanOrEqual(frames[1].maxY, frames[2].minY)
                XCTAssert(frames[3].contains(frames[0].union(frames[1]).union(frames[2])))
                save(app, "tour-\(language)-\(index).png")
                next.tap()
            }
            XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.exists)
            app.terminate()
        }
    }

    func testTourWalksAndSticks() {
        let app = XCUIApplication()
        // ScreenshotTestCase seeds -seedTour by default so every other UI
        // test suppresses the tour; strip it here so it actually fires.
        app.launchArguments = testArguments(["-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        let mark = app.otherElements["tour-mark"].firstMatch
        XCTAssert(mark.appears(within: 15), "the tour did not fire on the first detail")
        save(app, "tour-1-read.png")

        // Read → stars → moon → moonCard → star, then done.
        for n in 2...5 {
            app.buttons["tour-next"].tap()
            // Let the 0.2 s crossfade finish so the shot is the new mark alone.
            Thread.sleep(forTimeInterval: 0.4)
            save(app, "tour-\(n).png")
        }
        XCTAssert(app.buttons["Done"].exists, "the last mark should offer Done")
        app.buttons["tour-next"].tap()
        XCTAssertFalse(mark.exists, "Done must end the tour")

        // One-way: the flag survives a relaunch.
        app.terminate()
        app.launchArguments = testArguments(["-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()
        XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.appears(within: 5),
                       "a seen tour must not run again")
    }

    // The assertion this whole design rests on: the overlay hit-tests only on
    // its capsule, so the user's own drag reaches the strip underneath. If
    // this regresses the tour still "works" and silently stops teaching.
    func testARealSwipeAdvancesTheStarsMark() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        app.buttons["tour-next"].tap()   // → .stars

        scrubStrip(app)
        settleScrub(app)
        // Advancing off .stars lands on .moon, whose mark names the moon.
        XCTAssert(app.staticTexts["And that is the real moon, at tonight's phase."]
                    .appears(within: 5),
                  "a real drag must advance the stars mark — the overlay is swallowing touches")
    }

    func testSkipEndsItFromTheFirstMark() {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-resetTour", "-locAuthorizedNoFix"])
            .filter { $0 != "-seedTour" }
        app.launch()

        XCTAssert(app.otherElements["tour-mark"].firstMatch.appears(within: 15))
        app.buttons["tour-skip"].tap()
        XCTAssertFalse(app.otherElements["tour-mark"].firstMatch.exists)
    }
}
