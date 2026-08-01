// Slackwater — GPL v3. Walks the M1–M4 surfaces and saves screenshots.
// Doubles as the smoke check that every interaction actually responds.
// M4 launch flow: the app opens on the first-run gate, then the list — tests
// seed or reset that state explicitly (-seedGate / -resetGate) because a
// UserDefaults value passed as a launch argument would mask in-app writes.
import UIKit
import XCTest

final class ScreenshotTests: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["M1_SHOT_DIR"] ?? "/tmp"

    /// M4.5: search lives behind the bottom-left FAB. Opens it and types with
    /// NO field tap — typeText throws unless the field already has keyboard
    /// focus, so every use doubles as the keyboard-up-immediately assertion.
    private func openSearch(_ app: XCUIApplication, _ text: String) {
        app.buttons["Search"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssert(field.waitForExistence(timeout: 5), "search input did not appear")
        sleep(1)  // let the auto-focus land
        field.typeText(text)
    }

    /// The X glass circle beside the bottom input (Bryan's Weather reference).
    private func closeSearch(_ app: XCUIApplication) {
        app.buttons["Close search"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
    }

    /// Scroll the list until `el` is realized and hittable (Recents now lives
    /// at the very bottom — often below the fold).
    private func scrollTo(_ el: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while (!el.exists || !el.isHittable), tries < 6 {
            app.swipeUp()
            tries += 1
        }
        XCTAssert(el.exists, "could not scroll to element")
    }

    /// Pan the timeline strip under its fixed centerline (drag left = later).
    /// Targets the strip element itself so the drag lands on it at any size —
    /// the old window-normalized offsets (dy 0.8) miss the strip on iPad.
    private func scrubStrip(_ app: XCUIApplication) {
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.waitForExistence(timeout: 5), "timeline strip missing")
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo:
                strip.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
    }

    func testM1Walkthrough() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        // M4: launches on the list — when located it ranks by distance, so
        // reach Friday Harbor through search (deterministic either way).
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // Units are settings-only now (no list pill): reset to feet first —
        // the setting persists across runs.
        setUnits(app, "Feet")

        openFridayHarbor(app)
        sleep(2)

        // Scrub: pan the strip under the fixed centerline (drag left = later),
        // release — the readout keeps the scrubbed time.
        scrubStrip(app)
        sleep(1)
        save(app, "m1-detail-scrubbed.png")

        // Back to the station list (search closed itself on the pick).
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        sleep(1)
        save(app, "m1-list.png")

        // Search mid-query: name + region substring both match (bottom input).
        openSearch(app, "pass")
        XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        save(app, "m1-search.png")
        closeSearch(app)

        // Metres via Settings, then open Friday Harbor in metric.
        setUnits(app, "Meters")
        openFridayHarbor(app)
        sleep(2)
        save(app, "m1-detail-metric.png")
        // Leave the store imperial for the other tests.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        setUnits(app, "Feet")
    }

    /// Units moved to Settings only (design pass item 1): toggle there.
    private func setUnits(_ app: XCUIApplication, _ label: String) {
        app.buttons["Settings"].tap()
        let segment = app.buttons[label]
        XCTAssert(segment.waitForExistence(timeout: 5))
        segment.tap()
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
    }

    /// Search "friday" via the FAB → tap the tide card → detail (the overlay
    /// closes itself on the pick).
    private func openFridayHarbor(_ app: XCUIApplication) {
        openSearch(app, "friday")
        let card = app.staticTexts["Friday Harbor"].firstMatch
        XCTAssert(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
    }

    // M2: current stations join the list; walk into Deception Pass and scrub
    // the signed velocity curve.
    func testM2Currents() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        sleep(2)
        save(app, "m2-list-mixed.png")

        // Search finds the current station; its detail is the signed curve.
        openSearch(app, "deception")
        let card = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 5))  // MonoLabel uppercases
        sleep(2)
        save(app, "m2-current-detail.png")

        // Scrub: pan the combined tide+current strip, release.
        scrubStrip(app)
        sleep(1)
        save(app, "m2-current-scrubbed.png")
    }

    // M3: Canadian (CHS) stations — pending state, a REAL end-to-end fit
    // against live IWLS, then the airplane-mode day-after relaunch. One test,
    // in order, because the offline half depends on the fit half's stored model.
    func testM3ChsPendingFitOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels", "-seedGate"]  // clean first-run
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // Victoria is pending (or already mid-fit): identity + honest message, no numbers.
        openSearch(app, "victoria")
        let pending = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'signal' OR label CONTAINS 'Downloading'")).firstMatch
        XCTAssert(pending.waitForExistence(timeout: 10))
        sleep(1)
        save(app, "m3-pending.png")

        // Live IWLS fetch (10 polite requests) + JSCore fit. The card becomes
        // a navigable tide card when the model lands — it stops being copy and
        // shows numbers. (Cards are no longer buttons: since the M4.3 List
        // conversion, rows navigate via a hidden link.)
        let fitted = app.staticTexts.matching(
            NSPredicate(format: "label == 'Rising' OR label == 'Falling'")).firstMatch
        XCTAssert(fitted.waitForExistence(timeout: 300), "Victoria never fitted — IWLS unreachable?")
        sleep(1)
        app.staticTexts["Victoria"].firstMatch.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        // The provenance marking (device-computed vs authoritative-harmonic).
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        save(app, "m3-fitted-detail.png")

        // Airplane-mode day-after: relaunch offline, clock shifted to tomorrow.
        app.terminate()
        app.launchArguments = ["-networkKillSwitch", "-nowOffsetDays", "1", "-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openSearch(app, "victoria")
        let offlineFitted = app.staticTexts.matching(
            NSPredicate(format: "label == 'Rising' OR label == 'Falling'")).firstMatch
        XCTAssert(offlineFitted.waitForExistence(timeout: 10), "stored model did not survive relaunch")
        app.staticTexts["Victoria"].firstMatch.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["↑ HIGH"].firstMatch.waitForExistence(timeout: 5)
                  || app.staticTexts["↓ LOW"].firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        save(app, "m3-offline.png")
    }

    // M4: first-run gate — the search bypass lands in the search experience
    // (M4.5), and the choice sticks across relaunch without reopening search.
    // (The Use-My-Location path needs the system permission dialog; exercised
    // manually via simctl privacy.)
    func testM4Gate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGate"]
        app.launch()

        XCTAssert(app.staticTexts["See tides near you"].waitForExistence(timeout: 10))
        XCTAssert(app.buttons["Use My Location"].exists)
        save(app, "m4-ftue-gate.png")
        app.buttons["Or search for a harbor, bay, or channel."].tap()
        let field = app.textFields.firstMatch
        XCTAssert(field.waitForExistence(timeout: 5), "gate bypass did not open search")
        sleep(1)
        field.typeText("friday")  // works only if the field auto-focused
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.waitForExistence(timeout: 5))
        closeSearch(app)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields.firstMatch.exists,
                       "search must not reopen on relaunch — the handoff is one-shot")
    }

    // M4: pin map — opens from the floating button, land + pins render, and a
    // tap on the Deception Pass (Narrows) pin opens its detail. The pin's
    // screen point is pure web-mercator math from the fixed camera
    // (center 48.35,-123.05 · zoom 7.35 · 512pt world tiles — MapScreen's
    // SALISH constants; the styler re-asserts them after style load).
    func testM4MapPinToDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        app.buttons["Map"].tap()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 5))
        // M4.5: no header, no X — the toggle FAB (now the list icon) is the
        // way back, and the search FAB persists over the map.
        XCTAssertFalse(app.staticTexts["MAP"].exists, "map must carry no header chrome")
        XCTAssert(app.buttons["List"].exists, "toggle FAB did not flip to the list icon")
        XCTAssert(app.buttons["Search"].exists, "search FAB missing over the map")
        sleep(5)  // let tiles (and Seascape, when reachable) come in
        save(app, "m41-map-zoom.png")
        let frame = map.frame
        let world = 512.0 * pow(2.0, 7.35)  // SALISH_ZOOM
        func mercator(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
            let x = (lon + 180) / 360 * world
            let phi = lat * .pi / 180
            let y = (1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2 * world
            return (x, y)
        }
        let c = mercator(48.35, -123.05)                          // SALISH_CENTER
        let p = mercator(48.40618896484375, -122.64311981201172)  // Deception Pass (Narrows)
        let nx = (frame.midX + (p.x - c.x) - frame.minX) / frame.width
        let ny = (frame.midY + (p.y - c.y) - frame.minY) / frame.height
        map.coordinate(withNormalizedOffset: CGVector(dx: nx, dy: ny)).tap()

        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5),
                  "map pin tap did not open a station detail")
        XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch.waitForExistence(timeout: 5))
    }

    // M4: the paired current→tide detail on Deception Pass — the pane exists,
    // and every one of the reference port's schedule numbers (time + height of
    // each high/low today) appears verbatim in the gate's merged view: same
    // engine path, same values (current-detail spec §2).
    func testM4PairedTide() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // First: the reference port's own detail — collect today's H/L numbers.
        openSearch(app, "deception")
        let port = app.staticTexts["Deception Pass State Park"].firstMatch
        XCTAssert(port.waitForExistence(timeout: 5))
        port.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        sleep(1)
        let portTimes = clockLabels(app)
        let portHeights = heightLabels(app)
        XCTAssert(!portTimes.isEmpty && !portHeights.isEmpty, "no schedule rows read from the port detail")

        // Then: the gate's detail — paired pane present, port numbers verbatim.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "deception")
        let gate = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(gate.waitForExistence(timeout: 5))
        gate.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["TIDE AT DECEPTION PASS STATE PARK"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["↑ HIGH"].firstMatch.waitForExistence(timeout: 5)
                  || app.staticTexts["↓ LOW"].firstMatch.waitForExistence(timeout: 5),
                  "paired tide rows missing from the events table")
        sleep(1)
        save(app, "m4-paired-detail.png")

        let gateTimes = clockLabels(app)
        let gateHeights = heightLabels(app)
        // Sun rows joined the schedule (design pass item 7a) and are computed
        // from each station's own position, so a port sun time may differ from
        // the gate's by seconds — allow a 1-minute neighbour for those labels.
        func minutes(_ s: String) -> Int {
            let parts = s.split(separator: ":")
            return Int(parts[0])! * 60 + Int(parts[1])!
        }
        for t in portTimes {
            let ok = gateTimes.contains(t)
                || gateTimes.contains { abs(minutes($0) - minutes(t)) <= 1 }
            XCTAssert(ok, "port event at \(t) missing from paired view (has \(gateTimes))")
        }
        for h in portHeights {
            XCTAssert(gateHeights.contains(h), "port height \(h) missing from paired view (has \(gateHeights))")
        }
    }

    // M4: settings — units share the pill's store; the statement + licenses show.
    func testM4Settings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssert(app.staticTexts["Not for navigation."].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'OpenStreetMap'")).firstMatch.exists)
        sleep(1)
        save(app, "m4-settings.png")
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
    }

    // M4.1 design pass: the regrouped list — My Location hero (nm pill, 3-dp
    // coords, no match-grade sentence), Recents after a visit, Near Me, and
    // nothing else (no catalog section, no units pill).
    func testM41GroupedListAndRecents() throws {
        let app = XCUIApplication()
        // Deterministic Victoria fix via the -fixLat/-fixLon hook.
        app.launchArguments = ["-seedGate", "-resetRecents",
                               "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["MY LOCATION"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["NEAR ME"].exists)
        // The full-catalog section and the units pill are gone.
        XCTAssertFalse(app.staticTexts["SALISH SEA"].exists)
        XCTAssertFalse(app.buttons["FT"].exists)
        XCTAssertFalse(app.buttons["M"].exists)
        // Tile copy: coordinates only — no "to station"/match-grade sentence.
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '°N'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'to station'")).firstMatch.exists)
        // No recents yet on a clean run.
        XCTAssertFalse(app.staticTexts["RECENTS"].exists)
        sleep(2)
        save(app, "m41-mylocation-tile.png")

        // Visit a station; it must appear under Recents — now the very BOTTOM
        // group (M4.5 order: My Location → Favorites → Near Me → Recents).
        openFridayHarbor(app)
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        let near = app.staticTexts["NEAR ME"].firstMatch
        XCTAssert(near.waitForExistence(timeout: 5))
        let recentsLabel = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsLabel, in: app)
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        // Both labels realized (tall screens / short lists): direct order check.
        if near.exists {
            XCTAssert(near.frame.minY < recentsLabel.frame.minY,
                      "Recents must render below Near Me")
        }
        sleep(2)
        save(app, "m45-groups-order.png")
        save(app, "m41-list-grouped.png")
    }

    // M4.1: the detail header is the station map with the title overlaid, the
    // schedule carries sunrise/sunset rows, and the scrubber wears the moon
    // with its phase name.
    func testM41DetailMapHeaderSunMoon() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openFridayHarbor(app)
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 5),
                  "map header missing from tide detail")
        XCTAssert(app.staticTexts["☀ RISE"].firstMatch.waitForExistence(timeout: 5),
                  "sunrise row missing from the day schedule")
        XCTAssert(app.staticTexts["☀ SET"].firstMatch.exists,
                  "sunset row missing from the day schedule")
        let phaseNames = "New Moon|Waxing Crescent|First Quarter|Waxing Gibbous|Full Moon|Waning Gibbous|Last Quarter|Waning Crescent"
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", phaseNames)).firstMatch.exists,
                  "moon phase name missing from the scrub readout")
        sleep(6)  // let the header map tiles come in
        save(app, "m41-detail-mapheader.png")

        // Scrub, then capture the moon-bearing scrub card.
        scrubStrip(app)
        sleep(1)
        save(app, "m41-scrubber-moon.png")

        // The map header carries the current-station detail too.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "deception")
        let gate = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(gate.waitForExistence(timeout: 5))
        gate.tap()
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 5),
                  "map header missing from current detail")
        XCTAssert(app.staticTexts["☀ RISE"].firstMatch.waitForExistence(timeout: 5),
                  "sunrise row missing from the current-station schedule")
    }

    // M4.1: location denied — the amber card sits in the My Location slot
    // (NearMe.dc.html "unavailable"), above Near Me ranked from the fallback.
    func testM41DeniedSlot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-resetRecents", "-locDenied"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Location unavailable"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Go to Settings"].exists)
        XCTAssertFalse(app.staticTexts["MY LOCATION"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)
        sleep(2)
        save(app, "m41-denied-slot.png")
    }

    // M4.2: the continuous scrub — a fixed centerline with the multi-day strip
    // panning underneath. Scrubbing across midnight lands on the next day's
    // events; the schedule shows several days under day headers; a row tap
    // scrubs cross-day; return-to-now comes home.
    func testM42ContinuousScrubAcrossMidnight() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openFridayHarbor(app)
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "pan-under-centerline strip missing from tide detail")

        // The multi-day schedule carries day headers beyond today.
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Tomorrow"].waitForExistence(timeout: 5),
                  "multi-day schedule missing its Tomorrow day header")

        // Pan the strip: the centerline readout moves off "now".
        scrubStrip(app)
        sleep(1)
        XCTAssert(app.buttons["Return to now"].waitForExistence(timeout: 5),
                  "return-to-now affordance missing after scrubbing away")
        save(app, "m42-scrub-center.png")

        // Multi-day list, day-grouped.
        app.swipeUp()
        sleep(1)
        save(app, "m42-multiday-list.png")

        // Tap one of Tomorrow's rows: the scrub crosses midnight to it. A row
        // hugging the bottom edge "taps" without firing (the touch lands in
        // the home-indicator band — seen on iPad landscape), so scroll until
        // it sits clear of the edge first.
        let tomorrowRow = app.buttons.matching(identifier: "schedule-row-d1").firstMatch
        XCTAssert(tomorrowRow.waitForExistence(timeout: 5), "no Tomorrow rows in the schedule")
        var tries = 0
        while tomorrowRow.frame.maxY > app.windows.firstMatch.frame.maxY - 80, tries < 4 {
            app.swipeUp()
            sleep(1)
            tries += 1
        }
        tomorrowRow.tap()
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'TOMORROW'")).firstMatch.waitForExistence(timeout: 5),
                  "readout did not follow the cross-midnight scrub")
        app.swipeDown()
        sleep(1)
        save(app, "m42-scrub-midnight.png")

        // Return to now: the readout comes back to Today.
        app.buttons["Return to now"].firstMatch.tap()
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'TODAY'")).firstMatch.waitForExistence(timeout: 5),
                  "return-to-now did not restore the live readout")
    }

    // M4.3 design pass: favorites — the detail-header star files a station
    // under a Favorites group (My Location → Favorites → Recents → Near Me),
    // favorites/hero never repeat in Recents, swipe actions manage the groups
    // (current-detail spec §9), and the speed-unit setting rewrites a current
    // detail's readout.
    func testM43FavoritesSwipesAndSpeedUnits() throws {
        let app = XCUIApplication()
        // Deterministic Victoria fix; clean favorites/recents.
        app.launchArguments = ["-seedGate", "-resetRecents", "-resetFavorites",
                               "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // Star Friday Harbor from its detail (upper-right, back's mirror).
        openFridayHarbor(app)
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(star.waitForExistence(timeout: 5), "favorite star missing from detail header")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].waitForExistence(timeout: 5),
                  "star did not flip to favorited in the header")
        sleep(1)
        save(app, "m43-detail-star.png")

        // Back: a Favorites group holds it, and it does NOT repeat in Recents
        // (it was just visited — favorites win the dedupe).
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["RECENTS"].exists,
                       "a favorited station must not also render under Recents")

        // Visit a second station so Recents renders too — all four groups.
        openSearch(app, "deception")
        let port = app.staticTexts["Deception Pass State Park"].firstMatch
        XCTAssert(port.waitForExistence(timeout: 5))
        port.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["MY LOCATION"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)
        // M4.5: Recents is the last group — scroll down to it.
        let recentsLabel = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsLabel, in: app)
        sleep(1)
        save(app, "m43-favorites-group.png")

        // Swipe open the Recents row: red destructive Remove (spec §9).
        let parkRow = app.staticTexts["Deception Pass State Park"].firstMatch
        scrollTo(parkRow, in: app)
        parkRow.swipeLeft()
        XCTAssert(app.buttons["Remove"].waitForExistence(timeout: 5),
                  "trailing swipe did not reveal the Recents remove action")
        save(app, "m43-swipe.png")
        app.buttons["Remove"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["Deception Pass State Park"].exists,
                       "remove-from-recents left the row behind")

        // Swipe-unfavorite Friday Harbor (back near the top): it leaves
        // Favorites and re-files under Recents (spec §9 — a move, not a
        // deletion) — which now means the bottom of the list.
        app.swipeDown()
        app.swipeDown()
        let fridayRow = app.staticTexts["Friday Harbor"].firstMatch
        XCTAssert(fridayRow.waitForExistence(timeout: 5))
        fridayRow.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].waitForExistence(timeout: 5),
                  "trailing swipe did not reveal the favorites remove action")
        app.buttons["Unfavorite"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "unfavorite left the Favorites group behind")
        let recentsAgain = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsAgain, in: app)
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists,
                  "unfavorited station did not re-file to Recents")
        app.swipeDown()
        app.swipeDown()

        // Speed units: switch to km/h in Settings, the current detail follows.
        app.buttons["Settings"].tap()
        let kmh = app.buttons["km/h"]
        XCTAssert(kmh.waitForExistence(timeout: 5), "speed-unit switch missing from Settings")
        kmh.tap()
        sleep(1)
        save(app, "m43-settings-speed.png")
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "deception")
        let gate = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(gate.waitForExistence(timeout: 5))
        gate.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'km/h'")).firstMatch.waitForExistence(timeout: 5),
                  "current detail readout did not follow the km/h setting")
        // Leave the store on knots for the other tests.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        let kn = app.buttons["Knots"]
        XCTAssert(kn.waitForExistence(timeout: 5))
        kn.tap()
        app.buttons["Done"].tap()
    }

    // M4.3: the build-7 riding-dot bug — initial centering must happen at the
    // first layout, not the first magnet settle. Honest check: the very FIRST
    // scrub must move the centerline readout with the gesture (in build 7,
    // scrubTime stayed frozen until the settle recomputed everything, so the
    // dot floated off the curve). Screenshot lands mid-deceleration, before
    // any settle.
    func testM43FirstScrubDotRidesCurve() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openFridayHarbor(app)

        // First frame after appearance — no scrub, no settle yet.
        save(app, "m43-first-view.png")
        let readout = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d{1,2}:\\d{2} (AM|PM)$")).firstMatch
        XCTAssert(readout.waitForExistence(timeout: 5))
        let before = readout.label

        // The FIRST drag on a fresh detail: the readout must move during the
        // gesture itself, not only after the magnet settles.
        scrubStrip(app)
        save(app, "m43-first-scrub-fixed.png")  // mid-deceleration, pre-settle
        let after = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d{1,2}:\\d{2} (AM|PM)$")).firstMatch.label
        XCTAssertNotEqual(before, after,
                          "first scrub left the readout frozen — initial centering raced layout again")
    }

    // M4.3: the CHS pending card speaks plain language — held pending by the
    // network kill switch (no fit can start, honest offline stand-in).
    func testM43ChsPendingCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-chsResetModels", "-networkKillSwitch"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openSearch(app, "victoria")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Canadian tidal predictions download once'"))
            .firstMatch.waitForExistence(timeout: 10),
                  "pending card is missing the plain-language copy")
        sleep(1)
        save(app, "m43-chs-copy.png")
    }

    // M4.4: iPad split layout — regular width gets the web's ≥62rem shape
    // (styles.css): persistent sidebar (search + groups) beside the detail
    // pane, in both orientations. Skipped on iPhone, which keeps the stack.
    func testM44IPadSplit() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only layout test")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Pick a station"].waitForExistence(timeout: 5),
                  "detail placeholder missing beside the sidebar")
        openFridayHarbor(app)
        // The sidebar must still be on screen while the detail shows —
        // a split, not a push.
        XCTAssert(app.staticTexts["Slackwater"].exists, "sidebar gone — not a split layout")
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5))
        // A second pick replaces the detail (no stacking) — web sidebar behavior.
        openSearch(app, "deception")
        let gate = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(gate.waitForExistence(timeout: 5))
        gate.tap()
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 5),
                  "row tap did not replace the detail pane")
        sleep(5)  // header map tiles
        save(app, "m44-ipad-landscape.png")

        // M4.5 regular width: the FABs live in the sidebar column; the map
        // FAB swaps the detail pane to the map (replacing the shown detail),
        // flips to the list icon, and toggling back lands on the placeholder.
        app.buttons["Map"].firstMatch.tap()
        XCTAssert(app.otherElements["map-canvas"].waitForExistence(timeout: 5),
                  "map did not take over the detail pane")
        XCTAssert(app.buttons["List"].exists, "toggle FAB did not flip to the list icon")
        XCTAssert(app.buttons["Search"].exists, "search FAB missing while the map shows")
        sleep(4)  // map tiles
        save(app, "m45-ipad.png")
        app.buttons["List"].firstMatch.tap()
        XCTAssert(app.staticTexts["Pick a station"].waitForExistence(timeout: 5),
                  "toggle back did not land on the placeholder")

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssert(app.staticTexts["Slackwater"].exists, "portrait dropped the sidebar")
        save(app, "m44-ipad-portrait.png")
    }

    // M4.5 design pass: the floating toolbar (prototype NearMe.dc.html
    // showToggle) — search FAB bottom-left opens the bottom-input search with
    // the keyboard up; the X beside the input exits in one tap; the map FAB
    // toggles the surface in place and flips to the list icon (no header, no
    // close chrome); both FABs persist over the map.
    func testM45SearchFabAndMapToggle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // No top search bar on the list; both FABs present.
        XCTAssertFalse(app.textFields.firstMatch.exists, "top search bar must be gone")
        XCTAssert(app.buttons["Search"].exists)
        XCTAssert(app.buttons["Map"].exists)
        sleep(1)
        save(app, "m45-list-fabs.png")

        // Search FAB → bottom input, keyboard up (openSearch types with no
        // field tap), results fill the space above.
        openSearch(app, "friday")
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.waitForExistence(timeout: 5))
        XCTAssert(app.buttons["Close search"].exists, "X missing beside the input")
        sleep(1)
        save(app, "m45-search-open.png")

        // X beside the input: one tap back to the list, keyboard gone.
        closeSearch(app)
        XCTAssertFalse(app.textFields.firstMatch.exists, "X did not close search")

        // Map FAB: the surface swaps in place, the button becomes the list
        // icon, and no chrome sits over the map.
        app.buttons["Map"].tap()
        XCTAssert(app.otherElements["map-canvas"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["MAP"].exists, "map must carry no header")
        XCTAssert(app.buttons["List"].exists, "toggle did not flip to the list icon")
        sleep(4)  // tiles
        save(app, "m45-map-toggled.png")

        // The search FAB persists over the map and opens the same search.
        openSearch(app, "friday")
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close search"].firstMatch.tap()

        // Toggle back: list returns, the button is the map icon again.
        XCTAssert(app.buttons["List"].waitForExistence(timeout: 5))
        app.buttons["List"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.buttons["Map"].exists, "toggle did not flip back to the map icon")
    }

    // M47: a validated CHS current gate (Dodd Narrows) — pending copy in the
    // currents register, a REAL live 210-day wcsp1/wcdp1 fit (scoped to the
    // one gate via -chsFitOnly so the wait is one gate's fetch, ~2.5 min),
    // the full current-detail treatment with CHS provenance, then the
    // airplane-mode day-after relaunch on the stored model.
    func testM47DoddNarrowsPendingFitDetailOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels", "-seedGate", "-chsFitOnly", "chs-dodd-narrows"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // "dodd" matches ONLY the CHS gate — a broader query like "narrows"
        // also pulls NOAA current cards whose Flooding/Ebbing/SLACK labels
        // false-positive the fitted wait below.
        openSearch(app, "dodd")
        XCTAssert(app.staticTexts["Dodd Narrows"].firstMatch.waitForExistence(timeout: 5),
                  "search did not find Dodd Narrows")
        // Pending: identity + the honest currents message, no numbers.
        let pending = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'current predictions'")).firstMatch
        XCTAssert(pending.waitForExistence(timeout: 10), "currents pending copy missing")

        // The live fit lands and the card becomes a real current card:
        // a velocity phase word or the SLACK pill — numbers, not copy.
        // Scoped to the search overlay's ScrollView: the (accessibility-hidden
        // but still queryable) list behind it carries the same labels.
        let overlay = app.scrollViews.firstMatch
        let fitted = overlay.staticTexts.matching(
            NSPredicate(format: "label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK'")).firstMatch
        XCTAssert(fitted.waitForExistence(timeout: 480), "Dodd Narrows never fitted — IWLS unreachable?")
        sleep(1)
        save(app, "m47-gates-list.png")

        app.staticTexts["Dodd Narrows"].firstMatch.tap()
        // Full current-detail anatomy: the slack countdown and the CHS
        // provenance footer (device-computed, not CHS-published).
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        save(app, "m47-dodd-detail.png")

        // Airplane-mode day-after: the stored model predicts offline.
        app.terminate()
        app.launchArguments = ["-networkKillSwitch", "-nowOffsetDays", "1", "-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openSearch(app, "dodd")
        let offlineFitted = app.scrollViews.firstMatch.staticTexts.matching(
            NSPredicate(format: "label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK'")).firstMatch
        XCTAssert(offlineFitted.waitForExistence(timeout: 10), "stored current model did not survive relaunch")
        app.staticTexts["Dodd Narrows"].firstMatch.tap()
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.waitForExistence(timeout: 10))
        save(app, "m47-dodd-offline.png")
    }

    // M4.6: the derived gate (Malibu Rapids) — pending while its reference
    // port (Point Atkinson) is unfitted, held there by the network kill switch.
    func testM46MalibuPendingBeforeFit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-chsResetModels", "-networkKillSwitch"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openSearch(app, "malibu")
        XCTAssert(app.staticTexts["Malibu Rapids"].firstMatch.waitForExistence(timeout: 5),
                  "search did not find Malibu Rapids")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Canadian tidal predictions download once'"))
            .firstMatch.waitForExistence(timeout: 10),
                  "derived gate must show the CHS pending register before its reference is fitted")
    }

    // M4.6: after the reference port fits (live IWLS, like M3), the gate card
    // shows the phase pill + next slack, and the detail renders the dual-track
    // strip, slack rows with no speeds, and the derived provenance copy.
    func testM46MalibuDerivedGate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // M48: ONE tap. The gate always opens — showing the ⚠️ download
        // warning if its reference port (Point Atkinson) isn't fitted yet —
        // and opening it moves that port to the front of the queue, so the
        // page fills in live with no second tap and no back-and-forth.
        openSearch(app, "malibu")
        XCTAssert(app.staticTexts["Malibu Rapids"].firstMatch.waitForExistence(timeout: 5),
                  "search did not find Malibu Rapids")
        app.staticTexts["Malibu Rapids"].firstMatch.tap()
        XCTAssert(app.staticTexts["Malibu Rapids"].firstMatch.waitForExistence(timeout: 5),
                  "tapping the gate did not open a detail")
        // ~5 min ceiling: the in-flight station finishes, then the promoted
        // Point Atkinson runs.
        XCTAssert(app.staticTexts["TIDE AT POINT ATKINSON"].waitForExistence(timeout: 300),
                  "the open detail never filled in — Point Atkinson fit missing (IWLS unreachable?)")
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["TIDE AT POINT ATKINSON"].waitForExistence(timeout: 5),
                  "reference-port tide readout missing from the gate detail")
        XCTAssert(app.staticTexts["● SLACK"].firstMatch.waitForExistence(timeout: 5),
                  "slack rows missing from the schedule")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'speeds are not predicted'")).firstMatch.exists,
                  "the shape-only note is missing")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'cruising-community'")).firstMatch
            .waitForExistence(timeout: 5),
                  "derived provenance footer missing")
        // No knots anywhere: a derived gate never shows a speed. iPhone only —
        // the iPad split keeps the sidebar (and its NOAA "kn" cards) on screen
        // beside the detail, so the whole-hierarchy sweep would catch those.
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(app.staticTexts.matching(
                NSPredicate(format: "label MATCHES %@", "^\\d+\\.\\d+ kn$")).firstMatch.exists,
                           "a derived gate must never render a speed")
        }
        sleep(5)  // header map tiles
        save(app, "m46-malibu-detail.png")

        // Print today's rendered schedule times for the verification table.
        let labels = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d{2}:\\d{2}$")).allElementsBoundByIndex
        print("M46-SCHEDULE-TIMES: \(labels.compactMap { $0.exists ? $0.label : nil })")

        // The live card (PA fitted now): "Slack · time" line + the phase pill.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "malibu")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Slack ·'")).firstMatch.waitForExistence(timeout: 5),
                  "live gate card missing its next-slack line")
        sleep(1)
        save(app, "m46-malibu-card.png")
        closeSearch(app)

        // Map: the gate pins at the channel position. Pan north from the
        // Salish camera toward Jervis Inlet so the pin is on screen.
        app.buttons["Map"].tap()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 5))
        sleep(4)  // tiles
        // Malibu (50.16, -123.85) sits north-west of the camera — drag the
        // map content south-east to bring the pin into the frame's middle
        // (one full drag + one short one; two full drags left it at the edge).
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo:
                map.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.8)))
        sleep(1)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.35))
            .press(forDuration: 0.1, thenDragTo:
                map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.62)))
        sleep(1)
        sleep(2)
        save(app, "m46-malibu-map.png")
    }

    // M48: the offline-downloads system — the indicator beside the gear, the
    // manager it opens, the proximity-ordered queue, and the fix for the dead
    // tap: an unfitted station opens its detail with the ⚠️ explanation and
    // jumps to the front of the queue. Runs against LIVE IWLS from a clean
    // store (like M3/M47) — nothing here waits for a fit to land, only for the
    // queue and its UI, so it costs seconds, not the fit chain.
    func testM48DownloadsManagerAndQueueJump() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-chsResetModels",
                               "-fixLat", "48.4235", "-fixLon", "-123.3705"]  // Victoria
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // The indicator sits beside the gear, on the same line.
        let indicator = app.buttons["offline-status"].firstMatch
        XCTAssert(indicator.waitForExistence(timeout: 5), "no download indicator beside the gear")
        let gear = app.buttons["Settings"].firstMatch
        XCTAssert(gear.exists)
        XCTAssert(indicator.frame.maxX <= gear.frame.minX + 1, "indicator must sit beside the gear")
        XCTAssertEqual(indicator.frame.midY, gear.frame.midY, accuracy: 2,
                       "indicator must share the gear's row")
        sleep(3)  // let the first download start, so the state is 'downloading'
        save(app, "m48-indicator.png")

        // Tapping it opens the manager directly (not Settings).
        indicator.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5),
                  "the indicator did not open the downloads manager")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Downloading Canadian tidal and current predictions'"))
            .firstMatch.waitForExistence(timeout: 5),
                  "manager is missing the plain-register progress line")

        // Proximity order from the Victoria fix: Victoria, then Race Passage,
        // then Sooke — nearest-first, exactly as the queue sorts them.
        let rows = app.descendants(matching: .any)
        let victoria = rows["download-row-chs-victoria"].firstMatch
        let race = rows["download-row-chs-race-passage"].firstMatch
        let sooke = rows["download-row-chs-sooke"].firstMatch
        XCTAssert(victoria.waitForExistence(timeout: 5), "no per-station rows in the manager")
        XCTAssert(victoria.frame.minY < race.frame.minY, "queue is not proximity-ordered")
        XCTAssert(race.frame.minY < sooke.frame.minY, "queue is not proximity-ordered")
        sleep(1)
        save(app, "m48-downloads-manager.png")
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))

        // The dead tap, fixed: the farthest station in the catalogue is last in
        // the queue and has nothing to show — tapping it still opens a detail,
        // and that detail explains itself.
        openSearch(app, "weynton")
        let far = app.staticTexts["Weynton Passage"].firstMatch
        XCTAssert(far.waitForExistence(timeout: 5))
        far.tap()
        XCTAssert(app.staticTexts["No predictions yet"].waitForExistence(timeout: 5),
                  "tapping an unfitted station from search did not open the warning detail")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Canadian current predictions'")).firstMatch.exists,
                  "warning is missing the plain-register download line")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'works offline'")).firstMatch.exists,
                  "warning must say what to expect once it lands")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'first in line'")).firstMatch.exists,
                  "viewing must move the station to the front of the queue")
        sleep(2)  // header map tiles
        save(app, "m48-unfitted-detail.png")

        // And the promotion is visible in the manager: the station you opened
        // is at the top, badged, ahead of the nearer ones.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        app.buttons["offline-status"].firstMatch.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5))
        let promoted = app.descendants(matching: .any)["download-row-chs-weynton-passage"].firstMatch
        XCTAssert(promoted.waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["YOU OPENED"].firstMatch.exists,  // MonoLabel uppercases
                  "the promoted station is not marked in the manager")
        let stillQueued = app.descendants(matching: .any)["download-row-chs-sooke"].firstMatch
        XCTAssert(promoted.frame.minY < stillQueued.frame.minY,
                  "the viewed station did not jump ahead of the proximity order")
        sleep(1)
        save(app, "m48-queue-jump.png")
        app.buttons["Done"].tap()
    }

    // M48: the map needed no map-specific work — a pin tap goes through the
    // same open() as a row, so an unfitted station lands on the same warning
    // detail. Held unfitted by the kill switch, so this is deterministic.
    func testM48MapPinToUnfittedDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-chsResetModels", "-networkKillSwitch"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        app.buttons["Map"].tap()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 5))
        sleep(5)  // tiles

        // Same web-mercator math as testM4MapPinToDetail, on Race Passage.
        let frame = map.frame
        let world = 512.0 * pow(2.0, 7.35)  // SALISH_ZOOM
        func mercator(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
            let x = (lon + 180) / 360 * world
            let phi = lat * .pi / 180
            let y = (1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2 * world
            return (x, y)
        }
        let c = mercator(48.35, -123.05)        // SALISH_CENTER
        let p = mercator(48.3067, -123.5367)    // Race Passage
        let nx = (frame.midX + (p.x - c.x) - frame.minX) / frame.width
        let ny = (frame.midY + (p.y - c.y) - frame.minY) / frame.height
        map.coordinate(withNormalizedOffset: CGVector(dx: nx, dy: ny)).tap()

        XCTAssert(app.staticTexts["No predictions yet"].waitForExistence(timeout: 8),
                  "a map pin on an unfitted station must still open its detail")
        XCTAssert(app.staticTexts["Race Passage"].firstMatch.exists)
        // Offline: the established honest register, and no bogus ETA.
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'need a moment of signal'")).firstMatch.exists,
                  "offline warning must keep the moment-of-signal copy")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Nothing downloads without a connection'"))
            .firstMatch.exists)
    }

    /// All "HH:mm" labels on screen — chart annotations + schedule rows. The
    /// tide detail's set must be a subset of the paired view's merged set.
    private func clockLabels(_ app: XCUIApplication) -> Set<String> {
        let all = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d{2}:\\d{2}$")).allElementsBoundByIndex
        return Set(all.compactMap { $0.exists ? $0.label : nil })
    }

    /// All "N.N ft/m" height labels on screen.
    private func heightLabels(_ app: XCUIApplication) -> Set<String> {
        let all = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d+\\.\\d+ (ft|m)$")).allElementsBoundByIndex
        return Set(all.compactMap { $0.exists ? $0.label : nil })
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: shotDir + "/" + name))
    }
}
