// Slackwater — GPL v3. The station detail: its readouts, its map header,
// the timeline strip, and everything that scrubs it.
//
// One of the weight-balanced screenshot classes — see ScreenshotTestCase.swift
// for the helpers and for why the suite is split this way.
import UIKit
import XCTest

final class DetailAndScrubTests: ScreenshotTestCase {
    func testM1Walkthrough() throws {
        // The app launches on the list — when located it ranks by distance, so
        // reach Friday Harbor through search (deterministic either way).
        let app = launch("-seedGate")

        // Units live in Settings only (no list pill): reset to feet first —
        // the setting persists across runs.
        setUnits(app, "Feet")

        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        _ = strip.waitForExistence(timeout: 10)
        settleLayout(strip)  // the push animation is still moving the strip

        // Scrub: pan the strip under the fixed centerline (drag left = later),
        // release — the readout keeps the scrubbed time.
        scrubStrip(app)
        settleScrub(app)
        save(app, "m1-detail-scrubbed.png")

        // Back to the station list (search closed itself on the pick).
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        settleLayout(app.staticTexts["Slackwater"].firstMatch)  // the pop slides the list in
        save(app, "m1-list.png")

        // Search mid-query: name + region substring both match (bottom input).
        openSearch(app, "pass")
        // the truncation notice is the app's own "results are rendered" signal
        _ = app.descendants(matching: .any)["search-truncated"].firstMatch
            .waitForExistence(timeout: 10)
        save(app, "m1-search.png")
        // "pass" matches 139 stations nationally and results are ranked by
        // DISTANCE, not name — Active Pass sits eighth, not first
        // (Race Passage, then five San Juan passes, are nearer to
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
        // the rate line re-rendered in metres is the unit switch landing
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'm/hr'"))
            .firstMatch.waitForExistence(timeout: 10)
        save(app, "m1-detail-metric.png")
        // Leave the store imperial for the other tests.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        setUnits(app, "Feet")
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

    /// #170: provenance stays out of the primary tide-reading flow until the
    /// sailor asks for it, then exposes the support/debugging facts in place.
    func testStationDetailsAreCollapsedUntilOpened() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)

        let details = app.buttons["Station details"].firstMatch
        XCTAssert(details.waitForExistence(timeout: 10), "no Station details disclosure")
        XCTAssertFalse(app.staticTexts["noaa/9449880"].exists,
                       "station details should start collapsed")

        details.tap()
        XCTAssert(app.staticTexts["noaa/9449880"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["MLLW (NOAA chart datum)"].exists)
        XCTAssert(app.staticTexts["48.545°N, 123.013°W"].exists)
        XCTAssert(app.staticTexts["America/Los_Angeles"].exists)
        save(app, "station-details-expanded.png")
    }

    /// The range bar heads the schedule card on every scrubable detail and says
    /// what span the list below it covers; tapping it opens the picker, and
    /// picking a date moves the window with the bar following.
    ///
    /// The bar-exists-and-states-a-span check is the first three lines here
    /// rather than a test of its own — a launch costs ~6 s and this test
    /// already waits for the same element to read `before`.
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
        XCTAssert(app.buttons["detail-return-now"].waitForExistence(timeout: 5),
                  "picking a future week left the centerline on today: no return-to-now")

        // And the chart has to actually DRAW. The assertion above passes on a
        // blank strip: every readout, label and schedule row can be right for
        // the picked week while the canvas renders nothing, because the window
        // narrows when the anchor leaves today and the scroll view keeps its
        // old width. Nothing inside the strip is an accessibility element (it
        // is all one `Canvas`), so ink coverage is what a test can see.
        let ink = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(ink > 0.05, "the strip drew nothing after the pick — ink \(ink)")
        save(app, "picker-week-moved.png")

        // Back the other way, which is the same resize in reverse: today's
        // window is the WIDER one (it alone carries the 48h look-back), so a
        // fix that only handled the shrink would blank the strip on the way
        // home. "Today" is in the schedule's day column only when the anchor is
        // today — it is absent for the whole September week above.
        app.buttons["detail-return-now"].tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5),
                  "return-to-now did not bring the window back to today")
        let homeInk = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(homeInk > 0.05, "the strip drew nothing back on today — ink \(homeInk)")
    }

    // The detail header is the station map with the title overlaid, the
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
        sleep(6)  // header map tiles: MLNMapView surfaces no load state to XCUITest
        save(app, "m41-detail-mapheader.png")

        // The map header carries the current-station detail too.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 5),
                  "map header missing from current detail")
        XCTAssert(app.descendants(matching: .any).matching(identifier: "day-sun-d0")
            .firstMatch.waitForExistence(timeout: 5),
                  "sun times missing from the current-station day header")
        XCTAssertFalse(app.staticTexts["☀ RISE"].firstMatch.exists,
                       "sun rows have moved to the day header — none in the current-station schedule")
    }

    // The continuous scrub — a fixed centerline with the multi-day strip
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
            settleLayout(tomorrowRow)  // deceleration, before the frame is read again
            tries += 1
        }
        tomorrowRow.tap()
        // The floating chart readout intentionally contains only the changing
        // time/value. Its calendar context lives in the fixed day rail, so the
        // return-to-now control is the stable proof that this cross-day row
        // moved the scrub away from the present.
        XCTAssert(app.buttons["Return to now"].firstMatch.waitForExistence(timeout: 5),
                  "readout did not follow the cross-midnight scrub")
        app.swipeDown()

        // Return to now restores the live reading and hides the control.
        app.buttons["Return to now"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Return to now"].firstMatch.waitForExistence(timeout: 2),
                       "return-to-now did not restore the live readout")
    }

    // The riding dot: initial centering must happen at the first layout, not
    // the first magnet settle. Honest check: the very FIRST scrub must move the
    // centerline readout with the gesture — if `scrubTime` stays frozen until
    // the settle recomputes everything, the dot floats off the curve. The read
    // lands mid-deceleration, before any settle.
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

    /// Return-to-now owns a fixed slot — below the hero, in the scrub card's
    /// readout row, hard right beside the star — so it can appear and disappear
    /// without moving anything. Sharing the header's top-right row with the
    /// favourite star shoves the star sideways the moment you scrub.
    func testM52ReturnToNowHasItsOwnFixedSlot() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5))

        let star = app.buttons["detail-favorite"].firstMatch
        let back = app.buttons["detail-back"].firstMatch
        XCTAssert(star.waitForExistence(timeout: 5))
        let starBefore = star.frame, backBefore = back.frame
        let now = app.buttons["detail-return-now"]
        XCTAssertFalse(now.exists, "return-to-now must not show before a scrub")

        scrubStrip(app)
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
        // scrub card, directly beside the time/date stack on the LEADING side —
        // next to the time it resets.
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
        _ = now.waitForNonExistence(timeout: 10)
        XCTAssertFalse(app.buttons["detail-return-now"].exists,
                       "return-to-now did not clear after returning to now")
        XCTAssertEqual(settled { star.frame }.minX, starBefore.minX, accuracy: 0.5,
                       "the star moved when return-to-now went away")
    }}
