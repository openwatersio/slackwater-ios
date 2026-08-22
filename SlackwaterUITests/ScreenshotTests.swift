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

    /// The standard preamble: launch with `args`, wait for the list. Tests
    /// whose first screen is not the list (the FTUE gate, -openMap) and
    /// mid-test relaunches on an existing app stay inline.
    private func launch(_ args: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        return app
    }

    /// The live-IWLS / on-device-fit tests (minutes each) skip themselves
    /// outside `./scripts/test.sh --full`, which sets
    /// TEST_RUNNER_SLACKWATER_FULL=1 — xcodebuild strips the prefix and sets
    /// the rest on this UI-test runner process, the same route M1_SHOT_DIR
    /// rides above.
    private func skipUnlessFull() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SLACKWATER_FULL"] == nil,
                      "live-IWLS test — run ./scripts/test.sh --full")
    }

    func testM1Walkthrough() throws {
        // M4: launches on the list — when located it ranks by distance, so
        // reach Friday Harbor through search (deterministic either way).
        let app = launch("-seedGate")

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
        // The sheet's two fixed statements, asserted on the way past. This used
        // to be testM4Settings — its own launch, its own Settings round trip,
        // for two strings that every caller of this helper already has on
        // screen. M1Walkthrough alone opens the sheet four times.
        XCTAssert(app.staticTexts["Not for navigation."].exists,
                  "the settings sheet lost its disclaimer")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'OpenStreetMap'")).firstMatch.exists,
                  "the settings sheet lost its map attribution")
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

    /// #95 part 1: the readout says how fast the water is moving and how big
    /// this tide is — rate of rise on the direction line, a Range block beside
    /// the next-turn readout. Friday Harbor reads small; the point is the
    /// figures exist at every station, so Ile Haute's 32 ft can't hide.
    func testTideReadoutShowsRateAndRange() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        openFridayHarbor(app)
        let rate = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'ft/hr'")).firstMatch
        XCTAssert(rate.waitForExistence(timeout: 10), "no rate-of-rise readout")
        let range = app.staticTexts.matching(
            NSPredicate(format: "label ==[c] 'range'")).firstMatch
        XCTAssert(range.exists, "no Range block in the readout")
        save(app, "tide-readout-rate-range.png")
    }

    /// #95: the tide fill carries |dh/dt| on an absolute ramp. The strip must
    /// still draw — the rate stops replaced the fixed gradient, and an empty
    /// stops array would render a hollow track (this repo's blank-chart
    /// failure mode). The two shots are the review artifact: Friday Harbor
    /// sits low on the ramp, Avonmouth (Severn, 13.7 ft/hr peak) near the top
    /// — different pictures at last.
    func testTideRateRampDrawsOnQuietAndExtremeStations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.waitForExistence(timeout: 10))
        let quiet = inkFraction(strip)
        XCTAssert(quiet > 0.05, "tide strip drew nothing — ink \(quiet)")
        save(app, "tide-ramp-friday-harbor.png")

        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "avonmouth")
        let card = app.staticTexts["Avonmouth"].firstMatch
        XCTAssert(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(strip.waitForExistence(timeout: 10))
        let severn = inkFraction(strip)
        XCTAssert(severn > 0.05, "Avonmouth strip drew nothing — ink \(severn)")
        save(app, "tide-ramp-avonmouth.png")
    }

    /// The range bar heads the schedule card on every scrubable detail and says
    /// what span the list below it covers; tapping it opens the picker, and
    /// picking a date moves the window with the bar following.
    ///
    /// The bar-exists-and-states-a-span case used to be its own test and its own
    /// app launch. It is the first three lines of this one — a launch costs ~6 s
    /// and this test already had to wait for the same element to read `before`.
    func testPickingADateMovesTheWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))

        openFridayHarbor(app)
        let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
        XCTAssert(bar.waitForExistence(timeout: 10), "no range bar above the schedule")
        XCTAssert(bar.label.contains("–"), "the bar states a span, got '\(bar.label)'")
        let before = bar.label

        bar.tap()
        let picker = app.descendants(matching: .any)["week-picker"].firstMatch
        XCTAssert(picker.waitForExistence(timeout: 5))

        // The graphical DatePicker's forward-month button, then a day cell.
        app.buttons["Next Month"].firstMatch.tap()
        app.collectionViews.buttons.element(boundBy: 10).tap()
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()

        XCTAssertNotEqual(bar.label, before, "the bar must follow the anchor")
        XCTAssert(app.staticTexts["not this week"].waitForExistence(timeout: 5))

        // The centerline has to move WITH the window. It does not follow on its
        // own — the strip's x/time conversions are exact inverses, so a
        // programmatic scroll to an off-window `scrubTime` reads straight back
        // as the same off-window time and the strip draws blank. The
        // observable proof is this button: parking the centerline on the picked
        // week puts `scrubTime` far from now, and return-to-now is what shows
        // when it is. Without it there is no way back to today at all — the
        // range bar's "not this week" is a label, not a control.
        XCTAssert(app.buttons["detail-return-now"].firstMatch.waitForExistence(timeout: 5),
                  "picking a future week left the centerline on today: no return-to-now")

        // And the chart has to actually DRAW. The assertion above passes on a
        // blank strip — it did, for a whole review round: every readout, label
        // and schedule row was right for the picked week while the canvas
        // rendered nothing, because the window narrows when the anchor leaves
        // today and the scroll view kept its old width. Nothing inside the
        // strip is an accessibility element (it is all one `Canvas`), so ink
        // coverage is what a test can see.
        let ink = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(ink > 0.05, "the strip drew nothing after the pick — ink \(ink)")
        save(app, "picker-week-moved.png")

        // Back the other way, which is the same resize in reverse: today's
        // window is the WIDER one (it alone carries the 48h look-back), so a
        // fix that only handled the shrink would blank the strip on the way
        // home. "Today" is in the schedule's day column only when the anchor is
        // today — it is absent for the whole September week above.
        app.buttons["detail-return-now"].firstMatch.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5),
                  "return-to-now did not bring the window back to today")
        let homeInk = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(homeInk > 0.05, "the strip drew nothing back on today — ink \(homeInk)")
    }

    /// The share of an element's pixels that differ from its most common
    /// colour — "is anything drawn here". Measured on this strip: 0.008 blank
    /// (centerline, riding dot and the ft axis, all SwiftUI overlay ON TOP of
    /// the canvas), 0.13 drawn. The 0.05 threshold sits in the order of
    /// magnitude between them, so it needs no per-device tuning.
    private func inkFraction(_ element: XCUIElement) -> Double {
        guard let cg = element.screenshot().image.cgImage else { return 0 }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var counts: [UInt32: Int] = [:]
        for i in stride(from: 0, to: px.count, by: 4) {
            counts[UInt32(px[i]) << 16 | UInt32(px[i + 1]) << 8 | UInt32(px[i + 2]), default: 0] += 1
        }
        guard let bg = counts.max(by: { $0.value < $1.value })?.key else { return 0 }
        let r = Int(bg >> 16), g = Int((bg >> 8) & 0xFF), b = Int(bg & 0xFF)
        var ink = 0
        for i in stride(from: 0, to: px.count, by: 4)
        where max(abs(Int(px[i]) - r), abs(Int(px[i + 1]) - g), abs(Int(px[i + 2]) - b)) > 24 {
            ink += 1
        }
        return Double(ink) / Double(w * h)
    }

    // M2: current stations join the list; walk into Deception Pass and scrub
    // the signed velocity curve.
    func testM2Currents() throws {
        let app = launch("-seedGate")
        sleep(2)
        save(app, "m2-list-mixed.png")

        // Search finds the current station; its detail is the signed curve.
        openSearch(app, "deception")
        let card = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 5))  // MonoLabel uppercases

        // Scrub: pan the combined tide+current strip, release.
        scrubStrip(app)
        sleep(1)
        save(app, "m2-current-scrubbed.png")
    }

    // M3: Canadian (CHS) stations — pending state, a REAL end-to-end fit
    // against live IWLS, then the airplane-mode day-after relaunch. One test,
    // in order, because the offline half depends on the fit half's stored model.
    func testM3ChsPendingFitOffline() throws {
        try skipUnlessFull()
        // M53: scoped to Victoria. Unscoped, every launch also starts the
        // nine-station auto-fit set against live IWLS — minutes of paced
        // requests this test does not need, competing with the one fit it does.
        let app = launch("-chsResetModels", "-seedGate",
                         "-chsFitOnly", "chs-victoria")  // clean first-run

        // Victoria is pending (or already mid-fit): identity + honest message, no numbers.
        openSearch(app, "victoria")
        let pending = app.descendants(matching: .any)["chs-pending-chs-victoria"].firstMatch
        XCTAssert(pending.waitForExistence(timeout: 10))

        // Live IWLS fetch (10 polite requests) + JSCore fit. The card becomes
        // a navigable tide card when the model lands — it stops being copy and
        // shows numbers. (Cards are no longer buttons: since the M4.3 List
        // conversion, rows navigate via a hidden link.)
        // Scoped to the search overlay's ScrollView, like M47: the list behind
        // it is accessibility-hidden but still QUERYABLE, so an unscoped match
        // can pick up some other station's Rising/Falling and let the test walk
        // into a Victoria that is still downloading. Scoping to a ScrollView was
        // not enough: `app.scrollViews.firstMatch` resolves to whichever scroll
        // view the query walks first, which is the list BEHIND the overlay, so
        // the wait returned on some other station's card and the test opened a
        // Victoria with no model — "No predictions yet", four assertions down.
        // The pending card carrying Victoria's own id is the unambiguous signal:
        // it exists while the fit is outstanding and goes away when it lands.
        XCTAssert(pending.waitForNonExistence(timeout: 300), "Victoria never fitted — IWLS unreachable?")
        sleep(1)
        app.staticTexts["Victoria"].firstMatch.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        // The provenance marking (device-computed vs authoritative-harmonic).
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.waitForExistence(timeout: 5))

        // Airplane-mode day-after: relaunch offline, clock shifted to tomorrow.
        app.terminate()
        app.launchArguments = ["-networkKillSwitch", "-nowOffsetDays", "1", "-seedGate"]
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        openSearch(app, "victoria")
        // Victoria-scoped for the same reason as the online leg above: a stored
        // model means the card is never pending again, and an unscoped
        // Rising/Falling would happily match the list behind the overlay.
        let offlinePending = app.descendants(matching: .any)["chs-pending-chs-victoria"].firstMatch
        XCTAssertFalse(offlinePending.waitForExistence(timeout: 3),
                       "stored model did not survive relaunch — Victoria is pending again")
        app.staticTexts["Victoria"].firstMatch.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["⤒ HIGH"].firstMatch.waitForExistence(timeout: 5)
                  || app.staticTexts["⤓ LOW"].firstMatch.waitForExistence(timeout: 5))
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
    // pin tap opens the station's detail. Two cases, one per pin layer:
    // colour-and-form Task 4 split the dots into station-pins-current (circle,
    // Deception Pass) and station-pins-tide (square, Kanaka Bay), and the web
    // port silently dropped tap handling for one kind when it split — so both
    // layers must prove they reach the same tap handler. The pin's screen
    // point is pure web-mercator math from the fixed camera
    // (center 48.35,-123.05 · zoom 7.35 · 512pt world tiles — MapScreen's
    // SALISH constants; the styler re-asserts them after style load).
    func testM4MapPinToDetail() throws {
        for (lat, lon, name) in [
            (48.40618896484375, -122.64311981201172, "Deception Pass (Narrows)"),  // current → circle
            (48.48500061035156, -123.08300018310547, "Kanaka Bay"),                // NOAA tide → square
        ] {
            // World coverage (Task 5): the map's opening camera now follows a
            // real fix, then the last-opened station, before SALISH_CENTER —
            // and `tapPin`'s mercator math below assumes the camera IS
            // SALISH_CENTER. Without `-resetRecents`, a station recorded by an
            // earlier test in this run (UserDefaults persists across launches
            // in the same simulator) reliably steals the camera and every tap
            // below lands on the wrong pin.
            let app = launch("-seedGate", "-resetRecents")
            app.buttons["Map"].tap()
            let map = app.otherElements["map-canvas"].firstMatch
            XCTAssert(map.waitForExistence(timeout: 5))
            // M4.5: no header, no X — the toggle FAB (now the list icon) is
            // the way back, and the search FAB persists over the map.
            XCTAssertFalse(app.staticTexts["MAP"].exists, "map must carry no header chrome")
            XCTAssert(app.buttons["List"].exists, "toggle FAB did not flip to the list icon")
            XCTAssert(app.buttons["Search"].exists, "search FAB missing over the map")
            sleep(5)  // let tiles (and Seascape, when reachable) come in
            save(app, "m41-map-zoom.png")
            tapPin(map, lat, lon)
            XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5),
                      "map pin tap did not open a station detail")
            XCTAssert(app.staticTexts[name].firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    /// Tap the pin at (lat, lon) on the fixed Salish camera, by mercator math.
    private func tapPin(_ map: XCUIElement, _ lat: Double, _ lon: Double) {
        let world = 512.0 * pow(2.0, 7.35)  // SALISH_ZOOM
        func mercator(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
            let x = (lon + 180) / 360 * world
            let phi = lat * .pi / 180
            let y = (1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2 * world
            return (x, y)
        }
        let frame = map.frame
        let c = mercator(48.35, -123.05)  // SALISH_CENTER
        let p = mercator(lat, lon)
        let nx = (frame.midX + (p.x - c.x) - frame.minX) / frame.width
        let ny = (frame.midY + (p.y - c.y) - frame.minY) / frame.height
        map.coordinate(withNormalizedOffset: CGVector(dx: nx, dy: ny)).tap()
    }

    // M4 (split-scrubbers): a gate detail shows no tide — the port's numbers
    // live on the port's own detail, one tap through the quiet link.
    func testM4TideAtPortLink() throws {
        let app = launch("-seedGate")

        openSearch(app, "deception")
        let gate = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(gate.waitForExistence(timeout: 5))
        gate.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))

        // Nothing tide-shaped on the gate detail.
        XCTAssertFalse(app.staticTexts["TIDE AT DECEPTION PASS STATE PARK"].exists,
                       "the paired tide readout is retired")
        // Two calls, not one `&&`: an `&&` only fails when BOTH row kinds
        // leak, so a single stray HIGH (or LOW) row would pass silently.
        XCTAssertFalse(app.staticTexts["⤒ HIGH"].firstMatch.exists,
                       "port tide rows must not appear in a gate schedule")
        XCTAssertFalse(app.staticTexts["⤓ LOW"].firstMatch.exists,
                       "port tide rows must not appear in a gate schedule")
        // The slack window is the new next-slack detail.
        XCTAssert(app.descendants(matching: .any).matching(identifier: "slack-window")
            .firstMatch.waitForExistence(timeout: 5),
                  "slack window missing under Next slack")
        sleep(1)
        save(app, "m4-gate-detail.png")

        // The link opens the port's own detail with its schedule. Tide rows
        // are the primary tell, checked FIRST: a gate schedule can never show
        // HIGH/LOW (split-scrubbers retired that pairing), so their presence
        // is unambiguous proof navigation actually happened. The port's name
        // is checked second and only as a station-identity confirmation — on
        // iPad the sidebar's always-visible Recents section can carry the
        // exact same station name whether or not the tap navigated (bit us:
        // an exact-text existence check on the name alone false-positived
        // there against a stale Recents row while the pane was still showing
        // the gate).
        let link = app.descendants(matching: .any).matching(identifier: "tide-at-port").firstMatch
        XCTAssert(link.waitForExistence(timeout: 5), "tide-at-port link missing")
        link.tap()
        XCTAssert(app.staticTexts["⤒ HIGH"].firstMatch.waitForExistence(timeout: 8)
                  || app.staticTexts["⤓ LOW"].firstMatch.waitForExistence(timeout: 8),
                  "port detail shows its own tide schedule")
        XCTAssert(app.staticTexts["Deception Pass State Park"].firstMatch.exists,
                  "the link did not open the reference port's detail")
    }

    // M4.1 design pass: the regrouped list — My Location hero (nm pill, 3-dp
    // coords, no match-grade sentence), Recents after a visit, Near Me, and
    // nothing else (no catalog section, no units pill).
    func testM41GroupedListAndRecents() throws {
        // Deterministic Victoria fix via the -fixLat/-fixLon hook. Favorites
        // reset too: this test asserts group ORDER from a clean list, so its
        // launch args enforce that — not the goodwill of every earlier test
        // on the simulator (a leaked favorite pushed RECENTS past the iPad
        // sidebar's bounded scroll, 2026-08-08).
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
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
        // Both labels realized (tall screens / short lists): direct order
        // check. The sidebar reflows as CHS pending cards above update, so
        // read both frames together and wait them out (settled — see
        // testM50RecentsNamesFit) rather than reading each live.
        if near.exists {
            let f = settled { [near.frame, recentsLabel.frame] }
            XCTAssert(f[0].minY < f[1].minY,
                      "Recents must render below Near Me")
        }
    }

    // M4.1: the detail header is the station map with the title overlaid, the
    // day header carries the sun times, and the scrubber wears the moon
    // with its phase name.
    func testM41DetailMapHeaderSunMoon() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 5),
                  "map header missing from tide detail")
        XCTAssert(app.descendants(matching: .any).matching(identifier: "day-sun-d0")
            .firstMatch.waitForExistence(timeout: 5),
                  "sun times missing from the schedule day header")
        XCTAssertFalse(app.staticTexts["☀ RISE"].firstMatch.exists,
                       "sun rows have moved to the day header — none in the schedule")
        let phaseNames = "New Moon|Waxing Crescent|First Quarter|Waxing Gibbous|Full Moon|Waning Gibbous|Last Quarter|Waning Crescent"
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", phaseNames)).firstMatch.exists,
                  "moon phase name missing from the scrub readout")
        sleep(6)  // let the header map tiles come in
        save(app, "m41-detail-mapheader.png")

        // The map header carries the current-station detail too.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "deception")
        let gate = app.staticTexts["Deception Pass (Narrows)"].firstMatch
        XCTAssert(gate.waitForExistence(timeout: 5))
        gate.tap()
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 5),
                  "map header missing from current detail")
        XCTAssert(app.descendants(matching: .any).matching(identifier: "day-sun-d0")
            .firstMatch.waitForExistence(timeout: 5),
                  "sun times missing from the current-station day header")
        XCTAssertFalse(app.staticTexts["☀ RISE"].firstMatch.exists,
                       "sun rows have moved to the day header — none in the current-station schedule")
    }

    // M4.1: location denied — the amber card sits in the My Location slot
    // (NearMe.dc.html "unavailable"), above Near Me ranked from the fallback.
    func testM41DeniedSlot() throws {
        let app = launch("-seedGate", "-resetRecents", "-locDenied")
        XCTAssert(app.staticTexts["Location unavailable"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Go to Settings"].exists)
        XCTAssertFalse(app.staticTexts["MY LOCATION"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)
    }

    // M4.2: the continuous scrub — a fixed centerline with the multi-day strip
    // panning underneath. Scrubbing across midnight lands on the next day's
    // events; the schedule shows several days under day headers; a row tap
    // scrubs cross-day; return-to-now comes home.
    func testM42ContinuousScrubAcrossMidnight() throws {
        let app = launch("-seedGate")
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

        // Down the multi-day list. (One swipe first: schedule-row-d1 may not
        // be realized until it scrolls near the fold — the loop below only
        // clears the home-indicator band once the row exists.)
        app.swipeUp()

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
        // The when-row shows only the date now ("AUG 8") — TODAY/TOMORROW went
        // with the 2026-08-07 when-row redesign (the strip's day headers carry
        // the relative day). Follow the scrub by the date flipping to tomorrow.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US")
        fmt.dateFormat = "MMM d"
        let tomorrow = fmt.string(from: Date(timeIntervalSinceNow: 86400)).uppercased()
        let today = fmt.string(from: Date()).uppercased()
        XCTAssert(app.staticTexts[tomorrow].firstMatch.waitForExistence(timeout: 5),
                  "readout did not follow the cross-midnight scrub")
        app.swipeDown()

        // Return to now: the readout comes back to today's date.
        app.buttons["Return to now"].firstMatch.tap()
        XCTAssert(app.staticTexts[today].firstMatch.waitForExistence(timeout: 5),
                  "return-to-now did not restore the live readout")
    }

    /// A station that hasn't downloaded yet can still be favorited from its
    /// detail. Fresh-install bug (2026-08-08): the waiting page's star wrote
    /// "current:chs-…" while the catalog keys CHS gates bare, so the favorite
    /// was a phantom id — the star lit, and no Favorites group ever appeared.
    /// The sharp assertion is the FAVORITES section label itself: it only
    /// renders when a favorite id RESOLVES, so the phantom leaves it absent.
    func testFavoritePendingChsGateFromDetail() throws {
        // Fit only Victoria, so Dodd Narrows deterministically stays the
        // pending ⚠️ waiting page (the M46 scoping pattern).
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-chsResetModels", "-chsFitOnly", "chs-victoria",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "dodd")
        let gate = app.staticTexts["Dodd Narrows"].firstMatch
        XCTAssert(gate.waitForExistence(timeout: 5), "search did not find Dodd Narrows")
        gate.tap()

        // The pending detail still carries the header star — tap it.
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(star.waitForExistence(timeout: 5), "favorite star missing from the waiting detail")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].waitForExistence(timeout: 5),
                  "star did not flip to favorited on the waiting detail")

        // Back to the list: the favorite must RESOLVE — a Favorites group
        // with the gate in it, not a phantom id and no group at all.
        app.buttons["detail-back"].firstMatch.tap()
        // iPhone closes search with the push; the iPad sidebar keeps it open.
        if app.buttons["Close search"].firstMatch.exists { closeSearch(app) }
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5),
                  "favoriting a pending CHS gate produced no Favorites group — the star wrote an id the list cannot resolve")
        let row = app.staticTexts["Dodd Narrows"].firstMatch
        XCTAssert(row.exists, "the favorited pending gate is missing from the Favorites group")

        // Leave the simulator as found: swipe-unfavorite the row so later
        // tests that assume a clean favorites store aren't ambushed.
        row.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].waitForExistence(timeout: 5))
        app.buttons["Unfavorite"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "cleanup unfavorite left the Favorites group behind")
    }

    // M4.3 design pass: favorites — the detail-header star files a station
    // under a Favorites group (My Location → Favorites → Recents → Near Me),
    // favorites/hero never repeat in Recents, swipe actions manage the groups
    // (current-detail spec §9), and the speed-unit setting rewrites a current
    // detail's readout.
    func testM43FavoritesSwipesAndSpeedUnits() throws {
        // Deterministic Victoria fix; clean favorites/recents.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        // Star Friday Harbor from its detail (upper-right, back's mirror).
        openFridayHarbor(app)
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(star.waitForExistence(timeout: 5), "favorite star missing from detail header")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].waitForExistence(timeout: 5),
                  "star did not flip to favorited in the header")

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

        // Swipe open the Recents row: red destructive Remove (spec §9).
        let parkRow = app.staticTexts["Deception Pass State Park"].firstMatch
        scrollTo(parkRow, in: app)
        parkRow.swipeLeft()
        XCTAssert(app.buttons["Remove"].waitForExistence(timeout: 5),
                  "trailing swipe did not reveal the Recents remove action")
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
        let app = launch("-seedGate")
        openFridayHarbor(app)

        // First frame after appearance — no scrub, no settle yet.
        let readout = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d{1,2}:\\d{2} (AM|PM)$")).firstMatch
        XCTAssert(readout.waitForExistence(timeout: 5))
        let before = scrubClock(app)

        // The FIRST drag on a fresh detail: the readout must move during the
        // gesture itself (read mid-deceleration, pre-settle), not only after
        // the magnet settles.
        scrubStrip(app)
        XCTAssertNotEqual(before, scrubClock(app),
                          "first scrub left the readout frozen — initial centering raced layout again")
    }

    // M4.3 + M4.6: the CHS pending card speaks plain language — held pending by
    // the network kill switch (no fit can start, honest offline stand-in). Both
    // station kinds in one launch: a plain CHS tide port (Victoria) and a
    // DERIVED gate (Malibu Rapids), which is pending for a different reason —
    // its reference port, Point Atkinson, is the thing that is unfitted. They
    // asserted the same string under identical launch args in two tests and
    // two cold launches.
    func testChsPendingCopy() throws {
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch")
        // #93 took the sentence off the visible card — it is an icon and two
        // words now — but the plain-language copy still has to reach VoiceOver,
        // which is the reader with the LEAST context, not the most.
        let copy = NSPredicate(format: "label CONTAINS 'download once, then work offline'")

        openSearch(app, "victoria")
        XCTAssert(app.descendants(matching: .any).matching(copy)
            .firstMatch.waitForExistence(timeout: 10),
                  "the pending card's status strip is missing the plain-language copy")
        closeSearch(app)

        openSearch(app, "malibu")
        XCTAssert(app.staticTexts["Malibu Rapids"].firstMatch.waitForExistence(timeout: 5),
                  "search did not find Malibu Rapids")
        XCTAssert(app.descendants(matching: .any).matching(copy)
            .firstMatch.waitForExistence(timeout: 10),
                  "derived gate must show the CHS pending register before its reference is fitted")
    }

    // M4.4: iPad split layout — regular width gets the web's ≥62rem shape
    // (styles.css): persistent sidebar (search + groups) beside the detail
    // pane, in both orientations. Skipped on iPhone, which keeps the stack.
    func testM44IPadSplit() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only layout test")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch("-seedGate")
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
        let app = launch("-seedGate")

        // No top search bar on the list; both FABs present.
        XCTAssertFalse(app.textFields.firstMatch.exists, "top search bar must be gone")
        XCTAssert(app.buttons["Search"].exists)
        XCTAssert(app.buttons["Map"].exists)

        // Search FAB → bottom input, keyboard up (openSearch types with no
        // field tap), results fill the space above.
        openSearch(app, "friday")
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.waitForExistence(timeout: 5))
        XCTAssert(app.buttons["Close search"].exists, "X missing beside the input")

        // X beside the input: one tap back to the list, keyboard gone.
        closeSearch(app)
        XCTAssertFalse(app.textFields.firstMatch.exists, "X did not close search")

        // Map FAB: the surface swaps in place, the button becomes the list
        // icon, and no chrome sits over the map.
        app.buttons["Map"].tap()
        XCTAssert(app.otherElements["map-canvas"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["MAP"].exists, "map must carry no header")
        XCTAssert(app.buttons["List"].exists, "toggle did not flip to the list icon")

        // #43: the "not for navigation" pill belongs ON the FAB row, not
        // floating above it mid-chart. Asserted as geometry rather than by
        // eye — the old bug was a constant (96pt from the screen edge, past
        // the safe area) that looked right in one simulator and wrong on the
        // next, which is exactly what a frame comparison catches.
        let disclaimer = app.staticTexts["map-disclaimer"].firstMatch
        XCTAssert(disclaimer.waitForExistence(timeout: 5), "map disclaimer missing")
        let toggle = app.buttons["List"].firstMatch
        XCTAssertGreaterThan(disclaimer.frame.minY, toggle.frame.minY,
                             "the pill floats above the FABs instead of sitting on their row")
        XCTAssertLessThanOrEqual(disclaimer.frame.maxY, toggle.frame.maxY + 1,
                                 "the pill hangs below the FAB row, into the home indicator")

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
        try skipUnlessFull()
        let app = launch("-chsResetModels", "-seedGate", "-chsFitOnly", "chs-dodd-narrows")

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

        app.staticTexts["Dodd Narrows"].firstMatch.tap()
        // Full current-detail anatomy: the slack countdown and the CHS
        // provenance footer (device-computed, not CHS-published). M51: Dodd is
        // a 210-day gate, so the card above landed on its 60-day fast answer —
        // the final footer is the tell that the full model has since replaced
        // it (the fast answer's own footer says "60 of 210 days downloaded").
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.waitForExistence(timeout: 300))

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
    }

    // M4.6: after the reference port fits (live IWLS, like M3), the gate card
    // shows the phase pill + next slack, and the detail renders the
    // current-only strip (split-scrubbers — the port sources slacks, it is
    // not a track of its own), slack rows with no speeds, and the derived
    // provenance copy.
    func testM46MalibuDerivedGate() throws {
        try skipUnlessFull()
        // M53: Point Atkinson is 100 km from the Victoria fallback, so it is
        // NOT in the auto-fit set — opening the gate is what downloads it,
        // which is the behaviour under test. Scoped so that is the only fit
        // in flight (see testM3 for why unscoped live tests fight each other).
        let app = launch("-seedGate", "-chsFitOnly", "chs-point-atkinson")

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
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 300),
                  "the open detail never filled in — Point Atkinson fit missing (IWLS unreachable?)")
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.descendants(matching: .any).matching(identifier: "tide-at-port")
            .firstMatch.waitForExistence(timeout: 5),
                  "derived gate must link to its reference port")
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

        // Print today's rendered schedule times for the verification table.
        // Scoped to the rows via scheduleValues: unscoped, this table would
        // quietly include iPad sidebar card readings.
        print("M46-SCHEDULE-TIMES: \(scheduleValues(app, "\\b\\d{2}:\\d{2}\\b").sorted())")

        // The live card (PA fitted now): "Slack · time" line + the phase pill.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "malibu")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Slack ·'")).firstMatch.waitForExistence(timeout: 5),
                  "live gate card missing its next-slack line")
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
        sleep(3)
        save(app, "m46-malibu-map.png")
    }

    // #38: the derived-gate strip, offline, in the FAST plan. A derived gate
    // is the one path where EVERY slack takes the windowless branch — no
    // `slackWindows` by design, so every gate event draws a dropline + gutter
    // time and never a band — and testM46MalibuDerivedGate (the only other
    // render of it) needs a live IWLS fit, so a normal run rendered it
    // nowhere. `-seedTideModel` stores a synthetic fit for the reference port
    // (Point Atkinson) before ChsFitService's one-time directory read, so the
    // same detail renders with no network; `-networkKillSwitch` keeps it
    // honest. No `-chsResetModels`: the seed hook wipes the store itself
    // (combining them would delete the seed — SlackwaterApp.init's comment).
    func testM46MalibuDerivedGateSeededOffline() throws {
        let app = launch("-seedGate", "-networkKillSwitch",
                         "-seedTideModel", "chs-point-atkinson")

        openSearch(app, "malibu")
        XCTAssert(app.staticTexts["Malibu Rapids"].firstMatch.waitForExistence(timeout: 5),
                  "search did not find Malibu Rapids")
        app.staticTexts["Malibu Rapids"].firstMatch.tap()

        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 10),
                  "seeded reference fit did not render the derived-gate detail")
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["● SLACK"].firstMatch.waitForExistence(timeout: 5),
                  "slack rows missing from the schedule")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'speeds are not predicted'")).firstMatch.exists,
                  "the shape-only note is missing")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'cruising-community'")).firstMatch
            .waitForExistence(timeout: 5),
                  "derived provenance footer missing")

        // The strip must actually DRAW its schematic curve, droplines and
        // gutter times — nothing inside the Canvas is an accessibility
        // element, so ink coverage is what a test can see (the
        // testPickingADateMovesTheWindow precedent).
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.waitForExistence(timeout: 5), "derived-gate strip missing")
        let ink = inkFraction(strip)
        XCTAssert(ink > 0.05, "the derived-gate strip drew nothing — ink \(ink)")
        sleep(1)
        save(app, "m46-derived-gate-seeded.png")
    }

    // M48: the offline-downloads system — the indicator beside the gear, the
    // manager it opens, the proximity-ordered queue, and the fix for the dead
    // tap: an unfitted station opens its detail with the ⚠️ explanation and
    // jumps to the front of the queue. Runs against LIVE IWLS from a clean
    // store (like M3/M47) — nothing here waits for a fit to land, only for the
    // queue and its UI, so it costs seconds, not the fit chain.
    func testM48DownloadsManagerAndQueueJump() throws {
        try skipUnlessFull()
        let app = launch("-seedGate", "-chsResetModels",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")  // Victoria

        // The indicator sits beside the gear, on the same line.
        let indicator = app.buttons["offline-status"].firstMatch
        XCTAssert(indicator.waitForExistence(timeout: 5), "no download indicator beside the gear")
        let gear = app.buttons["Settings"].firstMatch
        XCTAssert(gear.exists)
        XCTAssert(indicator.frame.maxX <= gear.frame.minX + 1, "indicator must sit beside the gear")
        XCTAssertEqual(indicator.frame.midY, gear.frame.midY, accuracy: 2,
                       "indicator must share the gear's row")
        sleep(3)  // let the first download start, so the state is 'downloading'

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
        // ChsFitService is actively mutating row heights here (status text
        // flips as downloads progress) — read all three rows together and wait
        // the layout out, so the order check compares one layout (see
        // testM50RecentsNamesFit / settled).
        let rowFrames = settled { [victoria.frame, race.frame, porlier.frame] }
        XCTAssert(rowFrames[0].minY < rowFrames[1].minY, "queue is not proximity-ordered")
        XCTAssert(rowFrames[1].minY < rowFrames[2].minY, "queue is not proximity-ordered")
        XCTAssertFalse(rows["download-row-chs-sooke"].firstMatch.exists,
                       "the manager is listing the catalog again, not the download set")
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
        // Right after service.promote — the queue is mid-transition, so read
        // both rows together and let them settle (settled).
        let queue = settled { [promoted.frame, stillQueued.frame] }
        XCTAssert(queue[0].minY < queue[1].minY,
                  "the viewed station did not jump ahead of the proximity order")
        app.buttons["Done"].tap()
    }

    /// Issue #33: a Downloads row is a dead tap no longer — tapping it closes
    /// the sheet and opens the station's own detail via `openChsRoute`
    /// (Theme.swift), the same generalized closure the online-gate honesty
    /// card's nearest-shipped link now shares. `-chsResetModels` wipes the
    /// model store so the whole queue starts `.pending`; no `-fixLat`/`-fixLon`
    /// needed because `ChsFitService.init` unconditionally adopts the
    /// `firstRunFix` (Victoria) before any real fix can land (its own doc
    /// comment: "never an arbitrary order, even before a fix lands"), and
    /// Victoria itself is distance zero from that anchor — so it is always the
    /// queue's first job, deterministic without a location launch argument.
    func testDownloadsRowOpensDetail() throws {
        let app = launch("-seedGate", "-chsResetModels")

        app.buttons["offline-status"].firstMatch.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5),
                  "the indicator did not open the downloads manager")

        let victoria = app.descendants(matching: .any)["download-row-chs-victoria"].firstMatch
        XCTAssert(victoria.waitForExistence(timeout: 5), "Victoria is not in the download queue")
        if !victoria.isHittable { app.swipeUp() }  // it should already be the first row
        XCTAssert(victoria.isHittable, "download-row-chs-victoria exists but never became hittable")
        victoria.tap()

        // Wait on the positive signal first — the pushed detail's header —
        // rather than an immediate non-existence check on "Downloads": the
        // sheet's dismiss animation is not instant, so checking right after
        // the tap synthesizes races it. Scoped to the header, not a bare name
        // lookup: on iPad the persistent sidebar can carry "Victoria" in its
        // own list ranking independently of what got pushed (same trap
        // testOnlineGateUnfetchedShowsHonestyCard's header lookup dodges).
        let header = app.otherElements["detail-map-header"].firstMatch
        XCTAssert(header.waitForExistence(timeout: 5),
                  "the row tap did not push a detail")
        XCTAssert(header.staticTexts["Victoria"].firstMatch.exists,
                  "the row tap opened the wrong station's detail")

        // The sheet is gone — "Downloads" was its own nav title, so its
        // disappearance is the dismiss signal, not just the row. Checked last:
        // by now the dismiss animation has long since settled.
        XCTAssertFalse(app.staticTexts["Downloads"].exists,
                       "tapping a row must dismiss the Downloads sheet")
    }

    /// Issue #33 review finding #2: the row's own tap gesture and the Retry
    /// button (`service.promote`, shown only on a `.failed` job) are siblings
    /// in the same `HStack` — the Retry button ahead of `.contentShape`/
    /// `.onTapGesture` in the modifier chain, per the row-tap comment. No test
    /// covered that combination; this proves the button wins the hit test
    /// rather than the row's gesture swallowing it. `-chsFailOnly` (new hook,
    /// ChsFitService.swift) marks a job `.failed` at launch, no network
    /// attempt — a real fetch failure isn't deterministic for a fast test, and
    /// `-networkKillSwitch` keeps every OTHER job inert too (`run()`'s claim
    /// loop only ever touches `.pending` jobs, so the seeded `.failed` status
    /// sticks until something explicitly retries it).
    ///
    /// Seeded on Victoria HARBOUR, deliberately NOT plain Victoria: at regular
    /// width the split layout auto-selects a first detail on `.onAppear`
    /// (SlackwaterApp.swift), and with no fix that's the nearest station to
    /// the Victoria fallback — chs-victoria itself. `ChsDetailView.onAppear`
    /// unconditionally promotes whatever route it shows, so seeding
    /// chs-victoria as `.failed` was self-defeating on iPad: auto-select
    /// opened it and silently un-failed it before this test ever touched the
    /// sheet (confirmed live — the Retry button and the "still failed"
    /// precondition were gone by the time of the very first read). Victoria
    /// Harbour is the second-nearest port — queued (inside the auto-fit set's
    /// nearest 6 ports) but never auto-selected — so it stays genuinely
    /// `.failed` until this test's own tap.
    func testDownloadsRowRetryButtonWinsOverRowTap() throws {
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch",
                         "-chsFailOnly", "chs-victoria-harbour")

        app.buttons["offline-status"].firstMatch.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5))

        let row = app.descendants(matching: .any)["download-row-chs-victoria-harbour"].firstMatch
        XCTAssert(row.waitForExistence(timeout: 5), "the seeded failed row is missing")
        if !row.isHittable { app.swipeUp() }
        XCTAssert(row.isHittable, "download-row-chs-victoria-harbour exists but never became hittable")
        // `.accessibilityElement(children: .combine)` on the row merges its
        // plain text into one label but does NOT absorb the nested Button —
        // confirmed live (`app.buttons["Retry"]` resolves as its own element,
        // separate from the row).
        let retry = row.buttons["Retry"].firstMatch
        XCTAssert(retry.waitForExistence(timeout: 5), "seeded chs-victoria-harbour never shows the Retry button")
        if !retry.isHittable { app.swipeUp() }
        XCTAssert(retry.isHittable, "Retry button exists but never became hittable")
        retry.tap()
        sleep(1)  // the queue re-sort/re-render isn't instant

        // Promote's own visible effect proves the BUTTON's action ran: the
        // failed row flips to promoted+pending — "YOU OPENED" and "Waiting"
        // replace the Retry pill. The row renders EITHER the Retry button OR
        // `statusText(job)`, never both (OfflineDownloads.swift's `row(_:)`),
        // so "Waiting" in the label already implies Retry is gone.
        let label = row.label
        XCTAssert(label.contains("YOU OPENED") && label.contains("Waiting"),
                  "tapping Retry did not promote the row — expected \"YOU OPENED\"/\"Waiting\" in its label, got \"\(label)\"")

        // And the row tap's OWN effect never fired: the sheet is still up.
        // NOT a bare "no detail-map-header exists" check — on iPad the split
        // layout auto-selects Victoria's OWN detail underneath this sheet
        // regardless of anything this test does (the same auto-select the
        // doc comment above routes around), so a header legitimately exists
        // throughout. The header's NAME is the tell: if the row's gesture had
        // fired instead of the button, it would have pushed Victoria
        // Harbour's detail, replacing what's shown.
        XCTAssert(app.staticTexts["Downloads"].exists,
                  "the row's onTapGesture must not have fired — the Retry button owns this tap")
        let header = app.otherElements["detail-map-header"].firstMatch
        if header.exists {
            XCTAssertFalse(header.staticTexts["Victoria Harbour"].firstMatch.exists,
                           "no detail should have opened — the button, not the row, must have handled the tap")
        }
    }

    /// Issue #32: the map-header title jumps to the map, focused on the
    /// detail's own station (SlackwaterApp.swift `openMapFocused`/`mapFocus`,
    /// MapHeader.swift's title pill). No accessibility surface exposes an
    /// `MLNMapView`'s live center/zoom to XCUITest — nothing in this file
    /// reads one — so this proves the navigation contract (map up, detail
    /// gone) rather than the actual camera position; `mapFocus`/`stationZoom`
    /// wiring the correct center/zoom into `MapViewRepresentable` is covered
    /// by reading the source, same as the rest of MapStyler's camera
    /// assertion, which nothing here exercises either.
    ///
    /// Two entry paths, one launch. They assert the identical contract and
    /// differed only in how the detail was reached, which is worth a second leg
    /// but not a second cold launch.
    func testHeaderTitleFocusesMap() throws {
        // Camera dead-centered on Friday Harbor (stations.json) so the pin leg
        // below can tap it: a finger-sized box at the exact center of a
        // station-scale zoom holds one pin. Same convention as
        // testM48MapPinToUnfittedDetail.
        let app = launch("-seedGate", "-fixLat", "48.5453", "-fixLon", "-123.0125",
                         "-mapZoom", "11")

        // Leg 1 — detail reached from a list row.
        openFridayHarbor(app)
        assertTitleTapFocusesMap(app)

        // Leg 2 — detail reached from a MAP PIN. Review finding on the first cut
        // of #32: that path leaves `showMap` already `true` on iPhone, so the map
        // pane doesn't naturally remount for the title tap that follows.
        // `.id(mapFocusToken)` on `MapViewRepresentable` forces the remount and
        // `makeUIView` applies the focus (MapScreen.swift). iPhone-only: on iPad
        // the split layout's `mapPane` `onSelect` resets `showMap` on a pin tap,
        // so the scenario cannot arise there — an inline guard rather than a
        // whole-test skip, so leg 1 still runs on both.
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.waitForExistence(timeout: 5))
        sleep(5)  // tiles
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5),
                  "the pin tap did not open a detail")
        assertTitleTapFocusesMap(app)
    }

    /// Tap the detail's header title: the map comes up and the detail is gone.
    /// The camera move itself is not independently assertable — no accessibility
    /// surface exposes `MLNMapView`'s live center — so this is the navigation
    /// contract; the `.id(mapFocusToken)` remount is verified by reading
    /// MapScreen.swift, traced in the issue-32 report.
    private func assertTitleTapFocusesMap(_ app: XCUIApplication) {
        // Top of the detail, under the status bar clearance — should be
        // hittable the moment the header renders, no scroll needed.
        let title = app.descendants(matching: .any)["map-header-title"].firstMatch
        XCTAssert(title.waitForExistence(timeout: 5), "map-header-title missing")
        XCTAssert(title.isHittable, "map-header-title exists but never became hittable")
        title.tap()

        XCTAssert(app.otherElements["map-canvas"].firstMatch.waitForExistence(timeout: 5),
                  "the title tap did not show the map")
        XCTAssertFalse(app.otherElements["detail-map-header"].exists,
                       "the title tap must pop the detail, not layer the map over it")
    }

    // M48: the map needed no map-specific work — a pin tap goes through the
    // same open() as a row, so an unfitted station lands on the same warning
    // detail. Held unfitted by the kill switch, so this is deterministic.
    func testM48MapPinToUnfittedDetail() throws {
        // M53: the camera is put ON Race Passage rather than aimed at it from
        // the wide Salish view. At 195 bundled stations a finger-sized box over
        // that pin held one dot; at 3,125 it holds several, and "the nearest
        // dot to the tap" stopped being the one the test meant. The fix is the
        // fix — the discovery map now opens on it — plus a station-scale zoom.
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch",
                         "-fixLat", "48.3067", "-fixLon", "-123.5367", "-mapZoom", "11")
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
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "discovery island")
        XCTAssert(app.staticTexts["6.6 nm SSE"].firstMatch.waitForExistence(timeout: 5),
                  "the fixed subtitle is missing — expected nautical miles and SSE")
        XCTAssertFalse(app.staticTexts["7.6 mi. Sse"].exists,
                       "the broken subtitle is still rendering")
        XCTAssert(app.staticTexts["3.0 nm NE"].firstMatch.exists,
                  "the sibling station's already-correct subtitle changed")
        closeSearch(app)
    }

    /// Two "Discovery Island" cards used to sit in Near Me looking identical.
    /// Now: one entry, and the matching stations behind the chooser — and
    /// once you pick the non-nearest one from that chooser, Recents remembers
    /// exactly which one you opened (Task 7: no namesake collapse on an
    /// explicit pick).
    func testM50MatchingStationChooser() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        // M53: the fix moved from Victoria to Discovery Island itself. At 195
        // bundled stations the two namesakes were both inside Victoria's Near
        // Me; at 3,125 the six nearest a Victoria fix are all harbour gauges
        // inside 5 km, which is what Near Me is FOR and not what this test is
        // about. Standing at the station is the deterministic way to put a
        // collided name in the list.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.452", "-fixLon", "-123.155")  // Discovery Island
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

        // Picking the collapsed one opens it — it is not lost, just quiet.
        app.staticTexts["6.6 nm SSE"].firstMatch.tap()
        XCTAssert(app.staticTexts["Discovery Island"].firstMatch.waitForExistence(timeout: 8))
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8),
                  "the chooser pick did not open a station detail")

        // Recents keeps the station actually opened (Task 7 / split-scrubbers
        // spec §6): the chooser pick is an explicit choice, not the distance
        // ranking — collapsing it used to file the visit under the nearest
        // namesake's id, so Recents would silently show and reopen "3.0 nm
        // NE" instead of the "6.6 nm SSE" station tapped. Same disambiguating
        // field the chooser assertions above key on (each station's region is
        // literally its bearing string), so a bare text match is unambiguous.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        let recentsLabel = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsLabel, in: app)
        let recentPick = app.staticTexts["6.6 nm SSE"].firstMatch
        scrollTo(recentPick, in: app)
        XCTAssert(recentPick.exists,
                  "Recents must keep the chooser-picked station, not collapse it into the nearest namesake")
    }

    /// "Deception Pas…" — the compact Recents row starved the name column so
    /// two different stations truncated to the same string.
    func testM50RecentsNamesFit() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

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
        // Recents updates its status line, and the row's name/reading gap is
        // only ~2pt — so the name and EVERY reading come out of one `settled`
        // read. Settling the name alone and reading the readings after it let
        // a 3pt shift land in between and failed CI (PR #25).
        let readingLabels = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^-?\\d+\\.\\d+ (ft|m|kn)$"))
        let frames = settled {
            [long.frame] + readingLabels.allElementsBoundByIndex.compactMap {
                $0.exists ? $0.frame : nil
            }
        }
        let nameFrame = frames[0]
        // The name owns the row's width now. Truncated, its frame collapsed to
        // the ~150pt column left over beside the reading (iPad sidebar).
        XCTAssert(nameFrame.width > 165,
                  "the Recents name column is still starved: \(nameFrame.width)pt")
        // And the reading sits below the name, not beside it. Only this row's —
        // the Near Me cards above carry readings too.
        let readings = frames.dropFirst().filter {
            $0.minY >= nameFrame.minY && $0.maxY <= nameFrame.maxY + 34
        }
        XCTAssertFalse(readings.isEmpty, "the Recents row lost its reading")
        for frame in readings {
            XCTAssert(frame.minY >= nameFrame.maxY - 1,
                      "the reading still shares the name's line: \(frame) vs name \(nameFrame)")
        }
    }

    /// Build 13, iPad: opening a second station of the SAME kind kept the
    /// first one's chart and map — same destination type at the same depth is
    /// the same SwiftUI identity, so @State survived. The tide-row tell is
    /// gone with the paired pane (split-scrubbers); the stale-@State tell is
    /// now the schedule contents themselves — timeline-derived, so a stale
    /// detail keeps the previous station's rows verbatim — plus the
    /// tide-at-port link (record-derived: Discovery Island has none, Deception
    /// Pass (Narrows) does) as the layout check.
    func testM50DetailSwapsBetweenSameKindStations() throws {
        // Split layout only: on iPhone the detail covers the search FAB, so a
        // second station is always reached through a pop first.
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only split-layout swap")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "discovery island")
        app.staticTexts["3.0 nm NE"].firstMatch.tap()
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "tide-at-port").firstMatch.exists,
                       "an unpaired current station has no reference port to link")
        let before = scheduleRowLabels(app)
        XCTAssert(!before.isEmpty, "no schedule rows read from the first station")

        // Second station, same kind — in the split layout this replaces the
        // detail pane without a pop.
        openSearch(app, "deception pass (n")
        app.staticTexts["Deception Pass (Narrows)"].firstMatch.tap()
        XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch
            .waitForExistence(timeout: 8))
        XCTAssert(app.descendants(matching: .any).matching(identifier: "tide-at-port")
            .firstMatch.waitForExistence(timeout: 8),
                  "a paired gate links to its reference port")
        XCTAssert(scheduleRowLabels(app) != before,
                  "the detail kept the previous station's timeline — schedule did not change")
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
        try skipUnlessFull()
        let t0 = Date()
        let app = launch("-chsResetModels", "-seedGate", "-chsFitOnly", "chs-victoria",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
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
        try skipUnlessFull()
        let t0 = Date()
        let app = launch("-chsResetModels", "-seedGate", "-chsFitOnly", "chs-active-pass",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        openSearch(app, "active pass")
        let overlay = app.scrollViews.firstMatch
        let fitted = overlay.staticTexts.matching(
            NSPredicate(format: "label == 'Flooding' OR label == 'Ebbing' OR label == 'SLACK'")).firstMatch
        XCTAssert(fitted.waitForExistence(timeout: 240), "Active Pass never fitted — IWLS unreachable?")
        report("nearest 60-day gate → FINAL", t0)

        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Refining'")).firstMatch.exists,
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
        try skipUnlessFull()
        let t0 = Date()
        let app = launch("-chsResetModels", "-seedGate", "-chsFitOnly", "chs-dodd-narrows",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        openSearch(app, "dodd")

        // The fast answer, in the list: the amber "Refining · ±35 min" strip and
        // a tilde'd reading, and that is ALL — the amber PROSE that used to ride
        // the card measured 1.03:1 against the palest station gradient (M52),
        // and the ⚠️ badge that replaced it said nothing a reader could act on
        // (#93). The full explanation still lives on the detail.
        let badge = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Refining'")).firstMatch
        XCTAssert(badge.waitForExistence(timeout: 240),
                  "Dodd Narrows never published its 60-day fast answer")
        XCTAssert(badge.label.contains("±35 min"),
                  "the strip must carry THIS pass's measured tolerance, not a generic hedge")
        report("nearest 210-day gate → PROVISIONAL", t0)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'FAST ANSWER'")).firstMatch.exists,
                       "the low-contrast amber badge must be gone from the list card")
        // CONTAINS, not BEGINSWITH: when the gate is inside its slack window
        // the trailing reading is the SLACK phase pill, and the card's tilde
        // rides the detail line instead ("Max flood ~3.0 kn · 8:20 PM") — a
        // time-of-day form this test can land on (it did, iPad, build-20 full
        // run at 6:07 PM). Both forms keep a hedged number on the card.
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '~'")).firstMatch.exists,
                  "the tilde stays: the reading itself must still say it is not exact")

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

        // The refinement lands under the open page: same station, final model.
        var waited = 0
        while warning.exists, waited < 300 { sleep(5); waited += 5 }
        XCTAssertFalse(warning.exists, "the fast answer never refined to the full model")
        report("nearest 210-day gate → FINAL", t0)
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.exists, "the refined page is still a live detail")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.exists,
                  "the refined page carries the ordinary final footer")
    }

    /// The manager, mid-run: one gate usable-but-refining beside the ordinary
    /// waiting/downloading rows — provisional and final are different words.
    func testM51ManagerShowsProvisionalApartFromFinal() throws {
        try skipUnlessFull()
        let app = launch("-chsResetModels", "-seedGate",
                         "-chsFitOnly", "chs-dodd-narrows,chs-victoria,chs-active-pass",
                         "-fixLat", "49.1344", "-fixLon", "-123.8171")  // at Dodd
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
        app.buttons["Done"].tap()
    }

    /// Opening a station while a long gate is mid-download used to cost up to
    /// ~2.5 min: promotion only took effect at the next STATION boundary. Now
    /// the running job steps aside at the next CHUNK — and comes back to what
    /// it already fetched.
    func testM51PromotionInterruptsAnInFlightDownload() throws {
        try skipUnlessFull()
        let app = launch("-chsResetModels", "-seedGate",
                         "-chsFitOnly", "chs-dodd-narrows,chs-tofino",
                         "-fixLat", "49.1344", "-fixLon", "-123.8171")  // Dodd is nearest

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
        // stepped aside and the station you opened is downloading. Idle that is
        // seconds, but the second-simulator leg of a full run starts ~30 min in
        // on the machine that also hosts the CI runner — a fixed 30 s here
        // failed ~2 of 3 full runs under that load (#65), so poll to the same
        // 300 s deadline the surrounding loops use. The print below still
        // reports the time it actually took.
        let tofino = app.descendants(matching: .any)["download-row-chs-tofino"].firstMatch
        var waited = 0
        while !tofino.label.contains("Downloading"), waited < 300 { sleep(1); waited += 1 }
        XCTAssert(tofino.label.contains("Downloading"),
                  "opening a station did not interrupt the gate in flight (waited \(waited) s)")
        XCTAssert(app.descendants(matching: .any)["download-row-chs-dodd-narrows"]
            .firstMatch.label.contains("Waiting"), "the yielded gate must go back to waiting, not fail")
        print("M51 interrupt: promoted station started \(String(format: "%.1f", -t0.timeIntervalSinceNow)) s after the open")

        // And it resumes: once the promoted port is done the gate carries on
        // from its cached chunks (never re-fetching them — ChsProvisionalTests).
        // Same deadline as above: this clock covers Tofino's whole download,
        // which load stretches just as much as the yield (#65).
        waited = 0
        while !dodd.label.contains("Downloading"), waited < 300 { sleep(2); waited += 2 }
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
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch")

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
        let app = launch("-seedGate")
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
        // The 44pt slot this guards is fixed by construction, but re-reading
        // star/now/header/back live below would still be racy (settled — see
        // testM50RecentsNamesFit). One read, one layout, four snapshots.
        let header = app.otherElements["detail-map-header"].firstMatch
        let after = settled { [star.frame, now.frame, header.frame, back.frame] }
        let starAfter = after[0], nowFrame = after[1], headerFrame = after[2]
        XCTAssertEqual(starAfter.minX, starBefore.minX, accuracy: 0.5,
                       "return-to-now still shifts the star")
        XCTAssertEqual(starAfter.minY, starBefore.minY, accuracy: 0.5)
        XCTAssertEqual(after[3].minX, backBefore.minX, accuracy: 0.5,
                       "return-to-now must not move the back button either")

        // Its own slot: below the hero, in the when-row at the bottom of the
        // scrub card, directly beside the time/date stack on the LEADING side
        // (2026-08-07 when-row redesign — it stopped bouncing between readout
        // rows and settled next to the time it resets).
        XCTAssert(nowFrame.minY > starAfter.maxY, "return-to-now is not below the star")
        XCTAssert(nowFrame.minY >= headerFrame.maxY - 1,
                 "return-to-now must live below the hero, in the scrub card")
        // Leading side of the DETAIL PANE, not of the window: on a portrait
        // iPad the sidebar pushes the pane past the window's midX, so the
        // window ruler only passed here because the test before this one
        // leaves the device in landscape. `detail-map-header` is no ruler
        // either — its accessibility frame spans the whole window, not the
        // pane. The pane's own chrome is: back on its leading edge, star on
        // its trailing one.
        let paneMidX = (after[3].minX + starAfter.maxX) / 2
        XCTAssert(nowFrame.midX < paneMidX,
                  "return-to-now sits beside the time stack on the leading side: "
                  + "\(nowFrame.midX) vs pane mid \(paneMidX)")

        // And it still does its job — back to now, and gone again.
        now.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["detail-return-now"].firstMatch.exists,
                       "return-to-now did not clear after returning to now")
        XCTAssertEqual(settled { star.frame }.minX, starBefore.minX, accuracy: 0.5,
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
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 10),
                  "the detail pane did not open a station on launch")
        XCTAssertFalse(app.staticTexts["Pick a station"].exists,
                       "the placeholder is still what a fresh iPad launch shows")
        // The sidebar is intact — this is a selection, not a push.
        XCTAssert(app.staticTexts["Slackwater"].exists)

        // Don't fight the user: a deliberate pick stands, and coming back to
        // the list does not re-run the auto-select.
        openSearch(app, "friday")
        app.staticTexts["Friday Harbor"].firstMatch.tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists,
                  "the auto-selection overrode a deliberate pick")
    }

    /// All "HH:mm" labels on screen — chart annotations + schedule rows. The
    /// schedule rows' accessibility labels — NOT the whole screen (the paired
    /// current→tide detail this originally guarded is retired — split-scrubbers
    /// — but callers still need the schedule scoped out of the whole hierarchy,
    /// see below).
    ///
    /// Scoping matters on iPad and only on iPad. The split-view sidebar renders
    /// live station cards, and since layout A put the reading on the card's
    /// right they emit `X.X ft` strings that match the same regexes the schedule
    /// rows do. A caller that scrapes twice and diffs then blames the detail
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

    private func save(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: shotDir + "/" + name))
    }

    /// `XCUIElement.frame` re-queries the live layout on EVERY access, so
    /// comparing two elements' `.frame` values across a reflow (a sidebar
    /// row resizing as async status text lands, a queue re-sorting mid-
    /// promotion) compares coordinates from two different layouts. That is
    /// how CI watched a Near Me reading 550pt away "share the name's line"
    /// (PR #22, testM50RecentsNamesFit).
    ///
    /// Settling ONE element and then reading its counterparts live is the same
    /// bug with an extra step — the reflow lands in the gap between the settle
    /// and the next read, which is how M50 failed again on a 3pt shift when
    /// the row's gap is only 2pt (PR #25). So read EVERY frame a comparison
    /// needs inside this closure: it re-reads them all together until two
    /// consecutive passes agree, and hands back that ONE layout. Never re-read
    /// `.frame` after this.
    private func settled<T: Equatable>(_ read: () -> T) -> T {
        var snapshot = read()
        for _ in 0..<20 {
            usleep(250_000)
            let again = read()
            if again == snapshot { break }
            snapshot = again
        }
        return snapshot
    }

    // MARK: - M53: the US and Canada

    /// The whole point of M53: a station 4,000 km from the Salish Sea is
    /// searchable, opens, and draws a real curve from bundled NOAA harmonics —
    /// no download, no signal needed, same screen as Friday Harbor.
    func testM53UsEastCoastStationRendersACurve() throws {
        // Airplane mode: whatever renders here is bundled, not fetched.
        let app = launch("-seedGate", "-networkKillSwitch")

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
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty,
                       "no height readings on the Boston detail")
        XCTAssertGreaterThanOrEqual(scheduleValues(app, "\\b\\d{2}:\\d{2}\\b").count, 3,
                                    "no schedule on the Boston detail")
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

    /// T6 acceptance case for the whole world-coverage plan: the Solent, the
    /// water that started it (`firstRunFix`'s doc comment — the app once
    /// opened here and ranked from Vancouver Island). No NOAA or CHS current
    /// station is within `currentCoverageKm` of Portsmouth, so Near Me must say so in words
    /// rather than just show an empty currents list — an empty list here
    /// reads as "the water is slack", which is false and dangerous.
    func testM53NoCurrentCoverageNoticeAtPortsmouth() throws {
        let app = launch("-seedGate", "-resetRecents", "-fixLat", "50.80", "-fixLon", "-1.11")

        let notice = app.staticTexts["Current predictions not available here"].firstMatch
        XCTAssert(notice.waitForExistence(timeout: 5),
                  "Portsmouth has no NOAA or CHS current station within reach — Near Me must say so")
        scrollTo(notice, in: app)
        save(app, "m53-portsmouth-no-current-coverage.png")
    }

    /// Search at 3,125 stations: bounded, nearest-first, and honest about what
    /// it is not showing.
    func testM53SearchAtNationalScale() throws {
        // `-resetRecents` is load-bearing, not hygiene: since the ranking anchor
        // became fix -> RecentsStore.lastOpened -> firstRunFix, "the Victoria
        // fallback" this test asserts about only holds with no recents. The
        // full plan runs testM53OnDemandCanadianStationFitsWhenOpened (Halifax)
        // immediately before this, which left the anchor 4,500 km east and no
        // BC or WA port inside the truncated set. The fast plan skips that test,
        // so CI stayed green while the full run went red.
        let app = launch("-seedGate", "-networkKillSwitch", "-resetRecents")

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

        // Narrowing removes the truncation notice — the list is complete again.
        app.textFields.firstMatch.typeText(" townsend")
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any)["search-truncated"].firstMatch.exists,
                       "a narrow query must not claim to be truncated")
        closeSearch(app)
    }

    /// The map at continental scale. Thousands of pins is a grey smear without
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
        // scale where an unclustered one is thousands of separate dots.
        let start = Date.now
        for _ in 0..<5 { map.pinch(withScale: 1.6, velocity: 2) }
        let gestures = Date.now.timeIntervalSince(start)
        // No pin count in the line. A UI test cannot see `StationItem.all`
        // (separate target, no `@testable`), so the 3,125 that used to be
        // printed here was a hardcoded literal from the pre-world bundle — it
        // read as a measurement and was off by 1,500 the day world coverage
        // landed. A diagnostic that states a number it cannot check is worse
        // than one that states only what it timed.
        print(String(format: "map · 5 pinches at z3.2 over the whole world bundle: %.2f s", gestures))
        XCTAssertLessThan(gestures, 20, "zooming the world pin map should not take 20 seconds")

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
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch")

        openSearch(app, "halifax")
        let halifax = app.staticTexts["Halifax"].firstMatch
        XCTAssert(halifax.waitForExistence(timeout: 5),
                  "a Canadian station 4,400 km away must still be findable offline")
        // The words on the card, not the VoiceOver phrasing: this is the one
        // assertion about what a reader actually SEES on an unqueued station.
        XCTAssert(app.staticTexts["Tap to download"].firstMatch.exists,
                  "an unqueued station must not claim to be queued")
        // The card, by id — see testM53OnDemandCanadianStationFitsWhenOpened.
        app.descendants(matching: .any)["chs-pending-chs-halifax"].firstMatch.tap()

        XCTAssert(app.staticTexts["No predictions yet"].waitForExistence(timeout: 8),
                  "opening an undownloaded Canadian station must explain itself")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'works offline'")).firstMatch.exists)

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
        try skipUnlessFull()
        let app = launch("-seedGate", "-chsResetModels")

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
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty,
                       "fitted, but no numbers")
    }

    // MARK: - Online gates (task-6: the 7 fit-reject gates, fetched-on-demand
    // CHS predictions instead of an on-device fit — no network in either test:
    // the unfetched page below relies on `-networkKillSwitch` staying up for
    // its whole run, the fetched one relies on `ChsModelStore.saveOnline`
    // writing a covering window before the app ever draws a frame.)

    /// The origin report: a fresh install can FIND Sechelt Rapids by its
    /// "skookumchuck" alias, and the tap lands on the honest explanation, not a
    /// dead end (M48). `-chsResetModels` leaves no stored window (it wipes the
    /// whole `ChsModelStore.dir`, `-online.json` included — same directory as
    /// the fitted files); `-networkKillSwitch` is what keeps the honesty card
    /// up for the length of the test — without it, `OnlineGateDetailView.onAppear`
    /// fires a REAL IWLS fetch the moment the honesty card would otherwise be
    /// asserted, and a fetch that lands mid-test would swap it for the fetched
    /// detail out from under the assertions (SlackwaterApp.swift's
    /// `seedOnlineWindow` doc comment covers the other half of this same
    /// coverage question). The nearest-gate-link push is NOT a list-driven
    /// reset (`OpenChsRouteKey`'s doc comment, Theme.swift): it
    /// stacks onto Sechelt's own detail, so one `detail-back` lands back on
    /// Sechelt, not the list — which is exactly the page this test stars, to
    /// exercise the bare-id favorite rule (ChsCurrentGate.swift's `itemId`
    /// comment, the 2026-08-08 fresh-install bug) on an online gate
    /// specifically, never fitted, never queued.
    func testOnlineGateUnfetchedShowsHonestyCard() throws {
        let app = launch("-chsResetModels", "-seedGate", "-networkKillSwitch",
                         "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        let result = app.staticTexts["Sechelt Rapids"].firstMatch
        XCTAssert(result.waitForExistence(timeout: 5),
                  "search did not find Sechelt Rapids by its alias")
        result.tap()

        let honesty = app.descendants(matching: .any)["online-honesty-card"].firstMatch
        XCTAssert(honesty.waitForExistence(timeout: 5),
                  "an online gate with no window must show the honesty card, never a dead end")

        // Its one tap out: the nearest of the 11 shipped (fittable) gates —
        // Dodd Narrows, ~67 km away. Bundled-identity distance, independent of
        // the fix, so this is deterministic without depending on -fixLat/-fixLon.
        let link = app.descendants(matching: .any)["nearest-gate-link"].firstMatch
        XCTAssert(link.waitForExistence(timeout: 5), "nearest-gate-link missing from the honesty card")
        if !link.isHittable { app.swipeUp() }  // it sits under the honesty card — likely already clear
        XCTAssert(link.isHittable, "nearest-gate-link exists but never became hittable")
        link.tap()

        // Scoped to the now-active detail header, not a bare name lookup: on
        // iPad the persistent sidebar can carry "Dodd Narrows" in its own Near
        // Me ranking independently of what's pushed, so the name alone is a
        // secondary tell at best.
        let header = app.otherElements["detail-map-header"].firstMatch
        XCTAssert(header.waitForExistence(timeout: 5), "nearest-gate-link did not open a detail")
        XCTAssert(header.staticTexts["Dodd Narrows"].firstMatch.exists,
                  "nearest-gate-link did not land on the nearest shipped gate's detail")

        // Back to Sechelt's own (still-honesty) detail — one pop, since the
        // link pushed rather than reset the path.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.descendants(matching: .any)["online-honesty-card"].firstMatch.waitForExistence(timeout: 5),
                  "one back from the nearest-gate-link push should land on Sechelt's own honesty card")

        // Star round-trip on the online gate itself — the bare-id rule.
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(star.waitForExistence(timeout: 5), "favorite star missing from the honesty-card detail")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].waitForExistence(timeout: 5),
                  "star did not flip to favorited on the honesty-card detail")

        // Back to the list: the favorite must RESOLVE — a Favorites group with
        // Sechelt Rapids in it, not a phantom id and no group at all.
        app.buttons["detail-back"].firstMatch.tap()
        // iPhone closes search with the push; the iPad sidebar keeps it open.
        if app.buttons["Close search"].firstMatch.exists { closeSearch(app) }
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5),
                  "favoriting an online gate produced no Favorites group — the star wrote an id the list cannot resolve")
        let row = app.staticTexts["Sechelt Rapids"].firstMatch
        XCTAssert(row.exists, "the favorited online gate is missing from the Favorites group")

        // Leave the simulator as found.
        row.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].waitForExistence(timeout: 5))
        app.buttons["Unfavorite"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "cleanup unfavorite left the Favorites group behind")
    }

    /// Seeded window: the online gate renders the exact single-track detail a
    /// real fetch would produce (`OnlineGateDetailView`'s fetched branch), and
    /// nothing from the fitted-station provisional story leaks onto it — an
    /// online gate is never queued and never fits, so there is no fast answer
    /// to mark (`ChsCurrentGateInfo.isOnline`'s exclusion from
    /// `ChsFitService.candidates`).
    func testOnlineGateFetchedRendersDetail() throws {
        // `-chsResetModels` so the seed is the ONLY window on disk: it writes
        // through the merging `saveOnline`, and the live-fetch test leaves a
        // real window for this same gate. Passing by test ordering is not
        // passing. (The reset runs first — SlackwaterApp.init touches
        // ChsFitService.shared before seeding, precisely for this.)
        let app = launch("-seedGate", "-chsResetModels",
                         "-seedOnlineWindow", "chs-sechelt-rapids",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        let result = app.staticTexts["Sechelt Rapids"].firstMatch
        XCTAssert(result.waitForExistence(timeout: 5),
                  "search did not find Sechelt Rapids by its alias")
        result.tap()

        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "the seeded window did not render the fetched strip")
        XCTAssert(app.staticTexts["NEXT SLACK"].waitForExistence(timeout: 5))  // MonoLabel uppercases
        XCTAssert(app.descendants(matching: .any).matching(identifier: "slack-window")
            .firstMatch.waitForExistence(timeout: 5), "slack window missing under Next slack")

        let provenance = app.staticTexts["online-provenance"].firstMatch
        XCTAssert(provenance.waitForExistence(timeout: 5), "provenance footer missing")
        XCTAssert(provenance.label.contains("CHS-published"),
                  "the fetched footer must say CHS-published — never claim an on-device computation")

        XCTAssert(app.descendants(matching: .any).matching(identifier: "day-sun-d0")
            .firstMatch.waitForExistence(timeout: 5), "today's schedule row missing")

        // No fitted-station provisional story belongs anywhere near this page.
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Refining'")).firstMatch.exists,
                       "an online gate can never carry the fitted-station refining strip")
        XCTAssertFalse(app.descendants(matching: .any)["provisional-reading-badge"].firstMatch.exists,
                       "an online gate can never show a fitted-station fast-answer amber reading")
        XCTAssertFalse(app.descendants(matching: .any)["online-honesty-card"].firstMatch.exists,
                       "a covering window must render the real detail, not the honesty card")

        // #38: the fetched strip (slack BANDS, unlike the derived gate's
        // droplines) must actually draw, and a normal run should leave a
        // screenshot of it — this was the only offline render of the online
        // strip and nothing ever looked at it.
        let ink = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(ink > 0.05, "the online-gate strip drew nothing — ink \(ink)")
        sleep(1)
        save(app, "online-gate-seeded.png")
    }

    /// Paging an online gate to a week nobody has downloaded, with no network,
    /// must SAY so — not render an empty strip that reads as slack water all
    /// week. Same picker choreography as `testPickingADateMovesTheWindow`, two
    /// months out so no 30-day window could cover it. The honesty card is not
    /// a dead end: the week-range bar survives it, and its picker is the way
    /// back to a week the app holds (#67 item 2) — it used to be that only the
    /// navigation back button could get you off this screen.
    func testOnlineGatePagedBeyondItsWindowOffline() throws {
        let app = launch("-seedGate", "-chsResetModels",
                         "-seedOnlineWindow", "chs-sechelt-rapids",
                         "-networkKillSwitch",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        let result = app.staticTexts["Sechelt Rapids"].firstMatch
        XCTAssert(result.waitForExistence(timeout: 5),
                  "search did not find Sechelt Rapids by its alias")
        result.tap()
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "the seeded window should render before we page off it")

        app.descendants(matching: .any)["week-range-bar"].firstMatch.tap()
        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch
            .waitForExistence(timeout: 5))
        app.buttons["Next Month"].firstMatch.tap()
        app.buttons["Next Month"].firstMatch.tap()   // two months out — past the 30-day window
        app.collectionViews.buttons.element(boundBy: 10).tap()
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()

        XCTAssert(app.descendants(matching: .any)["online-honesty-card"].firstMatch
            .waitForExistence(timeout: 5),
                  "an uncovered week offline must show the honesty card, never a dead strip")
        XCTAssertFalse(app.otherElements["timeline-strip"].exists,
                       "the strip must be GONE, not drawn flat over data nobody has")

        // #67 item 2: the honesty card is not a dead end — the bar survives it,
        // and its picker is the way back to a week the app holds.
        let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
        XCTAssert(bar.exists, "the honesty card must keep the week-range bar")
        bar.tap()
        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Previous Month"].firstMatch.tap()
        app.buttons["Previous Month"].firstMatch.tap()
        let todayCell = app.collectionViews.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'today'")).firstMatch
        XCTAssert(todayCell.exists, "the graphical picker labels today's cell")
        todayCell.tap()
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "back on the seeded week, the strip must render from disk — offline")
    }

    /// #67 item 4, hermetically: two DISJOINT seeded blocks, no network. Under
    /// the single-window store the far seed's save DISCARDED today's block, so
    /// this test's very first strip assertion is red there; and paging into the
    /// far block must render from disk, which is the multi-block payoff.
    func testOnlineGatePagesBetweenSeededBlocksOffline() throws {
        let app = launch("-seedGate", "-chsResetModels",
                         "-seedOnlineWindow", "chs-sechelt-rapids",
                         "-seedOnlineFarWindow", "chs-sechelt-rapids",
                         "-networkKillSwitch",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        let result = app.staticTexts["Sechelt Rapids"].firstMatch
        XCTAssert(result.waitForExistence(timeout: 5))
        result.tap()

        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "today's block must survive the far seed's save (single-window: it did not)")

        // today+45d always lands inside the seeded far block
        // ([today+30d, today+85d] minus the 48h back-pad and 180h forward
        // trim — 15 days of slack either side survives both), so target that
        // date directly instead of a grid index: leading-blank/spillover
        // cells shift what a fixed `boundBy` index means across month
        // layouts (this repo's CLAUDE.md documents exactly that failure
        // class). Calendar-based add, not `addingTimeInterval` — see
        // "Calendar days are not 86,400 seconds".
        let target = Calendar(identifier: .gregorian).date(byAdding: .day, value: 45, to: Date())!
        let targetLabelFormatter = DateFormatter()
        targetLabelFormatter.dateFormat = "EEEE, MMMM d"   // observed cell label shape:
                                                            // "Sunday, October 11" (no year)
        let targetLabel = targetLabelFormatter.string(from: target)

        app.descendants(matching: .any)["week-range-bar"].firstMatch.tap()
        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.waitForExistence(timeout: 5))
        let targetCell = app.collectionViews.buttons.matching(
            NSPredicate(format: "label == %@", targetLabel)).firstMatch
        // `.exists` is a no-wait snapshot; taken right after `.tap()` it races
        // the graphical calendar's month-transition animation and can read
        // false on a month the target is already in — the loop then taps past
        // it and the final check (also a bare `.exists`) fails one month late.
        // Proved by forcing that exact outcome (3 unconditional taps land on
        // November while the target is in October): `waitForExistence` gives
        // each check up to a second for the animation to settle, so a taken
        // tap can no longer be "lost" against an in-flight transition either.
        var monthsAdvanced = 0
        while !targetCell.waitForExistence(timeout: 1), monthsAdvanced < 3 {
            app.buttons["Next Month"].firstMatch.tap()
            monthsAdvanced += 1
        }
        XCTAssert(targetCell.waitForExistence(timeout: 1),
                  "today+45d cell (\(targetLabel)) not found within 3 months forward")
        targetCell.tap()
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()

        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "a far week the app holds on disk must render offline, not honesty-card")
        XCTAssertFalse(app.descendants(matching: .any)["online-honesty-card"].firstMatch.exists)
        let ink = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(ink > 0.05, "the far block's strip drew nothing — ink \(ink)")
        save(app, "online-gate-far-block.png")
    }

    /// Full-plan only (`skipUnlessFull` — run via ./scripts/test.sh --full):
    /// the spec's open item, verified against REAL IWLS rather than a seeded window.
    /// Sechelt Rapids is one of the 7 fit-reject gates (ChsCurrentGate.swift) — this
    /// proves IWLS actually resolves and serves wcsp1/wcdp1 (its station pair) for a
    /// gate CHS rejects for on-device fitting, which is the online set's entire premise.
    /// No `-networkKillSwitch`, no `-seedOnlineWindow`: `-chsResetModels` wipes any
    /// stored window so `OnlineGateDetailView.onAppear` has to fetch live. If IWLS
    /// stops resolving or serving this station, the honesty card persists and the
    /// `online-provenance` wait times out — see the failure message below, which is
    /// the actual signal this test exists to produce (Task 7 Step 3: a timeout here
    /// means Sechelt may need dropping from the online set, a human call).
    func testOnlineGateLiveFetch() throws {
        try skipUnlessFull()
        let app = launch("-seedGate", "-chsResetModels",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        let result = app.staticTexts["Sechelt Rapids"].firstMatch
        XCTAssert(result.waitForExistence(timeout: 5),
                  "search did not find Sechelt Rapids by its alias")
        result.tap()

        // Generous, M46-idiom ceiling: a live IWLS fetch, not a seeded window.
        let provenance = app.staticTexts["online-provenance"].firstMatch
        XCTAssert(provenance.waitForExistence(timeout: 300),
                  "Sechelt never fetched — check whether IWLS resolves/serves this gate")

        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "the live fetch did not render the strip")
        XCTAssert(provenance.label.contains("CHS-published"),
                  "the fetched footer must say CHS-published — never claim an on-device computation")
        XCTAssert(provenance.label.range(of: "covers to [A-Z][a-z]{2} \\d{1,2}",
                                          options: .regularExpression) != nil,
                  "provenance must carry a real covers-to date, not a placeholder")
    }

    // MARK: - Issue #91: a favorite whose station left the bundle

    /// `chs-north-galiano` is one of the 28 CHS withdrew: it shipped, it is
    /// tombstoned, and it resolves to no StationItem. Before #91 this favorite
    /// rendered as nothing at all — and with one favorite, the "FAVORITES"
    /// header vanished with it. Assert the row, not its neighbour: the card's
    /// TITLE has to be the station's real name, which is the only thing the
    /// tombstone file exists to supply.
    func testRemovedFavoriteKeepsItsRowAndOffersAReplacement() throws {
        let app = launch("-seedGate", "-resetRecents",
                         "-seedFavorites", "chs-north-galiano",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        defer {
            // Leave the simulator as found. `-seedGate` too: FavoritesStore is a
            // lazy singleton, so a relaunch that stops at the first-run gate
            // never touches it and the reset never happens.
            app.launchArguments = ["-seedGate", "-resetFavorites"]
            app.launch()
        }

        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 10),
                  "the section header went with the station it could not render")
        // The TITLE, not the presence of an amber card: the name is the one
        // thing only the tombstone file can supply, so it is the assertion.
        let title = app.staticTexts["North Galiano"].firstMatch
        XCTAssert(title.waitForExistence(timeout: 5),
                  "the removed favorite rendered no row, or rendered one it could not name")
        scrollTo(title, in: app)
        save(app, "issue91-removed-favorite.png")

        // The offer: nearest to where the station WAS. Chemainus is ~50 km up
        // island from the Victoria fix, so a chooser anchored on the user
        // instead of the tombstone would list a visibly different set.
        // ChsAmberCard's action is a .plain Button — the denied-card test reads
        // its twin as a staticText, so accept either element type.
        tapAmberAction(app, "Pick a replacement")
        // `descendants(matching: .any)`, not `otherElements`: the identifier
        // sits on the sheet's root ZStack and does not reliably surface as an
        // `otherElement` (the same reason `listContainer` queries this way).
        let sheet = app.descendants(matching: .any)["station-chooser"].firstMatch
        XCTAssert(sheet.waitForExistence(timeout: 5), "the replacement chooser did not open")
        save(app, "issue91-replacement-chooser.png")

        // THE assertion for #91's anchoring: every offer is a station near
        // where North Galiano WAS (Chemainus, ~1-4 nm) rather than near the
        // simulated Victoria fix ~30 nm south. Anchor the chooser on the user
        // instead and this named gate is nowhere in the list.
        let pick = app.staticTexts["Galiano & Valdes Islands"].firstMatch
        XCTAssert(pick.waitForExistence(timeout: 5),
                  "the chooser is ranked from the wrong position — it offered no Galiano-area station")
        pick.tap()

        // Picking swaps the favorite in place and opens the station.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5),
                  "the swap emptied Favorites instead of taking the removed station's slot")
        XCTAssertFalse(app.staticTexts["North Galiano"].firstMatch.exists,
                       "the removed station is still starred after picking a replacement")
        XCTAssert(app.staticTexts["Galiano & Valdes Islands"].firstMatch.exists,
                  "the replacement did not land in Favorites")
    }

    /// The other exit: there is no Recents to re-file a removed station to, so
    /// its swipe action is true deletion — and it has to actually be reachable.
    func testRemovedFavoriteCanBeRemovedOutright() throws {
        let app = launch("-seedGate", "-resetRecents",
                         "-seedFavorites", "chs-north-galiano",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        defer {
            // Leave the simulator as found. `-seedGate` too: FavoritesStore is a
            // lazy singleton, so a relaunch that stops at the first-run gate
            // never touches it and the reset never happens.
            app.launchArguments = ["-seedGate", "-resetFavorites"]
            app.launch()
        }

        let title = app.staticTexts["North Galiano"].firstMatch
        XCTAssert(title.waitForExistence(timeout: 10))
        scrollTo(title, in: app)
        title.swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssert(remove.waitForExistence(timeout: 5), "no swipe action on the removed-station row")
        remove.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["North Galiano"].firstMatch.exists,
                       "the removed favorite came back")
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "the only favorite is gone — the group should be too")
    }

    /// ChsAmberCard's action renders as a `.plain` Button whose label is an
    /// HStack; whether XCUI surfaces it as a button or a static text has
    /// differed by card, so try both rather than guess.
    private func tapAmberAction(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons[label].firstMatch
        if button.exists { button.tap(); return }
        let text = app.staticTexts[label].firstMatch
        XCTAssert(text.waitForExistence(timeout: 5), "amber action \"\(label)\" is not on screen")
        text.tap()
    }
}
