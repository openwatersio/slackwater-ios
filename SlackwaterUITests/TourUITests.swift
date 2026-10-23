// Slackwater — GPL v3. The first-run tour: the walk, the skip, and the
// assertion that earns its keep — a real swipe advances the stars mark.
import XCTest

final class TourUITests: ScreenshotTestCase {
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
