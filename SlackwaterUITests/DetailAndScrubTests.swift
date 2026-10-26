// Slackwater — GPL v3. The station detail: its readouts, its map header,
// the timeline strip, and everything that scrubs it.
//
// One of the weight-balanced screenshot classes — see ScreenshotTestCase.swift
// for the helpers and for why the suite is split this way.
import UIKit
import XCTest

final class DetailAndScrubTests: ScreenshotTestCase {
    func testWideSummaryCards() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch("-locDenied")
        openFridayHarbor(app)
        let sun = app.buttons["sun-card-details"].firstMatch
        scrollTo(sun, in: app)
        XCTAssertTrue(sun.appears(within: 5))
        let moon = app.buttons["tile-moon"].firstMatch
        let range = app.buttons["tile-primary"].firstMatch
        XCTAssertGreaterThan(sun.frame.maxX - range.frame.minX, 700)
        XCTAssertEqual(sun.frame.width, moon.frame.width, accuracy: 1)
        XCTAssertGreaterThan(range.frame.width, sun.frame.width * 1.9)
        XCTAssertEqual(range.frame.minY, sun.frame.minY, accuracy: 1)
        XCTAssertEqual(moon.frame.minY, sun.frame.minY, accuracy: 1)
        XCTAssertEqual(range.frame.height, sun.frame.height, accuracy: 1)
        save(app, "summary-cards-ipad.png")
    }

    func testScheduleSunDetails() throws {
        let app = launch("-locDenied")
        openFridayHarbor(app)
        let row = app.buttons["sun-card-details"].firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.appears(within: 5))
        XCTAssertFalse(row.label.contains("Solar noon"))
        let moon = app.buttons["tile-moon"].firstMatch
        let range = app.buttons["tile-primary"].firstMatch
        XCTAssertEqual(row.frame.width, moon.frame.width, accuracy: 1)
        XCTAssertEqual(row.frame.minY, moon.frame.minY, accuracy: 1)
        XCTAssertEqual(row.frame.height, moon.frame.height, accuracy: 1)
        XCTAssertGreaterThan(range.frame.width, row.frame.width * 1.9)
        XCTAssertLessThanOrEqual(range.frame.height, moon.frame.height + 1)
        if row.frame.maxX - range.frame.minX >= 700 {
            XCTAssertEqual(range.frame.minY, row.frame.minY, accuracy: 1)
        } else {
            XCTAssertLessThan(range.frame.minY, row.frame.minY)
        }
        XCTAssertTrue(row.label.hasPrefix("Sun, Sunrise"), row.label)
        XCTAssertFalse(app.buttons["sun-card-previous"].exists)
        XCTAssertFalse(app.buttons["sun-card-next"].exists)
        save(app, "sun-card.png")
        row.tap()
        let next = app.buttons["sun-next-event"]
        XCTAssertTrue(next.appears(within: 5))
        let initialPrevious = app.buttons["sun-previous-event"]
        XCTAssertTrue(initialPrevious.label.contains("Sunset"), initialPrevious.label)
        XCTAssertTrue(initialPrevious.label.contains("Yesterday"), initialPrevious.label)
        XCTAssertTrue(next.label.contains("Sunrise"), next.label)
        let distance = app.descendants(matching: .any)["sun-distance"].firstMatch
        XCTAssertTrue(distance.exists)
        XCTAssertGreaterThan(distance.frame.minY, next.frame.maxY)
        let dawn = app.descendants(matching: .any)["sun-event-astroDawn"].firstMatch
        XCTAssertLessThan(distance.frame.maxY, dawn.frame.minY)
        XCTAssertTrue(app.buttons["sun-perihelion"].exists)
        XCTAssertTrue(app.buttons["sun-aphelion"].exists)
        save(app, "sun-details.png")
        let destination = try XCTUnwrap(next.value as? String)
        next.tap()
        XCTAssertTrue(app.navigationBars["Sun activity"].disappears(within: 10))
        XCTAssertTrue(waitFor(leadReading(app), "value ENDSWITH '\(destination)'"))
        row.tap()
        let previous = app.buttons["sun-previous-event"]
        XCTAssertTrue(previous.appears(within: 5))
        XCTAssertTrue(previous.label.contains("Yesterday"), previous.label)
        let earlier = try XCTUnwrap(previous.value as? String)
        XCTAssertNotEqual(earlier, destination)
        previous.tap()
        XCTAssertTrue(app.navigationBars["Sun activity"].disappears(within: 10))
        XCTAssertTrue(waitFor(leadReading(app), "value ENDSWITH '\(earlier)'"))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["sun-event-astroDawn"].firstMatch.appears(within: 5))
        XCTAssertFalse(app.descendants(matching: .any)["sun-eye-height"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["sun-horizon-dip"].firstMatch.exists)
        var previousY = -Double.infinity
        for kind in ["astroDawn", "nauticalDawn", "morningBlueStart", "civilDawn", "morningBlueEnd", "rise",
                     "morningGoldenEnd", "transit", "eveningGoldenStart", "set", "eveningBlueStart",
                     "civilDusk", "eveningBlueEnd", "nauticalDusk", "astroDusk"] {
            let event = app.descendants(matching: .any)["sun-event-\(kind)"].firstMatch
            XCTAssertTrue(event.exists, kind)
            XCTAssertGreaterThan(event.frame.minY, previousY, kind)
            previousY = event.frame.minY
        }
        let daylight = app.descendants(matching: .any)["sun-daylight"].firstMatch
        XCTAssertGreaterThan(daylight.frame.minY, previousY)
        // Every row is a destination: the sheet closes and the timeline lands on the row's time.
        let golden = app.descendants(matching: .any)["sun-event-eveningGoldenStart"].firstMatch
        let clock = try XCTUnwrap(golden.label.components(separatedBy: ", ").last)
        XCTAssertNotEqual(scrubClock(app), clock)
        golden.tap()
        XCTAssertTrue(app.navigationBars["Sun activity"].disappears(within: 10),
                      "the sheet stayed up after a jump")
        XCTAssertTrue(waitFor(leadReading(app), "value ENDSWITH '\(clock)'"),
                      "the timeline did not land on \(clock): \(scrubClock(app))")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let perihelion = app.buttons["sun-perihelion"]
        XCTAssertTrue(perihelion.appears(within: 5))
        let apsisClock = try XCTUnwrap(perihelion.value as? String)
        perihelion.tap()
        XCTAssertTrue(app.navigationBars["Sun activity"].disappears(within: 10))
        XCTAssertTrue(waitFor(leadReading(app), "value ENDSWITH '\(apsisClock)'"))
    }

    func testM1Walkthrough() throws {
        // The app launches on the list — when located it ranks by distance, so
        // reach Friday Harbor through search (deterministic either way).
        // The Victoria fix is pinned because the SEARCH step below depends on
        // it: results rank by distance from the live anchor, and the scroll
        // loop's budget only reaches Active Pass from a Salish Sea anchor. A
        // dev machine with a custom simulator location (or none) ranks from
        // somewhere else entirely.
        // Hosted runners have dropped this walk's scrub (#664); the native trace says
        // whether the drag's hit test reached the strip and whether its pan began.
        let app = launch("-fixLat", "48.4235", "-fixLon", "-123.3705",
                         "-scrubTrace", "\(shotDir)/m1-scrub-\(UUID().uuidString).log")

        // Units live in Settings only (no list pill): start this walk in feet.
        setUnits(app, "Feet")

        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        _ = strip.appears(within: 10)
        settleLayout(strip)  // the intro is still sliding the strip to now

        // Scrub: pan the strip under the fixed centerline (drag left = later),
        // release — the lead keeps the scrubbed time. The lead is the page's
        // one readout and combines its children, so its whole label is what a
        // test can read; comparing it across the drag is the scrub landing.
        let lead = leadReading(app)
        XCTAssert(lead.appears(within: 10), "no lead reading on the tide detail")
        let leadBefore = lead.label
        scrubStrip(app)
        settleScrub(app)
        XCTAssertNotEqual(lead.label, leadBefore,
                          "the scrub left the lead reading unchanged")
        save(app, "m1-detail-scrubbed.png")

        // Back to the station list (search closed itself on the pick).
        goBack(app)
        settleLayout(stationList(app).firstMatch)  // the pop slides the list in
        save(app, "m1-list.png")

        // Search mid-query: name + region substring both match (bottom input).
        openSearch(app, "pass")
        // the truncation notice is the app's own "results are rendered" signal
        _ = app.descendants(matching: .any)["search-truncated"].firstMatch
            .appears(within: 10)
        save(app, "m1-search.png")
        // "pass" matches 139 stations nationally and results are ranked by
        // DISTANCE, not name — Active Pass sits eighth, not first
        // (Race Passage, then five San Juan passes, are nearer to
        // the Victoria fix). Scroll for both rather than assume the fold.
        // The results scroller fills the whole overlay — the keyboard and the
        // floating controls are content insets, not frame — so `swipeUp()`
        // from the ELEMENT's center starts the gesture on the keyboard and
        // scrolls nothing. Drag inside the visible results region instead,
        // where a thumb scrolls.
        let overlay = app.scrollViews.firstMatch
        for name in ["Active Pass", "Deception Pass (Narrows)"] {
            let card = app.staticTexts[name].firstMatch
            var tries = 0
            while !card.exists, tries < 8 {
                overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
                    .press(forDuration: 0.05, thenDragTo:
                        overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
                tries += 1
            }
            XCTAssert(card.exists, "search did not find \(name)")
        }
        closeSearch(app)

        // Metres via Settings, then open Friday Harbor in metric.
        setUnits(app, "Meters")
        openFridayHarbor(app)
        // the lead re-rendered in metres is the unit switch landing. The
        // height and its unit are one Text inside the combined label, so the
        // digit-then-unit match holds however the label is joined.
        XCTAssert(waitFor(leadReading(app), "label MATCHES '.*\\\\d m.*'"),
                  "the lead did not re-render in metres: \(leadReading(app).label)")
        save(app, "m1-detail-metric.png")
    }

    /// #95: the tide detail says where the water is and how big this swing is
    /// — a height under the centerline and a Range tile beside the moon. How
    /// fast it is moving is the lead glyph's colour, which no query can read,
    /// so the readable half is what this pins. Friday Harbor reads small; the
    /// point is the figures exist at every station, so Ile Haute's 32 ft can't
    /// hide.
    func testTideReadoutShowsHeightAndRange() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments([])
        app.launch()
        XCTAssert(stationList(app).appears(within: 10))

        openFridayHarbor(app)
        let lead = leadReading(app)
        XCTAssert(lead.appears(within: 10), "no lead reading on the tide detail")
        XCTAssert(lead.label.contains("ft"),
                  "the lead must carry the height and its unit, got '\(lead.label)'")
        // Case-insensitive: the tile's eyebrow combines a MonoLabel that
        // uppercases with an accessibility label that does not.
        let range = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] 'range'")).firstMatch
        XCTAssert(range.exists, "no Range tile beside the moon")
        save(app, "tide-readout-height-range.png")
    }

    /// A tap on the strip brings that moment to the centerline — the fast way
    /// across a week that dragging measures out an hour at a time. Every label
    /// on the strip is a moment and scrubs to itself, sunrise included; the
    /// date under the day is the one that names a DAY rather than a moment, so
    /// it opens the picker instead.
    func testTappingTheStripScrubsAndTheDateOpensThePicker() throws {
        let app = launch("-scrubTrace", "\(shotDir)/strip-tap-\(UUID().uuidString).log")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 10), "timeline strip missing")
        settleLayout(strip)  // the intro is still sliding the strip to now
        settleScrub(app)

        // Well right of the centerline, in the plot box: hours away from now,
        // whichever stop the magnet finishes on.
        let opening = scrubClock(app)
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6)).tap()
        settleScrub(app)  // the tap rides an animated scroll to the stop
        let afterTap = scrubClock(app)
        if afterTap == opening {
            save(app, "strip-tap-frozen.png")
            XCTContext.runActivity(named: "Strip-tap UI hierarchy") { activity in
                let attachment = XCTAttachment(string: app.debugDescription)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
        XCTAssertNotEqual(afterTap, opening,
                          "a tap on the strip left the centerline on \(opening)")
        save(app, "strip-tap-scrubbed.png")

        // Pick a date, for the geometry the rest of this test needs: the
        // centerline parks on the picked day's NOON, which is where its date
        // label is drawn, with that day's sun labels either side of it. Nothing
        // else puts a known label under a known point of the strip — where the
        // centerline sits on arrival depends on the clock the test runs at.
        let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
        XCTAssert(bar.appears(within: 10), "no range bar above the schedule")
        let week = bar.label
        bar.tap()
        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.appears(within: 5))
        stepMonth(app, "Next Month")
        tapDay(app.collectionViews.buttons.element(boundBy: 10))
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()
        XCTAssert(waitFor(bar, "label != '\(week)'"), "the pick did not move the window")
        settleScrub(app)
        let noon = scrubClock(app)

        // The date, under the centerline: the picker, and the strip left where
        // it was when the sheet goes away.
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        let picker = app.descendants(matching: .any)["week-picker"].firstMatch
        XCTAssert(picker.appears(within: 5), "a tap on the date did not open the picker")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssert(waitFor(picker, "exists == false"), "the picker did not close")

        // The sunrise label, left of the date on the same row. Friday Harbor's
        // sun rises 4–7 hours before noon whatever the season, so a quarter of
        // the way across the strip is nearer the sunrise than the date by a
        // clear margin at any anchor the picker can reach.
        let sun = app.buttons["sun-card-details"].firstMatch
        XCTAssert(sun.exists, "no Sun card below the summary tiles")
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.95)).tap()
        settleScrub(app)
        XCTAssertFalse(picker.exists, "a tap on the sunrise opened the picker")
        let sunrise = scrubClock(app)
        sun.tap()
        let rise = app.descendants(matching: .any)["sun-event-rise"].firstMatch
        XCTAssertTrue(rise.appears(within: 5))
        XCTAssertTrue(rise.label.contains(sunrise),
                      "the sunrise tap left the centerline on \(sunrise), outside '\(rise.label)' (noon was \(noon))")
        app.buttons["Done"].tap()
        save(app, "strip-tap-sunrise.png")
    }

    /// #170: provenance stays out of the primary tide-reading flow until the
    /// sailor asks for it, then exposes the support/debugging facts in place.
    func testStationDetailsAreCollapsedUntilOpened() throws {
        let app = launch()
        openFridayHarbor(app)

        let details = app.buttons["Station details"].firstMatch
        XCTAssert(details.appears(within: 10), "no Station details disclosure")
        XCTAssertFalse(app.staticTexts["noaa/9449880"].exists,
                       "station details should start collapsed")

        details.tap()
        XCTAssert(app.staticTexts["noaa/9449880"].appears(within: 5))
        XCTAssert(app.staticTexts["MLLW (NOAA chart datum)"].exists)
        XCTAssert(app.staticTexts["48.545°N, 123.013°W"].exists)
        XCTAssert(app.staticTexts["America/Los_Angeles"].exists)
        save(app, "station-details-expanded.png")
    }

    /// Every detail closes on Nearby: the shared filter narrows its rows, a
    /// row pushes that station, and a tap off the pins opens the full map.
    func testNearbyFiltersOpensAStationAndOpensTheMap() throws {
        let app = launch()
        openFridayHarbor(app)

        let nearby = app.descendants(matching: .any)["nearby"].firstMatch
        XCTAssert(nearby.appears(within: 10), "no Nearby section on the detail")
        nearby.descendants(matching: .any)["series-filter-currents"].firstMatch.tap()
        let rows = nearby.descendants(matching: .any).matching(identifier: "nearby-station")
        XCTAssert(rows.firstMatch.appears(within: 5), "Nearby lists no stations")
        XCTAssertEqual(rows.count, 6)
        for row in rows.allElementsBoundByIndex {
            XCTAssert(row.label.contains("Current"), "the Currents filter let through '\(row.label)'")
        }
        save(app, "nearby-currents.png")

        // Friday Harbor has a current station of its own, so pick a row whose
        // name is not the page's — otherwise the title check proves nothing.
        let row = try XCTUnwrap(rows.allElementsBoundByIndex.first { !$0.label.hasPrefix("Friday Harbor") })
        let name = try XCTUnwrap(row.label.components(separatedBy: ", ").first)
        row.tap()
        let title = app.descendants(matching: .any)["detail-title"].firstMatch
        wait(for: [expectation(for: NSPredicate(format: "label BEGINSWITH %@", name),
                               evaluatedWith: title)], timeout: 10)

        let map = nearby.descendants(matching: .any)["nearby-map"].firstMatch
        goBack(app, to: map)
        XCTAssert(map.appears(within: 10), "back from the pushed station lost the Nearby map")
        // A coordinate tap never scrolls, and the map sits below the rows.
        let window = app.windows.firstMatch.frame
        for _ in 0..<6 where map.frame.maxY > window.maxY - 40 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
                .press(forDuration: 0.1, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)))
        }
        XCTAssert(map.frame.maxY <= window.maxY - 40, "the Nearby map stayed below the screen")
        save(app, "nearby-map.png")
        // Clear of the iPad scroll bar and the iPhone's top-right station pin.
        let tapX = UIDevice.current.userInterfaceIdiom == .pad ? 0.8 : 0.97
        map.coordinate(withNormalizedOffset: CGVector(dx: tapX, dy: 0.05)).tap()
        XCTAssert(app.descendants(matching: .any)["map-canvas"].firstMatch.appears(within: 10),
                  "a tap on the Nearby map did not open the full map")
    }

    /// The picker sheet fits a six-week month. At the `.medium` detent the iPad
    /// sheet clipped the calendar's lower rows, and a tap on one landed outside
    /// the sheet and closed it without picking. August 2026 starts on a
    /// Saturday, so its 31st is on the sixth row.
    func testPickerReachesTheSixthWeek() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments([])
        app.launch()
        XCTAssert(stationList(app).appears(within: 10))

        openFridayHarbor(app)
        let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
        XCTAssert(bar.appears(within: 10), "no range bar above the schedule")
        let before = bar.label
        bar.tap()
        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.appears(within: 5))

        // The fixture clock opens the picker on September 2026.
        stepMonth(app, "Previous Month")
        save(app, "week-picker-six-weeks.png")
        tapDay(app.collectionViews.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Monday, August 31")).firstMatch)
        let show = app.descendants(matching: .any)["week-picker-done"].firstMatch
        XCTAssert(show.appears(within: 5), "a tap on the sixth week closed the picker")
        show.tap()
        XCTAssert(waitFor(bar, "label != '\(before)'"), "picking August 31 did not move the window")
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
        app.launchArguments = testArguments([])
        app.launch()
        XCTAssert(stationList(app).appears(within: 10))

        openFridayHarbor(app)
        let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
        XCTAssert(bar.appears(within: 10), "no range bar above the schedule")
        XCTAssert(bar.label.contains("–"), "the bar states a span, got '\(bar.label)'")
        let before = bar.label

        bar.tap()
        let picker = app.descendants(matching: .any)["week-picker"].firstMatch
        XCTAssert(picker.appears(within: 5))

        // The graphical DatePicker's forward-month button, then a day cell.
        stepMonth(app, "Next Month")
        tapDay(app.collectionViews.buttons.element(boundBy: 10))
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()
        // The bar stays put and rewrites itself once the sheet's pick lands,
        // so wait for the label the next line reads, not for the bar (#341).
        XCTAssert(waitFor(bar, "label != '\(before)'"),
                  "the bar did not move off '\(before)' after Done")
        XCTAssertNotEqual(bar.label, before, "the bar must follow the anchor")

        // The centerline has to move WITH the window. It does not follow on its
        // own — the strip's x/time conversions are exact inverses, so a
        // programmatic scroll to an off-window `scrubTime` reads straight back
        // as the same off-window time and the strip draws blank. The
        // observable proof is this button: parking the centerline on the picked
        // week puts `scrubTime` far from now, and return-to-now is what shows
        // when it is. Without it there is no way back to today at all — the
        // range bar opens the picker, not today.
        XCTAssert(app.buttons["detail-return-now"].appears(within: 5),
                  "picking a future week left the centerline on today: no return-to-now")

        // And the chart has to actually DRAW. The assertion above passes on a
        // blank strip: every readout, label and schedule row can be right for
        // the picked week while the canvas renders nothing, because the window
        // narrows when the anchor leaves today and the scroll view keeps its
        // old width. Nothing inside the strip is an accessibility element (it
        // is all one `Canvas`), so ink coverage is what a test can see.
        let ink = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(ink > Self.drawnStripInk, "the strip drew nothing after the pick — ink \(ink)")
        save(app, "picker-week-moved.png")

        // Back the other way, which is the same resize in reverse: today's
        // window is the WIDER one (it alone carries the 48h look-back), so a
        // fix that only handled the shrink would blank the strip on the way
        // home. The range label, not "Today" in the day column: "Today" shows
        // for any anchor up to six days behind today.
        returnToNow(app)
        XCTAssert(waitFor(bar, "label == '\(before)'"),
                  "return-to-now left the bar on '\(bar.label)', not '\(before)'")
        let homeInk = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(homeInk > Self.drawnStripInk, "the strip drew nothing back on today — ink \(homeInk)")
    }

    // The detail header carries the title, the day header carries the sun
    // times, and the summary tile names the moon phase.
    func testM41DetailHeaderSunMoon() throws {
        let app = launch()
        openFridayHarbor(app)
        XCTAssert(app.otherElements["detail-header"].appears(within: 5),
                  "header missing from tide detail")
        XCTAssert(app.descendants(matching: .any).matching(identifier: "sun-card-details")
            .firstMatch.appears(within: 5),
                  "Sun card missing below the summary tiles")
        XCTAssertFalse(app.staticTexts["☀ RISE"].firstMatch.exists,
                       "sun rows have moved to the day header — none in the schedule")
        // The eclipse names belong here too (#222): on an eclipse night the
        // Moon tile reads "Partial Eclipse" instead of "Full Moon", and this
        // test runs against the real clock — without them it fails on a real
        // day, for whoever happens to run the suite that week.
        let phaseNames = "New Moon|Waxing Crescent|First Quarter|Waxing Gibbous|Full Moon|Waning Gibbous|Last Quarter|Waning Crescent|Penumbral Eclipse|Partial Eclipse|Total Eclipse"
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", phaseNames)).firstMatch.exists,
                  "moon phase name missing from the scrub readout")
        save(app, "m41-detail-header.png")

        // The header carries the current-station detail too.
        goBack(app)
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.otherElements["detail-header"].appears(within: 5),
                  "header missing from current detail")
        save(app, "m41-current-detail-header.png")
        XCTAssert(app.descendants(matching: .any).matching(identifier: "sun-card-details")
            .firstMatch.appears(within: 5),
                  "Sun card missing from the current detail")
        XCTAssertFalse(app.staticTexts["☀ RISE"].firstMatch.exists,
                       "sun rows have moved to the day header — none in the current-station schedule")
    }

    func testM42DayHeaderSpansTheSchedule() {
        let app = launch()
        openFridayHarbor(app)

        let tomorrowDay = app.buttons.matching(identifier: "schedule-day-d1").firstMatch
        XCTAssert(tomorrowDay.appears(within: 5), "Tomorrow's day header is not expandable")
        // Against today's open row, not the window: the iPad split puts the
        // schedule in the detail column, where spanning it is ~58% of the window.
        let todayRow = app.buttons.matching(identifier: "schedule-row-d0").firstMatch
        XCTAssert(todayRow.appears(within: 5), "today's rows should start expanded")
        XCTAssertGreaterThanOrEqual(tomorrowDay.frame.width, todayRow.frame.width - 1,
                                    "the day header should span the schedule with its chevron trailing")
        let laterDay = app.buttons.matching(identifier: "schedule-day-d2").firstMatch
        scrollTo(laterDay, in: app)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let later = calendar.date(byAdding: .day, value: 2, to: Self.fixtureDate)!
        XCTAssert(laterDay.staticTexts[formatter.string(from: later)].exists,
                  "a day beyond Tomorrow must show its date")
        save(app, "schedule-dates.png")
    }

    // The fixed centerline stays put while the multi-day strip pans underneath.
    func testM42ContinuousScrubAcrossMidnight() throws {
        let app = launch()
        openFridayHarbor(app)
        XCTAssert(app.otherElements["timeline-strip"].appears(within: 5),
                  "pan-under-centerline strip missing from tide detail")

        settleScrub(app)
        let liveClock = scrubClock(app)

        // Pan the strip while its midpoint is visible: the centerline readout moves off "now".
        scrubStrip(app)
        XCTAssert(app.buttons["Return to now"].appears(within: 5),
                  "return-to-now affordance missing after scrubbing away")

        // Later days stay compact until the sailor asks for one.
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        XCTAssert(app.staticTexts["Tomorrow"].appears(within: 5),
                  "multi-day schedule missing its Tomorrow day header")
        XCTAssert(app.buttons.matching(identifier: "schedule-row-d0").firstMatch.exists,
                  "today's rows should start expanded")
        let tomorrowRow = app.buttons.matching(identifier: "schedule-row-d1").firstMatch
        XCTAssertFalse(tomorrowRow.exists, "Tomorrow's rows should start collapsed")
        let tomorrowDay = app.buttons.matching(identifier: "schedule-day-d1").firstMatch
        XCTAssert(tomorrowDay.exists, "Tomorrow's day header is not expandable")
        // The scrub above re-anchors the schedule under this header, and a tap
        // taken while it reflows is dropped. Settle it, then a bounded retap
        // with the rows appearing as the landed signal (pickSearchResult's
        // shape). A retap cannot fold the day back: it only fires while the
        // rows are still absent. `exists`, not `isHittable`: the header
        // reports unhittable (its hit point resolves to the label inside)
        // while a tap on it lands — guarded on hittability, no tap was ever
        // synthesized.
        settleLayout(tomorrowDay)
        var expanded = false
        for _ in 0..<3 {
            if tomorrowDay.exists { tomorrowDay.tap() }
            if tomorrowRow.appears(within: 5) { expanded = true; break }
        }
        XCTAssert(expanded, "Tomorrow's rows did not expand")
        XCTAssertFalse(app.buttons.matching(identifier: "schedule-row-d0").firstMatch.exists,
                       "opening Tomorrow should collapse Today")

        // Down the multi-day list. (One swipe first: schedule-row-d1 may not
        // be realized until it scrolls near the fold — the loop below only
        // clears the home-indicator band once the row exists.)
        app.swipeUp()

        // Tap one of Tomorrow's rows: the scrub crosses midnight to it. A row
        // hugging the bottom edge "taps" without firing (the touch lands in
        // the home-indicator band — seen on iPad landscape), so scroll until
        // it sits clear of the edge first.
        XCTAssert(tomorrowRow.appears(within: 5), "no Tomorrow rows in the schedule")
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
        XCTAssert(app.buttons["Return to now"].firstMatch.appears(within: 5),
                  "readout did not follow the cross-midnight scrub")
        returnToNow(app)
        XCTAssertEqual(scrubClock(app), liveClock,
                       "return-to-now did not restore the live readout")
    }

    // The riding dot: initial centering must happen at the first layout, not
    // the first magnet settle. Honest check: the very FIRST scrub must move the
    // centerline readout with the gesture — if `scrubTime` stays frozen until
    // the settle recomputes everything, the dot floats off the curve. The read
    // lands mid-deceleration, before any settle.
    func testM43FirstScrubDotRidesCurve() throws {
        let app = launch("-scrubTrace", "\(shotDir)/first-scrub-\(UUID().uuidString).log")
        openFridayHarbor(app)

        // First frame after appearance — no scrub, no settle yet.
        XCTAssert(leadReading(app).appears(within: 5))
        let before = scrubClock(app)

        // The FIRST drag on a fresh detail: the readout must move during the
        // gesture itself (read mid-deceleration, pre-settle), not only after
        // the magnet settles.
        scrubStrip(app)
        let after = scrubClock(app)
        if before == after {
            save(app, "first-scrub-frozen.png")
            XCTContext.runActivity(named: "First-drag UI hierarchy") { activity in
                let attachment = XCTAttachment(string: app.debugDescription)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
        XCTAssertNotEqual(before, after,
                          "first scrub left the readout frozen — see the gesture trace and UI hierarchy")
    }

    /// #280: rotating an iPad kept the strip's `contentOffset` while its width
    /// changed, so the curve under the centerline drifted half the width
    /// change away from the readout until the next state change. The lead
    /// carries `scrubTime`; the strip's scroll view publishes the time
    /// actually under the centerline as its value. Both must agree through
    /// portrait → landscape → portrait, on the tide detail (all four detail
    /// screens share `TimelineScrubber`).
    func testRotationKeepsCurveUnderTheReadout() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only rotation test")
        }
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }
        let app = launch("-scrubInstant", "2026-09-09T09:54:00-07:00")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5), "timeline strip missing")
        XCTAssertEqual(scrubClock(app), localizedClock("09:54"), "the fixture moment did not land")
        let before = try assertStripCentre(app)

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            device.orientation = orientation
            settleLayout(strip)
            let readout = try assertStripCentre(app)
            XCTAssertEqual(readout, before, "rotation changed the readout")
        }
    }

    private func assertStripCentre(_ app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let values = settled {
            [leadReading(app).value as? String ?? "",
             app.otherElements["timeline-strip"].scrollViews.firstMatch.value as? String ?? ""]
        }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.defaultDate = Self.fixtureDate
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMd", options: 0, locale: formatter.locale)!
            + " '·' " + DateFormatter.dateFormat(fromTemplate: "jm", options: 0, locale: formatter.locale)!
        let readout = try XCTUnwrap(formatter.date(from: values[0]), "unreadable readout: \(values[0])", file: file, line: line)
        formatter.setLocalizedDateFormatFromTemplate("MMMMdjmz")
        let spokenTime = values[1].components(separatedBy: ", ").last ?? ""
        let centre = try XCTUnwrap(formatter.date(from: spokenTime), "unreadable strip: \(values[1])", file: file, line: line)
        // Half-point offset rounding plus minute-only clocks can differ by up to 160s.
        XCTAssertEqual(centre.timeIntervalSince(readout), 0, accuracy: 160,
                       "curve reads \(values[1]) while the readout says \(values[0])", file: file, line: line)
        return values[0]
    }

    /// A fast run is one commentary stop at its fastest point, and the rate
    /// is the lead's. Walking the pill from now reaches a `Fastest rise` or
    /// `Fastest fall` within a turn and a sun event; tapping it parks on the
    /// peak, where the lead names the rate and the pill moves on to the next
    /// event instead of naming the peak again.
    ///
    /// Eastport, not Boston: a run is a stop only once it clears the ramp's
    /// first anchor (0.6 m/hr). Boston's weaker limb dips under the anchor at
    /// neaps; Eastport's worst-case limb (M2 − S2 − N2) stays well over it,
    /// any day of the lunar month.
    func testFastTidePeakIsOneStopAndTheLeadNamesTheRate() throws {
        let app = launch("-networkKillSwitch")
        openSearch(app, "eastport")
        pickSearchResult(app, app.staticTexts["Eastport"].firstMatch)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 10))
        settleLayout(strip)
        let pill = commentaryPill(app)
        let namesThePeak = #"^Fastest (rising|falling) tide in "#
        let namesTheRate = #"^(Rising|Falling), \d+(\.\d+)? (feet|metres) per hour, "#
        // Turn, sunrise, sunset, then the peak at the latest: four stops.
        var steps = 0
        while true {
            XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                      "no commentary pill on the Eastport detail")
            if pill.label.range(of: namesThePeak, options: .regularExpression) != nil { break }
            steps += 1
            guard steps <= 4 else { return XCTFail("the pill never named a fast run's peak: '\(pill.label)'") }
            pill.tap()
            settleScrub(app)
        }
        pill.tap()
        settleScrub(app)
        XCTAssert(leadReading(app).label.range(of: namesTheRate, options: .regularExpression) != nil,
                  "on the peak the lead names the rate: '\(leadReading(app).label)'")
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "no commentary pill on the peak")
        XCTAssertNil(pill.label.range(of: namesThePeak, options: .regularExpression),
                     "on the peak the pill names the next event, not the peak: '\(pill.label)'")
        save(app, "fast-tide-commentary.png")
    }

    /// The commentary pill names the stop ahead and walks to it: tapping it
    /// scrubs the strip there, so the lead's time moves and the pill returns
    /// naming the stop after that one.
    func testCommentaryTapScrubsToTheStopItNames() throws {
        let app = launch()
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 10))
        settleLayout(strip)  // the intro is still sliding the strip to now

        // The pill fades in once the scrub rests, so hittability is the wait,
        // not existence.
        let pill = commentaryPill(app)
        XCTAssert(waitFor(pill, "isHittable == true"),
                  "no commentary pill parked on now: '\(pill.label)'")
        let saidBefore = pill.label
        let clockBefore = scrubClock(app)

        pill.tap()
        settleScrub(app)
        XCTAssertNotEqual(scrubClock(app), clockBefore,
                          "tapping the commentary did not scrub to the stop it names")
        XCTAssert(waitFor(pill, "isHittable == true AND label != '\(saidBefore)'"),
                  "the commentary did not come back after the jump: '\(pill.label)'")
        XCTAssertNotEqual(pill.label, saidBefore,
                          "the commentary must name the next stop, not the one just landed on")
        save(app, "commentary-tapped.png")

        returnToNow(app)
        XCTAssert(waitFor(pill, "isHittable == true AND label == '\(saidBefore)'"),
                  "the commentary did not come back after returning to now: '\(pill.label)'")
    }

    /// Return-to-now from HISTORY: the Now pill rides the strip's chrome row
    /// on the side now is, so scrubbing back puts it on the right, arrow
    /// pointing that way — and it must still bring the strip home.
    func testReturnToNowFromHistory() throws {
        let app = launch()
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let now = app.buttons["detail-return-now"].firstMatch
        XCTAssert(now.appears(within: 5), "no return-to-now after scrubbing back")
        save(app, "history-before-now.png")
        // One read, one layout (settled — see `settled`'s doc in ScreenshotTestCase): the
        // strip is the ruler, since the pill lives inside its chrome row.
        let places = settled { [now.frame, strip.frame] }
        XCTAssert(places[0].midX > places[1].midX,
                  "scrubbed into history, the Now pill belongs on the right: "
                  + "\(places[0].midX) vs strip mid \(places[1].midX)")
        returnToNow(app)
        save(app, "history-after-now.png")
    }

    /// Scrubbed into the FUTURE, now is behind you: the Now pill takes the
    /// left edge of the strip's chrome row with its arrow pointing back there,
    /// and appearing costs the header chrome nothing — the pill lives on the
    /// strip, not in the header's top row, so the star and the back button
    /// never move when it comes and goes.
    func testNowPillSitsLeftWhenScrubbedForward() throws {
        let app = launch()
        openFridayHarbor(app)
        XCTAssert(app.otherElements["timeline-strip"].appears(within: 5))

        let star = app.buttons["detail-favorite"].firstMatch
        let back = app.buttons["detail-back"].firstMatch
        XCTAssert(star.appears(within: 5))
        let starBefore = star.frame, backBefore = back.frame
        let now = app.buttons["detail-return-now"]
        XCTAssert(now.disappears(within: 3),
                  "the opening slide did not settle on now")

        scrubStrip(app)
        XCTAssert(now.appears(within: 5), "scrubbing did not reveal return-to-now")
        save(app, "now-pill-scrubbed.png")
        // Re-reading star/now/header/back live below would be racy (settled —
        // see `settled`'s doc in ScreenshotTestCase). One read, one layout, four snapshots.
        let header = app.otherElements["detail-header"].firstMatch
        let after = settled { [star.frame, now.frame, header.frame, back.frame] }
        let starAfter = after[0], nowFrame = after[1], headerFrame = after[2]
        XCTAssertEqual(starAfter.minX, starBefore.minX, accuracy: 0.5,
                       "return-to-now still shifts the star")
        XCTAssertEqual(starAfter.minY, starBefore.minY, accuracy: 0.5)
        XCTAssertEqual(after[3].minX, backBefore.minX, accuracy: 0.5,
                       "return-to-now must not move the back button either")

        // On the strip's chrome row, which sits below the name header — not in
        // the header's own top row with the star.
        XCTAssert(nowFrame.minY > starAfter.maxY, "return-to-now is not below the star")
        XCTAssert(nowFrame.minY >= headerFrame.maxY - 1,
                 "return-to-now must live below the header, on the strip")
        // Leading side of the DETAIL PANE, not of the window: on a portrait
        // iPad the sidebar pushes the pane past the window's midX, so the
        // window ruler only passed here because the test before this one
        // leaves the device in landscape. `detail-header` is no ruler
        // either — its accessibility frame spans the whole window, not the
        // pane. The pane's own chrome is: back on its leading edge, star on
        // its trailing one.
        let paneMidX = (after[3].minX + starAfter.maxX) / 2
        XCTAssert(nowFrame.midX < paneMidX,
                  "scrubbed into the future, the Now pill belongs on the left: "
                  + "\(nowFrame.midX) vs pane mid \(paneMidX)")

        // And it still does its job — back to now, and gone again.
        returnToNow(app)
        XCTAssertEqual(settled { star.frame }.minX, starBefore.minX, accuracy: 0.5,
                       "the star moved when return-to-now went away")
    }

    /// #187: the share button rides the header's chrome row inboard of the
    /// star, which keeps the trailing corner it has always had. Presence and
    /// placement only — tapping raises the system share sheet, which is
    /// another process.
    func testShareSitsInboardOfTheStar() throws {
        let app = launch()
        openFridayHarbor(app)
        let share = app.buttons["detail-share"].firstMatch
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(share.appears(within: 5), "no share button on the tide detail")
        XCTAssert(share.isHittable, "share is not hittable: \(share.frame)")
        let places = settled { [share.frame, star.frame] }
        XCTAssertEqual(places[0].midY, places[1].midY, accuracy: 0.5,
                       "share is not on the star's row")
        XCTAssert(places[0].maxX <= places[1].minX,
                  "share must sit inboard of the star: \(places[0].maxX) vs \(places[1].minX)")
    }

    /// #222: the Moon tile is the way into the moon's own facts, and the
    /// eclipse rows are destinations — tapping one moves the window to it.
    func testMoonOrientationAcrossTheDetailAndSheet() throws {
        let app = XCUIApplication()
        var arguments = testArguments(["-locDenied"])
        let now = try XCTUnwrap(arguments.firstIndex(of: "-nowEpoch"))
        let at = ISO8601DateFormatter().date(from: "2026-10-19T01:17:00Z")!
        arguments[now + 1] = String(at.timeIntervalSince1970)
        app.launchArguments = arguments
        app.launch()
        openFridayHarbor(app)
        save(app, "moon-orientation-sky.png")
        let moon = app.buttons["tile-moon"].firstMatch
        scrollTo(moon, in: app)
        save(app, "moon-orientation-card.png")
        moon.tap()
        XCTAssertTrue(app.navigationBars["Moon"].appears(within: 5))
        XCTAssertTrue(app.descendants(matching: .any)["moon-rise"].firstMatch.appears(within: 5))
        save(app, "moon-orientation-sheet.png")
    }

    func testTheMoonTileOpensItsSheetAndTheEclipseRowJumps() throws {
        let app = launch()
        openFridayHarbor(app)
        let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
        XCTAssert(bar.appears(within: 10), "no range bar above the schedule")
        let week = bar.label
        // Case-insensitive, like the Range assertion elsewhere in this file:
        // the tile's eyebrow combines an uppercasing MonoLabel with an
        // accessibility label that does not.
        let moon = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] 'moon'")).firstMatch
        XCTAssert(moon.appears(within: 10), "no Moon tile on the tide detail")
        moon.tap()

        XCTAssert(app.navigationBars["Moon"].appears(within: 5),
                  "the Moon tile did not open its sheet")
        save(app, "moon-sheet.png")

        // One row per eclipse KIND, so the identifier carries the kind rather
        // than a position: which of the three comes first depends on the date
        // and the observer, and pinning the test to "the total one" would fail
        // in a year that has no visible total inside the window.
        let next = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'moon-next-eclipse-'")).firstMatch
        XCTAssert(next.appears(within: 10), "no next-eclipse row in the Moon sheet")
        // Every reachable time in this sheet is somewhere the scrubber can go,
        // and that now includes rise, set, and the two ends of the orbit.
        for id in ["moon-next-full", "moon-next-new", "moon-rise", "moon-set",
                   "moon-perigee", "moon-apogee"] {
            XCTAssert(app.descendants(matching: .any)[id].firstMatch.exists,
                      "\(id) is not in the sheet")
        }
        scrollTo(next, in: app)
        save(app, "moon-sheet-eclipses.png")

        next.tap()

        // The sheet closes, and the window has moved: the next eclipse is
        // months out, so the range bar has to be saying so. Both are WAITS —
        // a sheet dismissal is animated, and `exists` read on the line after
        // the tap catches it mid-flight (it did, first run).
        XCTAssert(app.navigationBars["Moon"].disappears(within: 10),
                  "the sheet stayed up after a jump")
        XCTAssert(waitFor(bar, "label != '\(week)'"),
                  "the jump did not move the window off '\(week)'")
        save(app, "moon-sheet-jumped.png")

        moon.tap()
        let tideLabel = app.staticTexts["moon-tide-label"].firstMatch
        XCTAssert(tideLabel.appears(within: 10), "no named tide condition in the Moon sheet")
        XCTAssertEqual(tideLabel.label, "Apogean spring tide")
        let tideBlurb = app.staticTexts["moon-tide-blurb"].firstMatch
        XCTAssert(tideBlurb.appears(within: 10), "no tide explanation in the Moon sheet")
        XCTAssert(tideBlurb.label.contains("farther") && tideBlurb.label.contains("perigean spring tide"),
                  "the apogean spring explanation did not describe the competing effects: \(tideBlurb.label)")
        save(app, "moon-sheet-apogean-spring.png")
    }

    /// A shared moment three weeks out (#187) lands on its own clock and day.
    /// `-scrubInstant` rides the shared link's path into the detail, so this
    /// is the link's hand-off whichever of the scaffold's and the detail's
    /// appears runs first: a first build around now would clamp the strip
    /// short of the moment. The tide and harmonic-current details build their
    /// stores separately, so both are opened.
    func testAMomentWeeksAwayLandsOnItsClockAndDay() throws {
        for (query, name) in [("friday", "Friday Harbor"), ("deception", "Deception Pass (Narrows)")] {
            let app = launch("-scrubInstant", "2026-09-28T13:00:00-07:00")
            openSearch(app, query)
            pickSearchResult(app, app.staticTexts[name].firstMatch)
            XCTAssert(leadReading(app).appears(within: 10), "no lead reading on \(name)")
            let clock = localizedClock("13:00")
            XCTAssert(waitFor(leadReading(app), "value CONTAINS '\(clock)'"),
                      "\(name) did not land on the moment: \(leadReading(app).label)")
            _ = settled { scrubClock(app) }
            XCTAssertEqual(scrubClock(app), clock,
                           "\(name)'s strip moved off the moment once it settled")
            let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
            XCTAssert(bar.appears(within: 10), "no range bar on \(name)")
            XCTAssert(bar.label.contains("Sep 28"), "\(name)'s window did not move to the moment's day: \(bar.label)")
            app.terminate()
        }
    }

    /// The report menu sits below the fold in the provenance footer, where no
    /// unit test can reach it. Tapping an item hands off to Mail, so this stops
    /// at the open menu: what it guards is that the three subjects a support
    /// mail can carry are all still offered.
    func testReportAProblemOffersItsThreeSubjects() throws {
        let app = launch("-fixLat", "48.4235", "-fixLon", "-123.3705")
        openFridayHarbor(app)
        let report = app.descendants(matching: .any)["detail-report"].firstMatch
        scrollTo(report, in: app)
        XCTAssertEqual(report.label, "Concerns or Feedback")
        save(app, "report-footer.png")
        report.tap()
        for subject in ["Station is in the wrong place",
                        "Station name or details are wrong",
                        "Predictions look wrong"] {
            XCTAssert(app.descendants(matching: .any)[subject].firstMatch.appears(within: 5),
                      "the report menu is missing: \(subject)")
        }
        save(app, "report-menu.png")
    }
}
