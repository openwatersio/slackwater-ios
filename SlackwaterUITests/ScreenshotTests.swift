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

    /// The list's own scroll container. `app.swipeUp()` gestures at the centre
    /// of the whole app, which in the iPad split lands in the DETAIL pane and
    /// scrolls nothing — the sidebar list has to be swiped directly. Since M52
    /// the pane opens on a station, so "the first scroll view" is the detail's
    /// as often as the list's: go by identifier, and only then guess.
    private func listContainer(_ app: XCUIApplication) -> XCUIElement {
        let named = app.descendants(matching: .any)["station-list"].firstMatch
        if named.exists { return named }
        for query in [app.tables, app.collectionViews, app.scrollViews] {
            let el = query.firstMatch
            if el.exists { return el }
        }
        return app
    }

    /// Scroll the list until `el` is realized, hittable, and clear of the
    /// fixed FAB overlay pinned to the bottom of the sidebar/list (the same
    /// ~80pt exclusion already used inline for the schedule row below, "home
    /// indicator band" case). Bare `isHittable` alone is not enough for
    /// elements near the list's bottom — XCUITest counts an element hittable
    /// the moment any part of it is on-screen and unobscured by an ancestor's
    /// clipping, which can be true while it still sits directly under the
    /// FAB circles' own hit-test region: a swipe or tap aimed at it then
    /// silently lands on the FAB instead and nothing happens (confirmed by
    /// diagnostic frame dumps: at the old bare-isHittable stopping point the
    /// Recents row's bottom edge sat within 1pt of the FAB zone's top edge;
    /// one more swipe carried it clear by ~68pt and it stayed there — the
    /// list was genuinely bottomed out, not still scrolling).
    private func scrollTo(_ el: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while tries < 10 {
            if el.exists, el.isHittable, el.frame.maxY <= app.windows.firstMatch.frame.maxY - 80 {
                break
            }
            listContainer(app).swipeUp()
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
        sleep(1)
        save(app, "m1-search.png")
        // M53: "pass" matches 139 stations nationally and results are ranked by
        // DISTANCE, not name — Active Pass used to be first alphabetically and
        // is now eighth (Race Passage, then five San Juan passes, are nearer to
        // the Victoria fix). Scroll for both rather than assume the fold.
        for name in ["Active Pass", "Deception Pass (Narrows)"] {
            let card = app.staticTexts[name].firstMatch
            var tries = 0
            while !card.exists, tries < 8 { app.scrollViews.firstMatch.swipeUp(); tries += 1 }
            XCTAssert(card.exists, "search did not find \(name)")
        }
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
        // M53: scoped to Victoria. Unscoped, every launch also starts the
        // nine-station auto-fit set against live IWLS — minutes of paced
        // requests this test does not need, competing with the one fit it does.
        app.launchArguments = ["-chsResetModels", "-seedGate",
                               "-chsFitOnly", "chs-victoria"]  // clean first-run
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // Victoria is pending (or already mid-fit): identity + honest message, no numbers.
        openSearch(app, "victoria")
        let pending = app.descendants(matching: .any)["chs-pending-chs-victoria"].firstMatch
        XCTAssert(pending.waitForExistence(timeout: 10))
        sleep(1)
        save(app, "m3-pending.png")

        // Live IWLS fetch (10 polite requests) + JSCore fit. The card becomes
        // a navigable tide card when the model lands — it stops being copy and
        // shows numbers. (Cards are no longer buttons: since the M4.3 List
        // conversion, rows navigate via a hidden link.)
        // Scoped to the search overlay's ScrollView, like M47: the list behind
        // it is accessibility-hidden but still QUERYABLE, so an unscoped match
        // can pick up some other station's Rising/Falling and let the test walk
        // into a Victoria that is still downloading.
        let fitted = app.scrollViews.firstMatch.staticTexts.matching(
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
        let offlineFitted = app.scrollViews.firstMatch.staticTexts.matching(
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

    // Colour-and-form Task 4: the dot layer split into station-pins-current
    // (circle) and station-pins-tide (square). testM4MapPinToDetail above
    // only ever taps a `current`-kind pin (Deception Pass is a current
    // station) — this is the one test that proves the square/tide layer is
    // still wired to the same tap handler. Losing this coverage is exactly
    // the failure the split risked: the web port silently dropped tap
    // handling for one kind when its dot layer was split, and no test caught
    // it there either.
    func testM4TideSquarePinToDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        app.buttons["Map"].tap()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 5))
        sleep(5)  // let tiles (and Seascape, when reachable) come in
        let frame = map.frame
        let world = 512.0 * pow(2.0, 7.35)  // SALISH_ZOOM
        func mercator(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
            let x = (lon + 180) / 360 * world
            let phi = lat * .pi / 180
            let y = (1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2 * world
            return (x, y)
        }
        let c = mercator(48.35, -123.05)                 // SALISH_CENTER
        let p = mercator(48.48500061035156, -123.08300018310547)  // Kanaka Bay, NOAA tide
        let nx = (frame.midX + (p.x - c.x) - frame.minX) / frame.width
        let ny = (frame.midY + (p.y - c.y) - frame.minY) / frame.height
        map.coordinate(withNormalizedOffset: CGVector(dx: nx, dy: ny)).tap()

        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5),
                  "map pin tap did not open a station detail")
        XCTAssert(app.staticTexts["Kanaka Bay"].firstMatch.waitForExistence(timeout: 5))
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
        // Symmetry with the port-side guard above: if the row scope ever stops
        // matching, say so directly instead of reporting every port value as
        // "missing from paired view (has [])".
        XCTAssert(!gateTimes.isEmpty && !gateHeights.isEmpty,
                  "no schedule rows read from the gate detail")
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
        listContainer(app).swipeDown()
        listContainer(app).swipeDown()
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
        // Scroll to the ROW, not just the group label: how many rows Recents
        // has depends on what this simulator has downloaded, so the label can
        // land on the last visible line with the row below the fold.
        let refiled = app.staticTexts["Friday Harbor"].firstMatch
        scrollTo(refiled, in: app)
        XCTAssert(refiled.exists, "unfavorited station did not re-file to Recents")
        listContainer(app).swipeDown()
        listContainer(app).swipeDown()

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
        // M52: the pane opens on the first row, not the placeholder — the
        // placeholder is now only reachable by clearing the pane (map toggle).
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 10),
                  "regular width did not auto-select a station into the detail pane")
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
        // Pending: identity + the honest currents message, no numbers. By id
        // since M53 — the copy alone matches every undownloaded station.
        let pending = app.descendants(matching: .any)["chs-pending-chs-dodd-narrows"].firstMatch
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
        // provenance footer (device-computed, not CHS-published). M51: Dodd is
        // a 210-day gate, so the card above landed on its 60-day fast answer —
        // the final footer is the tell that the full model has since replaced
        // it (the fast answer's own footer says "60 of 210 days downloaded").
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.waitForExistence(timeout: 300))
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
        // M53: Point Atkinson is 100 km from the Victoria fallback, so it is
        // NOT in the auto-fit set — opening the gate is what downloads it,
        // which is the behaviour under test. Scoped so that is the only fit
        // in flight (see testM3 for why unscoped live tests fight each other).
        app.launchArguments = ["-seedGate", "-chsFitOnly", "chs-point-atkinson"]
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
        // Scoped to the rows for the same reason clockLabels is: unscoped, this
        // table would quietly include iPad sidebar card readings.
        print("M46-SCHEDULE-TIMES: \(clockLabels(app).sorted())")

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

        // Proximity order from the Victoria fix: Victoria, then Race Passage
        // (18 km), then Porlier Pass (68 km) — nearest-first, exactly as the
        // queue sorts them. M53: the list is the DOWNLOAD SET, so Sooke (30 km
        // and outside the six nearest ports) is deliberately not in it.
        let rows = app.descendants(matching: .any)
        let victoria = rows["download-row-chs-victoria"].firstMatch
        let race = rows["download-row-chs-race-passage"].firstMatch
        let porlier = rows["download-row-chs-porlier-pass"].firstMatch
        XCTAssert(victoria.waitForExistence(timeout: 5), "no per-station rows in the manager")
        XCTAssert(victoria.frame.minY < race.frame.minY, "queue is not proximity-ordered")
        XCTAssert(race.frame.minY < porlier.frame.minY, "queue is not proximity-ordered")
        XCTAssertFalse(rows["download-row-chs-sooke"].firstMatch.exists,
                       "the manager is listing the catalog again, not the download set")
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
        let stillQueued = app.descendants(matching: .any)["download-row-chs-porlier-pass"].firstMatch
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
        // M53: the camera is put ON Race Passage rather than aimed at it from
        // the wide Salish view. At 195 bundled stations a finger-sized box over
        // that pin held one dot; at 3,125 it holds several, and "the nearest
        // dot to the tap" stopped being the one the test meant. The fix is the
        // fix — the discovery map now opens on it — plus a station-scale zoom.
        app.launchArguments = ["-seedGate", "-chsResetModels", "-networkKillSwitch",
                               "-fixLat", "48.3067", "-fixLon", "-123.5367", "-mapZoom", "11"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        app.buttons["Map"].tap()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 5))
        sleep(5)  // tiles

        // Dead centre: the camera is on the station, so the pin is the middle.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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

    // MARK: - M50: station identity presentation

    /// The subtitle bug Bryan found on the iPad: "7.6 mi. Sse" — a compass
    /// point title-cased by station-corrections' cleanName, and statute miles
    /// on a card whose distance pill speaks nm.
    func testM50RegionSubtitleIsNauticalAndShouts() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        openSearch(app, "discovery island")
        XCTAssert(app.staticTexts["6.6 nm SSE"].firstMatch.waitForExistence(timeout: 5),
                  "the fixed subtitle is missing — expected nautical miles and SSE")
        XCTAssertFalse(app.staticTexts["7.6 mi. Sse"].exists,
                       "the broken subtitle is still rendering")
        XCTAssert(app.staticTexts["3.0 nm NE"].firstMatch.exists,
                  "the sibling station's already-correct subtitle changed")
        sleep(1)
        save(app, "m50-subtitle-fixed.png")
        closeSearch(app)
    }

    /// Two "Discovery Island" cards used to sit in Near Me looking identical.
    /// Now: one entry, and the matching stations behind the chooser.
    func testM50MatchingStationChooser() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // M53: the fix moved from Victoria to Discovery Island itself. At 195
        // bundled stations the two namesakes were both inside Victoria's Near
        // Me; at 3,125 the six nearest a Victoria fix are all harbour gauges
        // inside 5 km, which is what Near Me is FOR and not what this test is
        // about. Standing at the station is the deterministic way to put a
        // collided name in the list.
        app.launchArguments = ["-seedGate", "-resetRecents", "-resetFavorites",
                               "-fixLat", "48.452", "-fixLon", "-123.155"]  // Discovery Island
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["NEAR ME"].waitForExistence(timeout: 10))

        // One entry, not two: the nearer Discovery Island renders, the farther
        // one is behind the chooser.
        // Scoped to the LIST: at regular width the detail pane auto-opens on the
        // first row (M52), so an unscoped count also picks up its header title.
        let cards = listContainer(app).staticTexts
            .matching(NSPredicate(format: "label == %@", "Discovery Island"))
        XCTAssertEqual(cards.count, 1, "same-named stations must render as one entry")
        XCTAssert(app.staticTexts["3.0 nm NE"].firstMatch.exists, "the nearest one is the entry")
        XCTAssertFalse(app.staticTexts["6.6 nm SSE"].exists,
                       "the farther namesake must not render as its own card")

        let chooserButton = app.buttons["matching-stations"].firstMatch
        XCTAssert(chooserButton.waitForExistence(timeout: 5),
                  "no matching-station affordance on a collided name")
        XCTAssert(app.staticTexts["2 matching stations"].firstMatch.exists)
        chooserButton.tap()

        // The chooser: both stations, each with what it measures and how far.
        XCTAssert(app.otherElements["station-chooser"].waitForExistence(timeout: 5)
                  || app.staticTexts["3.0 nm NE"].firstMatch.waitForExistence(timeout: 5),
                  "the chooser sheet did not open")
        XCTAssert(app.staticTexts["6.6 nm SSE"].firstMatch.waitForExistence(timeout: 5),
                  "the chooser must offer the station the list collapsed")
        XCTAssert(app.staticTexts["CURRENT · NOAA"].firstMatch.exists,  // MonoLabel uppercases
                  "a chooser row must say what it measures and whose data it is")
        sleep(1)
        save(app, "m50-station-chooser.png")

        // Picking the collapsed one opens it — it is not lost, just quiet.
        app.staticTexts["6.6 nm SSE"].firstMatch.tap()
        XCTAssert(app.staticTexts["Discovery Island"].firstMatch.waitForExistence(timeout: 8))
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8),
                  "the chooser pick did not open a station detail")
    }

    /// "Deception Pas…" — the compact Recents row starved the name column so
    /// two different stations truncated to the same string.
    func testM50RecentsNamesFit() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-resetRecents", "-resetFavorites",
                               "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        for name in ["Deception Pass (Narrows)", "Deception Pass State Park"] {
            openSearch(app, "deception")
            let card = app.staticTexts[name].firstMatch
            XCTAssert(card.waitForExistence(timeout: 5), "\(name) missing from search")
            card.tap()
            XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8))
            app.buttons["detail-back"].firstMatch.tap()
            XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        }

        let recents = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recents, in: app)
        let long = app.staticTexts["Deception Pass State Park"].firstMatch
        scrollTo(long, in: app)
        XCTAssert(long.exists, "the visited station is not in Recents")
        // The sidebar reflows asynchronously while the CHS pending card above
        // Recents updates its status line, and `XCUIElement.frame` re-queries
        // the live layout on EVERY access — so a filter that touches frames
        // across that reflow compares coordinates from two different layouts.
        // That is how CI watched a Near Me reading 550pt away "share the
        // name's line" (PR #22). Wait for the row to hold still, then take
        // ONE snapshot per element and assert on the snapshots.
        var nameFrame = long.frame
        for _ in 0..<20 {
            usleep(250_000)
            let again = long.frame
            if again == nameFrame { break }
            nameFrame = again
        }
        // The name owns the row's width now. Truncated, its frame collapsed to
        // the ~150pt column left over beside the reading (iPad sidebar).
        XCTAssert(nameFrame.width > 165,
                  "the Recents name column is still starved: \(nameFrame.width)pt")
        // And the reading sits below the name, not beside it.
        let readings = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^-?\\d+\\.\\d+ (ft|m|kn)$"))
            .allElementsBoundByIndex
            // Only this row's — the Near Me cards above carry readings too.
            .compactMap { el -> CGRect? in
                guard el.exists else { return nil }
                let f = el.frame  // one read; every comparison below uses it
                return f.minY >= nameFrame.minY && f.maxY <= nameFrame.maxY + 34 ? f : nil
            }
        XCTAssertFalse(readings.isEmpty, "the Recents row lost its reading")
        for frame in readings {
            XCTAssert(frame.minY >= nameFrame.maxY - 1,
                      "the reading still shares the name's line: \(frame)")
        }
        sleep(1)
        save(app, "m50-recents-untruncated.png")
    }

    /// Build 13, iPad: opening a second station of the SAME kind kept the
    /// first one's chart and map — same destination type at the same depth is
    /// the same SwiftUI identity, so @State survived. Discovery Island has no
    /// paired reference port and Deception Pass (Narrows) does, so the paired
    /// station's tide rows are the tell: they come from the @State timeline,
    /// and a stale one has none.
    func testM50DetailSwapsBetweenSameKindStations() throws {
        // Split layout only: on iPhone the detail covers the search FAB, so a
        // second station is always reached through a pop first.
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only split-layout swap")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        openSearch(app, "discovery island")
        app.staticTexts["3.0 nm NE"].firstMatch.tap()
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["↑ HIGH"].firstMatch.exists,
                       "an unpaired current station must show no tide rows")

        // Second station, same kind — in the split layout this replaces the
        // detail pane without a pop.
        openSearch(app, "deception pass (n")
        app.staticTexts["Deception Pass (Narrows)"].firstMatch.tap()
        XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch
            .waitForExistence(timeout: 8))
        XCTAssert(app.staticTexts["↑ HIGH"].firstMatch.waitForExistence(timeout: 8),
                  "the detail kept the previous station's timeline — no tide rows for a paired gate")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'the nearby reference port'")).firstMatch.exists,
                  "the paired-tide honesty line is missing")
        sleep(4)  // header map tiles for the new station
        save(app, "m50-detail-swap.png")
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - M51: the fast answer

    /// Time-to-first-usable, printed into the test log. These four numbers —
    /// nearest tide port, 60-day gate, 210-day gate provisional, same gate
    /// final — are what M51 exists to move, so they get measured, not guessed.
    private func report(_ what: String, _ from: Date) {
        print("M51 TTFU · \(what): \(String(format: "%.1f", -from.timeIntervalSinceNow)) s")
    }

    /// (a) the nearest tide port — unchanged by M51 at its validated 60 d, and
    /// the baseline the gate numbers are read against.
    func testM51NearestTidePortTimeToFirstUsable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels", "-seedGate", "-chsFitOnly", "chs-victoria",
                               "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        let t0 = Date()
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openSearch(app, "victoria")
        // M53: by station id, not by copy. Every undownloaded Canadian station
        // says "Canadian tidal predictions", and "victoria" matches several.
        let pending = app.descendants(matching: .any)["chs-pending-chs-victoria"].firstMatch
        XCTAssert(pending.waitForExistence(timeout: 15), "no CHS Victoria card in the results")
        var waited = 0
        while pending.exists, waited < 240 { sleep(2); waited += 2 }
        XCTAssertFalse(pending.exists, "Victoria never fitted — IWLS unreachable?")
        report("nearest tide port (60 d)", t0)
        XCTAssert(app.scrollViews.firstMatch.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d+\\.\\d+ (ft|m)$")).firstMatch.exists,
                  "a fitted port must show a height, not just lose its pending copy")
    }

    /// (b) a gate validated at 60 d: one short fetch, straight to FINAL. The
    /// negative is the point — this station must never wear the amber fast
    /// answer, because its first fit already meets the full bar.
    func testM51ValidatedGateReachesFinalWithNoProvisionalStage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels", "-seedGate", "-chsFitOnly", "chs-active-pass",
                               "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        let t0 = Date()
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openSearch(app, "active pass")
        let overlay = app.scrollViews.firstMatch
        let fitted = overlay.staticTexts.matching(
            NSPredicate(format: "label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK'")).firstMatch
        XCTAssert(fitted.waitForExistence(timeout: 240), "Active Pass never fitted — IWLS unreachable?")
        report("nearest 60-day gate → FINAL", t0)

        XCTAssertFalse(app.descendants(matching: .any)["provisional-badge"].firstMatch.exists,
                       "a gate validated at 60 d must go straight to final — no provisional marking")
        app.staticTexts["Active Pass"].firstMatch.tap()
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'can be off by up to'")).firstMatch.exists,
                       "no fast-answer warning belongs on a final model")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.exists,
                  "final models keep the ordinary CHS provenance footer")
    }

    /// (c) + (d): a 210-day gate shows its fast answer at ~60 d, says by how
    /// much it can be wrong AT THIS PASS, then refines in place under an open
    /// page — the amber marking clearing is the transition to final.
    func testM51ProvisionalGateShowsFastAnswerThenRefines() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels", "-seedGate", "-chsFitOnly", "chs-dodd-narrows",
                               "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        let t0 = Date()
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openSearch(app, "dodd")

        // The fast answer, in the list: the ⚠️ badge and a tilde'd reading, and
        // that is ALL — the amber prose that used to ride the card measured
        // 1.03:1 against the palest station gradient (M52). The number it can
        // be off by lives on the detail, where the amber card can afford it.
        let badge = app.descendants(matching: .any)["provisional-badge"].firstMatch
        XCTAssert(badge.waitForExistence(timeout: 240),
                  "Dodd Narrows never published its 60-day fast answer")
        report("nearest 210-day gate → PROVISIONAL", t0)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'FAST ANSWER'")).firstMatch.exists,
                       "the low-contrast amber badge must be gone from the list card")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '~'")).firstMatch.exists,
                  "the tilde stays: the reading itself must still say it is not exact")
        sleep(1)
        save(app, "m51-provisional-list.png")
        save(app, "m52-provisional-card-icon.png")

        // …and in the detail: the ⚠️ family, with the real number in it.
        app.staticTexts["Dodd Narrows"].firstMatch.tap()
        let warning = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'slack at Dodd Narrows can be off by up to ~35 min'")).firstMatch
        XCTAssert(warning.waitForExistence(timeout: 10),
                  "the provisional detail is missing its warning, naming THIS pass's measured error")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Stay connected'")).firstMatch.exists,
                  "the warning must say what to do about it, and roughly how long")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '60 of 210 days downloaded'")).firstMatch.exists,
                  "the footer must say how much of the model is actually here")
        sleep(2)  // header map tiles
        save(app, "m51-provisional-detail.png")

        // The refinement lands under the open page: same station, final model.
        var waited = 0
        while warning.exists, waited < 300 { sleep(5); waited += 5 }
        XCTAssertFalse(warning.exists, "the fast answer never refined to the full model")
        report("nearest 210-day gate → FINAL", t0)
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.exists, "the refined page is still a live detail")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.exists,
                  "the refined page carries the ordinary final footer")
        sleep(1)
        save(app, "m51-refined.png")
    }

    /// The manager, mid-run: one gate usable-but-refining beside the ordinary
    /// waiting/downloading rows — provisional and final are different words.
    func testM51ManagerShowsProvisionalApartFromFinal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels", "-seedGate",
                               "-chsFitOnly", "chs-dodd-narrows,chs-victoria,chs-active-pass",
                               "-fixLat", "49.1344", "-fixLon", "-123.8171"]  // at Dodd
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        app.buttons["offline-status"].firstMatch.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5))
        let dodd = app.descendants(matching: .any)["download-row-chs-dodd-narrows"].firstMatch
        XCTAssert(dodd.waitForExistence(timeout: 10))
        var waited = 0
        while !dodd.label.contains("Refining"), waited < 300 { sleep(5); waited += 5 }
        XCTAssert(dodd.label.contains("Refining"),
                  "the manager never showed the usable-but-unfinished state")
        XCTAssert(dodd.label.contains("FAST ANSWER ±35 MIN"),
                  "the manager must say how good the fast answer is, not just that there is one")
        sleep(1)
        save(app, "m51-manager.png")
        app.buttons["Done"].tap()
    }

    /// Opening a station while a long gate is mid-download used to cost up to
    /// ~2.5 min: promotion only took effect at the next STATION boundary. Now
    /// the running job steps aside at the next CHUNK — and comes back to what
    /// it already fetched.
    func testM51PromotionInterruptsAnInFlightDownload() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-chsResetModels", "-seedGate",
                               "-chsFitOnly", "chs-dodd-narrows,chs-tofino",
                               "-fixLat", "49.1344", "-fixLon", "-123.8171"]  // Dodd is nearest
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // Dodd (210 d, ~2.5 min of chunks) is in flight.
        app.buttons["offline-status"].firstMatch.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5))
        let dodd = app.descendants(matching: .any)["download-row-chs-dodd-narrows"].firstMatch
        XCTAssert(dodd.waitForExistence(timeout: 10))
        XCTAssert(dodd.label.contains("Downloading"), "the nearest gate should be the one in flight")
        app.buttons["Done"].tap()

        // Open the far tide port — the promotion the queue has to honour NOW.
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "tofino")
        app.staticTexts["Tofino"].firstMatch.tap()
        XCTAssert(app.staticTexts["No predictions yet"].waitForExistence(timeout: 10))
        let t0 = Date()
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        app.buttons["offline-status"].firstMatch.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5))

        // Within one chunk (2.5 s of pacing, plus the round trip), the gate has
        // stepped aside and the station you opened is downloading.
        let tofino = app.descendants(matching: .any)["download-row-chs-tofino"].firstMatch
        var waited = 0
        while !tofino.label.contains("Downloading"), waited < 30 { sleep(1); waited += 1 }
        XCTAssert(tofino.label.contains("Downloading"),
                  "opening a station did not interrupt the gate in flight (waited \(waited) s)")
        XCTAssert(app.descendants(matching: .any)["download-row-chs-dodd-narrows"]
            .firstMatch.label.contains("Waiting"), "the yielded gate must go back to waiting, not fail")
        print("M51 interrupt: promoted station started \(String(format: "%.1f", -t0.timeIntervalSinceNow)) s after the open")

        // And it resumes: once the promoted port is done the gate carries on
        // from its cached chunks (never re-fetching them — ChsProvisionalTests).
        waited = 0
        while !dodd.label.contains("Downloading"), waited < 120 { sleep(2); waited += 2 }
        XCTAssert(dodd.label.contains("Downloading"), "the yielded gate never resumed")
        app.buttons["Done"].tap()
    }

    // MARK: - M52: device-testing fixes (build 15 → 16)

    /// Drag from the very left edge — the interactive pop, not a content swipe.
    /// Anchored to the map header's own band (near its bottom, not its
    /// screen-midpoint fraction) when a header is on screen: the hero-crop
    /// spec (2026-08-03) shrank the header to a third, and a start point
    /// close to the top of the screen — under the status bar / Dynamic
    /// Island — silently loses the touch to the system rather than the app's
    /// edge-pop gesture (verified by sweeping dy: 0.05 never pops, 0.15
    /// always does, on a 141pt-tall header). Low in the header stays clear of
    /// that zone at any Dynamic Type size. On the root list (no header, e.g.
    /// the no-op check) fall back to the same safe screen fraction.
    private func edgeSwipeBack(_ app: XCUIApplication) {
        let header = app.otherElements["detail-map-header"].firstMatch
        let edge: XCUICoordinate
        let across: XCUICoordinate
        if header.exists {
            edge = header.coordinate(withNormalizedOffset: CGVector(dx: 0.001, dy: 0.9))
            across = header.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9))
        } else {
            edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.001, dy: 0.15))
            across = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15))
        }
        edge.press(forDuration: 0.02, thenDragTo: across,
                   withVelocity: .default, thenHoldForDuration: 0)
    }

    /// The reading the strip's centerline is parked on ("1:42 PM").
    private func scrubClock(_ app: XCUIApplication) -> String? {
        app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d{1,2}:\\d{2} (AM|PM)$"))
            .firstMatch.label
    }

    /// (2) The nav bar is hidden app-wide for the map-hero chrome, and UIKit
    /// disables `interactivePopGestureRecognizer` whenever it is — so on iPhone
    /// there was no way back but the button. Both halves are asserted, because
    /// the risk in re-arming the gesture is that it eats the strip's scrub: a
    /// drag from the EDGE pops, a drag INSIDE the strip scrubs and stays put.
    /// Kill-switched, so the CHS page is deterministically the waiting page.
    func testM52EdgeSwipeBackOnEveryDetailType() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("iPhone-only: regular width is a split, with nothing to pop")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-chsResetModels", "-networkKillSwitch"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // (a) tide detail — and first, the gesture that must NOT pop.
        openFridayHarbor(app)
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5))
        let before = scrubClock(app)
        scrubStrip(app)
        sleep(1)
        XCTAssert(app.otherElements["timeline-strip"].exists,
                  "a drag inside the strip popped the detail — the edge gesture is too greedy")
        XCTAssertNotEqual(scrubClock(app), before,
                          "a drag inside the strip no longer scrubs")

        edgeSwipeBack(app)
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5),
                  "edge swipe did not pop the tide detail")

        // (b) current detail.
        openSearch(app, "deception")
        let current = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(current.waitForExistence(timeout: 5))
        current.tap()
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 10))
        edgeSwipeBack(app)
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5),
                  "edge swipe did not pop the current detail")

        // (c) the CHS waiting page — no chart at all, held there by the kill switch.
        openSearch(app, "victoria")
        app.staticTexts["Victoria"].firstMatch.tap()
        XCTAssert(app.staticTexts["No predictions yet"].waitForExistence(timeout: 10))
        edgeSwipeBack(app)
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5),
                  "edge swipe did not pop the CHS waiting page")

        // (d) a derived gate — Malibu Rapids, likewise pending offline.
        openSearch(app, "malibu")
        app.staticTexts["Malibu Rapids"].firstMatch.tap()
        XCTAssert(app.staticTexts["No predictions yet"].waitForExistence(timeout: 10))
        edgeSwipeBack(app)
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5),
                  "edge swipe did not pop the derived-gate detail")

        // And the root must not pop itself into a wedged navigation controller.
        edgeSwipeBack(app)
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5),
                  "an edge swipe on the list must be a no-op")
    }

    /// (3) Return-to-now used to live in the header's top-right row and shoved
    /// the favourite star sideways the moment you scrubbed. It has its own slot
    /// now — below the hero, in the scrub card's readout row, hard right beside
    /// the star — so appearing and disappearing moves nothing.
    func testM52ReturnToNowHasItsOwnFixedSlot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openFridayHarbor(app)
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5))

        let star = app.buttons["detail-favorite"].firstMatch
        let back = app.buttons["detail-back"].firstMatch
        XCTAssert(star.waitForExistence(timeout: 5))
        let starBefore = star.frame, backBefore = back.frame
        let now = app.buttons["detail-return-now"].firstMatch
        XCTAssertFalse(now.exists, "return-to-now must not show before a scrub")

        scrubStrip(app)
        sleep(1)
        XCTAssert(now.waitForExistence(timeout: 5), "scrubbing did not reveal return-to-now")
        XCTAssertEqual(star.frame.minX, starBefore.minX, accuracy: 0.5,
                       "return-to-now still shifts the star")
        XCTAssertEqual(star.frame.minY, starBefore.minY, accuracy: 0.5)
        XCTAssertEqual(back.frame.minX, backBefore.minX, accuracy: 0.5,
                       "return-to-now must not move the back button either")

        // Its own slot: below the star, in the card's readout row, hard
        // right — the hero-crop-and-scrub-order spec (2026-08-03) moved it
        // out of the hero's overlay into the card beside NEXT LOW, so it now
        // lives BELOW the hero rather than inside it.
        let header = app.otherElements["detail-map-header"].firstMatch
        XCTAssert(now.frame.minY > star.frame.maxY, "return-to-now is not below the star")
        XCTAssert(now.frame.minY >= header.frame.maxY - 1,
                 "return-to-now must live below the hero, in the card's readout row")
        XCTAssertEqual(now.frame.maxX, star.frame.maxX, accuracy: 1,
                       "return-to-now must share the star's right margin")
        save(app, "m52-return-now-fixed.png")

        // And it still does its job — back to now, and gone again.
        now.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["detail-return-now"].firstMatch.exists,
                       "return-to-now did not clear after returning to now")
        XCTAssertEqual(star.frame.minX, starBefore.minX, accuracy: 0.5,
                       "the star moved when return-to-now went away")
    }

    /// (4) iPad: a fresh launch opens the first row in the detail pane instead
    /// of the "Pick a station" invitation. Only when nothing is selected — a
    /// pick already made is never overridden.
    func testM52IPadAutoSelectsTheFirstStation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("regular-width behaviour")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 10),
                  "the detail pane did not open a station on launch")
        XCTAssertFalse(app.staticTexts["Pick a station"].exists,
                       "the placeholder is still what a fresh iPad launch shows")
        // The sidebar is intact — this is a selection, not a push.
        XCTAssert(app.staticTexts["Slackwater"].exists)
        sleep(5)  // header map tiles
        save(app, "m52-ipad-autoselect.png")

        // Don't fight the user: a deliberate pick stands, and coming back to
        // the list does not re-run the auto-select.
        openSearch(app, "friday")
        app.staticTexts["Friday Harbor"].firstMatch.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists,
                  "the auto-selection overrode a deliberate pick")
    }

    /// All "HH:mm" labels on screen — chart annotations + schedule rows. The
    /// tide detail's set must be a subset of the paired view's merged set.
    /// The schedule rows' accessibility labels — NOT the whole screen.
    ///
    /// Scoping matters on iPad and only on iPad. The split-view sidebar renders
    /// live station cards, and since layout A put the reading on the card's
    /// right they emit `X.X ft` strings that match the same regexes the schedule
    /// rows do. A caller that scrapes twice and diffs then blames the paired
    /// pane for a sidebar label: between two scrapes the Recents list reorders
    /// (the station just visited moves in), so a reading present in the first
    /// read is simply gone from the second. That produced two consecutive CI
    /// failures on "missing" values of 4.6 ft and 4.8 ft — both sidebar
    /// readings, never in the pane at all — while the other values drifted
    /// between runs (6.7→6.6, 5.1→5.2) the way a live reading does and a tide
    /// row does not. It passes on iPhone, which has no sidebar, and passes in
    /// isolation on iPad, where the sidebar state differs.
    ///
    /// Each row is ONE element, not a container: `TimelineStrip` applies
    /// `.accessibilityElement(children: .combine)`, so a row's children are
    /// merged into its own label and `row.staticTexts` finds nothing. Hence we
    /// read each row's label and pull the values out of it, rather than
    /// querying descendants — querying would return an empty set and every
    /// caller's comparison loop would pass vacuously.
    private func scheduleRowLabels(_ app: XCUIApplication) -> [String] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'schedule-row-d'"))
            .allElementsBoundByIndex
            .compactMap { $0.exists ? $0.label : nil }
    }

    /// Every substring of the schedule rows matching `pattern`. Unanchored by
    /// design: the row label is a combined string like "05:48 2.2 ft ↑ HIGH",
    /// so the anchored `^…$` these helpers used when each value was its own
    /// element would now match nothing.
    private func scheduleValues(_ app: XCUIApplication, _ pattern: String) -> Set<String> {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found: Set<String> = []
        for label in scheduleRowLabels(app) {
            let ns = label as NSString
            for m in re.matches(in: label, range: NSRange(location: 0, length: ns.length)) {
                found.insert(ns.substring(with: m.range))
            }
        }
        return found
    }

    /// All "HH:MM" clock labels in the schedule rows.
    private func clockLabels(_ app: XCUIApplication) -> Set<String> {
        scheduleValues(app, "\\b\\d{2}:\\d{2}\\b")
    }

    /// All "N.N ft/m" height labels in the schedule rows.
    private func heightLabels(_ app: XCUIApplication) -> Set<String> {
        scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: shotDir + "/" + name))
    }

    // MARK: - M53: the US and Canada

    /// The whole point of M53: a station 4,000 km from the Salish Sea is
    /// searchable, opens, and draws a real curve from bundled NOAA harmonics —
    /// no download, no signal needed, same screen as Friday Harbor.
    func testM53UsEastCoastStationRendersACurve() throws {
        let app = XCUIApplication()
        // Airplane mode: whatever renders here is bundled, not fetched.
        app.launchArguments = ["-seedGate", "-networkKillSwitch"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        openSearch(app, "boston")
        let boston = app.staticTexts["Boston"].firstMatch
        XCTAssert(boston.waitForExistence(timeout: 5), "Boston is not in the bundle")
        boston.tap()

        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 10),
                  "an east-coast station did not open a real detail")
        XCTAssert(app.staticTexts["MA"].firstMatch.exists,
                  "the region line fell back to the Salish gazetteer")
        // A curve, not an empty chart: heights and clock times both render, and
        // Boston's range is metres — the numbers are the station's own.
        XCTAssertFalse(heightLabels(app).isEmpty, "no height readings on the Boston detail")
        XCTAssertGreaterThanOrEqual(clockLabels(app).count, 3, "no schedule on the Boston detail")
        sleep(3)  // header map tiles — the continental land floor, offline
        save(app, "m53-us-station.png")

        // And the west coast, through the same path.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "san francisco")
        let sf = app.staticTexts["San Francisco (Golden Gate)"].firstMatch
        XCTAssert(sf.waitForExistence(timeout: 5), "San Francisco is not in the bundle")
        sf.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 10))
    }

    /// Search at 3,125 stations: bounded, nearest-first, and honest about what
    /// it is not showing.
    func testM53SearchAtNationalScale() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-networkKillSwitch"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        // "port" matches several hundred stations nationally.
        openSearch(app, "port")
        XCTAssert(app.descendants(matching: .any)["search-truncated"].firstMatch
                    .waitForExistence(timeout: 5),
                  "a query matching hundreds of stations must say it truncated")
        // Nearest-first: from the Victoria fallback the top of the list is
        // local water, not an alphabetical trip to Alaska.
        XCTAssert(app.staticTexts["Portage Inlet"].firstMatch.exists ||
                  app.staticTexts["Port Townsend"].firstMatch.exists,
                  "results are not ranked by distance from the fix")
        sleep(1)
        save(app, "m53-search-scale.png")

        // Narrowing removes the truncation notice — the list is complete again.
        app.textFields.firstMatch.typeText(" townsend")
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any)["search-truncated"].firstMatch.exists,
                       "a narrow query must not claim to be truncated")
        closeSearch(app)
    }

    /// The map at continental scale. 3,125 pins is a grey smear without
    /// clustering; this walks the camera out to the whole country, times the
    /// gestures, and checks the map is still a map afterwards.
    func testM53MapAtContinentalZoom() throws {
        let app = XCUIApplication()
        // z3.2 over the Salish camera longitude: the west coast from Mexico to
        // Alaska, offline, with everything the bundle knows on it. The camera
        // is stated rather than pinched into place — five synthesised pinches
        // land somewhere no assertion can name.
        app.launchArguments = ["-seedGate", "-networkKillSwitch", "-openMap", "-mapZoom", "3.2"]
        app.launch()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 15))
        sleep(6)  // the coarse land tiles, then the clusters
        save(app, "m53-map-continental.png")

        // Then the interaction cost, timed: zooming the clustered source at the
        // scale where an unclustered one is 3,125 separate dots.
        let start = Date.now
        for _ in 0..<5 { map.pinch(withScale: 1.6, velocity: 2) }
        let gestures = Date.now.timeIntervalSince(start)
        print(String(format: "M53 map · 5 pinches at z3.2 over %d pins: %.2f s", 3125, gestures))
        XCTAssertLessThan(gestures, 20, "zooming a 3,125-pin map should not take 20 seconds")

        // Still responsive and still a map afterwards.
        XCTAssert(app.buttons["List"].exists, "the map chrome stopped responding")
        XCTAssert(app.buttons["Search"].exists)
        app.buttons["List"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
    }

    /// A Canadian station outside the auto-fit set: visible, searchable, and
    /// honest — it is not queued, and it says opening it is what downloads it.
    /// Held offline so the state is deterministic.
    func testM53CanadianStationOnDemand() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-chsResetModels", "-networkKillSwitch"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        openSearch(app, "halifax")
        let halifax = app.staticTexts["Halifax"].firstMatch
        XCTAssert(halifax.waitForExistence(timeout: 5),
                  "a Canadian station 4,400 km away must still be findable offline")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Open to download'")).firstMatch.exists,
                  "an unqueued station must not claim to be queued")
        _ = halifax
        // The card, by id — see testM53OnDemandCanadianStationFitsWhenOpened.
        app.descendants(matching: .any)["chs-pending-chs-halifax"].firstMatch.tap()

        XCTAssert(app.staticTexts["No predictions yet"].waitForExistence(timeout: 8),
                  "opening an undownloaded Canadian station must explain itself")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'works offline'")).firstMatch.exists)
        sleep(3)  // header map tiles: the Atlantic coast, from the bundled floor
        save(app, "m53-canada-ondemand.png")

        // Opening it put it in the download set, at the front.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        app.buttons["offline-status"].firstMatch.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any)["download-row-chs-halifax"].firstMatch
        XCTAssert(row.waitForExistence(timeout: 5),
                  "opening a station outside the auto-fit set did not add it to the queue")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'searchable everywhere'")).firstMatch.exists,
                  "the manager must say the rest of Canada is on demand, not missing")
        app.buttons["Done"].tap()
    }

    /// FULL PLAN — live IWLS. The other half of on-demand: a Canadian station
    /// nobody auto-downloaded fits on the device when you open it, and the page
    /// fills in underneath you.
    func testM53OnDemandCanadianStationFitsWhenOpened() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate", "-chsResetModels"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        openSearch(app, "halifax")
        // Deliberately UNSCOPED: the point is that Halifax is not in the
        // auto-fit set, so the set is downloading in the background throughout.
        let pending = app.descendants(matching: .any)["chs-pending-chs-halifax"].firstMatch
        XCTAssert(pending.waitForExistence(timeout: 15),
                  "it should start with nothing — nothing auto-downloads Nova Scotia")
        // Tap the CARD, not the name: at regular width the sidebar behind the
        // search overlay is accessibility-hidden but still queryable, so
        // `staticTexts["Halifax"].firstMatch` can resolve to the hidden one.
        pending.tap()
        XCTAssert(app.staticTexts["No predictions yet"].waitForExistence(timeout: 20))

        // Promotion yields the running auto-fit job at its next chunk (~2.5 s),
        // then one 60-day tide fit: ~30 s of paced requests.
        let start = Date.now
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 180),
                  "an opened Canadian station never fitted")
        print(String(format: "M53 on-demand fit of Halifax: %.0f s", Date.now.timeIntervalSince(start)))
        XCTAssertFalse(heightLabels(app).isEmpty, "fitted, but no numbers")
        save(app, "m53-canada-fitted.png")
    }
}
