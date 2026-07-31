// Slackwater — GPL v3. Walks the M1–M4 surfaces and saves screenshots.
// Doubles as the smoke check that every interaction actually responds.
// M4 launch flow: the app opens on the first-run gate, then the list — tests
// seed or reset that state explicitly (-seedGate / -resetGate) because a
// UserDefaults value passed as a launch argument would mask in-app writes.
import XCTest

final class ScreenshotTests: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["M1_SHOT_DIR"] ?? "/tmp"

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
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8))
        from.press(forDuration: 0.3, thenDragTo: to)
        sleep(1)
        save(app, "m1-detail-scrubbed.png")

        // Back to the station list; clear the "friday" query.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        if app.buttons["xmark.circle.fill"].firstMatch.exists {
            app.buttons["xmark.circle.fill"].firstMatch.tap()
        }
        sleep(1)
        save(app, "m1-list.png")

        // Search mid-query: name + region substring both match.
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("pass")
        sleep(1)
        save(app, "m1-search.png")
        let clear = app.buttons["xmark.circle.fill"].firstMatch
        if clear.exists { clear.tap() } else { field.typeText(XCUIKeyboardKey.delete.rawValue) }

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

    /// Search "friday" → tap the tide card → detail; clears the query on the
    /// way in so the list is clean when the caller navigates back.
    private func openFridayHarbor(_ app: XCUIApplication) {
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("friday")
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
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("deception")
        let card = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 5))  // MonoLabel uppercases
        sleep(2)
        save(app, "m2-current-detail.png")

        // Scrub: pan the combined tide+current strip (it sits lower on the
        // gate detail — port tide readout above it), release.
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.88))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.88))
        from.press(forDuration: 0.3, thenDragTo: to)
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
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("victoria")
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
        let field2 = app.textFields.firstMatch
        field2.tap()
        field2.typeText("victoria")
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

    // M4: first-run gate — the search bypass lands on the fully usable list,
    // and the choice sticks across relaunch. (The Use-My-Location path needs
    // the system permission dialog; exercised manually via simctl privacy.)
    func testM4Gate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGate"]
        app.launch()

        XCTAssert(app.staticTexts["See tides near you"].waitForExistence(timeout: 10))
        XCTAssert(app.buttons["Use My Location"].exists)
        save(app, "m4-ftue-gate.png")
        app.buttons["Or search for a harbor, bay, or channel."].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Friday Harbor"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
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
        XCTAssert(app.staticTexts["MAP"].waitForExistence(timeout: 5))
        sleep(5)  // let tiles (and Seascape, when reachable) come in
        save(app, "m41-map-zoom.png")

        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 5))
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
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("deception")
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

        // Visit a station; it must appear under Recents on return.
        openFridayHarbor(app)
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        if app.buttons["xmark.circle.fill"].firstMatch.exists {
            app.buttons["xmark.circle.fill"].firstMatch.tap()
        }
        XCTAssert(app.staticTexts["RECENTS"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        sleep(2)
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
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
            .press(forDuration: 0.3, thenDragTo:
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)))
        sleep(1)
        save(app, "m41-scrubber-moon.png")

        // The map header carries the current-station detail too.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        if app.buttons["xmark.circle.fill"].firstMatch.exists {
            app.buttons["xmark.circle.fill"].firstMatch.tap()
        }
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("deception")
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
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.8))
            .press(forDuration: 0.3, thenDragTo:
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.8)))
        sleep(1)
        XCTAssert(app.buttons["Return to now"].waitForExistence(timeout: 5),
                  "return-to-now affordance missing after scrubbing away")
        save(app, "m42-scrub-center.png")

        // Multi-day list, day-grouped.
        app.swipeUp()
        sleep(1)
        save(app, "m42-multiday-list.png")

        // Tap one of Tomorrow's rows: the scrub crosses midnight to it.
        let tomorrowRow = app.buttons.matching(identifier: "schedule-row-d1").firstMatch
        XCTAssert(tomorrowRow.waitForExistence(timeout: 5), "no Tomorrow rows in the schedule")
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
        if app.buttons["xmark.circle.fill"].firstMatch.exists {
            app.buttons["xmark.circle.fill"].firstMatch.tap()
        }
        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["RECENTS"].exists,
                       "a favorited station must not also render under Recents")

        // Visit a second station so Recents renders too — all four groups.
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("deception")
        let port = app.staticTexts["Deception Pass State Park"].firstMatch
        XCTAssert(port.waitForExistence(timeout: 5))
        port.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        if app.buttons["xmark.circle.fill"].firstMatch.exists {
            app.buttons["xmark.circle.fill"].firstMatch.tap()
        }
        XCTAssert(app.staticTexts["MY LOCATION"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].exists)
        XCTAssert(app.staticTexts["RECENTS"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["NEAR ME"].exists)
        sleep(1)
        save(app, "m43-favorites-group.png")

        // Swipe open the Recents row: red destructive Remove (spec §9).
        app.staticTexts["Deception Pass State Park"].firstMatch.swipeLeft()
        XCTAssert(app.buttons["Remove"].waitForExistence(timeout: 5),
                  "trailing swipe did not reveal the Recents remove action")
        save(app, "m43-swipe.png")
        app.buttons["Remove"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["Deception Pass State Park"].exists,
                       "remove-from-recents left the row behind")

        // Swipe-unfavorite Friday Harbor: it leaves Favorites and re-files
        // under Recents (spec §9 — a move, not a deletion).
        app.staticTexts["Friday Harbor"].firstMatch.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].waitForExistence(timeout: 5),
                  "trailing swipe did not reveal the favorites remove action")
        app.buttons["Unfavorite"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "unfavorite left the Favorites group behind")
        XCTAssert(app.staticTexts["RECENTS"].waitForExistence(timeout: 5),
                  "unfavorited station did not re-file to Recents")
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)

        // Speed units: switch to km/h in Settings, the current detail follows.
        app.buttons["Settings"].tap()
        let kmh = app.buttons["km/h"]
        XCTAssert(kmh.waitForExistence(timeout: 5), "speed-unit switch missing from Settings")
        kmh.tap()
        sleep(1)
        save(app, "m43-settings-speed.png")
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        let field2 = app.textFields.firstMatch
        field2.tap()
        field2.typeText("deception")
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
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
            .press(forDuration: 0.3, thenDragTo:
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)))
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
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("victoria")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Canadian tidal predictions download once'"))
            .firstMatch.waitForExistence(timeout: 10),
                  "pending card is missing the plain-language copy")
        sleep(1)
        save(app, "m43-chs-copy.png")
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
