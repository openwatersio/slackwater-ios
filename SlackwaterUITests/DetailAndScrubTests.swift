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
        // The Victoria fix is pinned because the SEARCH step below depends on
        // it: results rank by distance from the live anchor, and the scroll
        // loop's budget only reaches Active Pass from a Salish Sea anchor. A
        // dev machine with a custom simulator location (or none) ranks from
        // somewhere else entirely.
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")

        // Units live in Settings only (no list pill): reset to feet first —
        // the setting persists across runs.
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
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        settleLayout(app.staticTexts["Slackwater"].firstMatch)  // the pop slides the list in
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
        // Leave the store imperial for the other tests.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        setUnits(app, "Feet")
    }

    /// #95: the tide detail says where the water is and how big this swing is
    /// — a height under the centerline and a Range tile beside the moon. How
    /// fast it is moving is the lead glyph's colour, which no query can read,
    /// so the readable half is what this pins. Friday Harbor reads small; the
    /// point is the figures exist at every station, so Ile Haute's 32 ft can't
    /// hide.
    func testTideReadoutShowsHeightAndRange() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-seedGate"])
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 10))

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

    /// #170: provenance stays out of the primary tide-reading flow until the
    /// sailor asks for it, then exposes the support/debugging facts in place.
    func testStationDetailsAreCollapsedUntilOpened() throws {
        let app = launch("-seedGate")
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

    /// The range bar heads the schedule card on every scrubable detail and says
    /// what span the list below it covers; tapping it opens the picker, and
    /// picking a date moves the window with the bar following.
    ///
    /// The bar-exists-and-states-a-span check is the first three lines here
    /// rather than a test of its own — a launch costs ~6 s and this test
    /// already waits for the same element to read `before`.
    func testPickingADateMovesTheWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-seedGate"])
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 10))

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

        XCTAssertNotEqual(bar.label, before, "the bar must follow the anchor")
        XCTAssert(app.staticTexts["not this week"].appears(within: 5))

        // The centerline has to move WITH the window. It does not follow on its
        // own — the strip's x/time conversions are exact inverses, so a
        // programmatic scroll to an off-window `scrubTime` reads straight back
        // as the same off-window time and the strip draws blank. The
        // observable proof is this button: parking the centerline on the picked
        // week puts `scrubTime` far from now, and return-to-now is what shows
        // when it is. Without it there is no way back to today at all — the
        // range bar's "not this week" is a label, not a control.
        XCTAssert(app.buttons["detail-return-now"].appears(within: 5),
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
        XCTAssert(app.staticTexts["Today"].appears(within: 5),
                  "return-to-now did not bring the window back to today")
        let homeInk = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(homeInk > 0.05, "the strip drew nothing back on today — ink \(homeInk)")
    }

    // The detail header carries the title, the day header carries the sun
    // times, and the summary tile names the moon phase.
    func testM41DetailHeaderSunMoon() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        XCTAssert(app.otherElements["detail-header"].appears(within: 5),
                  "header missing from tide detail")
        XCTAssert(app.descendants(matching: .any).matching(identifier: "day-sun-d0")
            .firstMatch.appears(within: 5),
                  "sun times missing from the schedule day header")
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
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.otherElements["detail-header"].appears(within: 5),
                  "header missing from current detail")
        save(app, "m41-current-detail-header.png")
        XCTAssert(app.descendants(matching: .any).matching(identifier: "day-sun-d0")
            .firstMatch.appears(within: 5),
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
        XCTAssert(app.otherElements["timeline-strip"].appears(within: 5),
                  "pan-under-centerline strip missing from tide detail")

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
        tomorrowDay.tap()
        XCTAssert(tomorrowRow.appears(within: 5), "Tomorrow's rows did not expand")
        XCTAssertFalse(app.buttons.matching(identifier: "schedule-row-d0").firstMatch.exists,
                       "opening Tomorrow should collapse Today")

        // Pan the strip: the centerline readout moves off "now".
        scrubStrip(app)
        XCTAssert(app.buttons["Return to now"].appears(within: 5),
                  "return-to-now affordance missing after scrubbing away")

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
        app.swipeDown()

        // Return to now restores the live reading and hides the control.
        app.buttons["Return to now"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Return to now"].firstMatch.appears(within: 2),
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
        XCTAssert(leadReading(app).appears(within: 5))
        let before = scrubClock(app)

        // The FIRST drag on a fresh detail: the readout must move during the
        // gesture itself (read mid-deceleration, pre-settle), not only after
        // the magnet settles.
        scrubStrip(app)
        XCTAssertNotEqual(before, scrubClock(app),
                          "first scrub left the readout frozen — initial centering raced layout again")
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
        let app = launch("-seedGate")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5), "timeline strip missing")
        // Away from now, so nothing but the rotation moves the strip.
        scrubStrip(app)
        settleScrub(app)
        XCTAssertLessThanOrEqual(clockGap(stripCentre(app), scrubClock(app)), 5,
                                 "before rotating, the curve and readout already disagree")

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            let before = scrubClock(app)
            device.orientation = orientation
            settleLayout(strip)
            let readout = scrubClock(app), centre = stripCentre(app)
            XCTAssertEqual(readout, before, "rotation changed the readout")
            XCTAssertLessThanOrEqual(clockGap(centre, readout), 5,
                                     "after rotating to \(orientation.rawValue) the curve under the "
                                     + "centerline reads \(centre) while the readout says \(readout)")
        }
    }

    /// The time under the strip's centerline ("1:42pm"), from the scroll
    /// view's accessibility value.
    private func stripCentre(_ app: XCUIApplication) -> String {
        app.otherElements["timeline-strip"].scrollViews.firstMatch.value as? String ?? ""
    }

    /// Minutes between two "h:mma" clocks, the short way round midnight.
    private func clockGap(_ a: String, _ b: String) -> Int {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mma"
        func minutes(_ s: String) -> Int {
            guard let d = f.date(from: s.uppercased()) else { return Int.min / 2 }
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            return c.hour! * 60 + c.minute!
        }
        let gap = abs(minutes(a) - minutes(b)) % 1440
        return min(gap, 1440 - gap)
    }

    /// Over a fast tide the pill explains the yellow line: the rate, in the
    /// ramp's colour, instead of the next turn. Landing on a turn first (the
    /// commentary tap) and then dragging about three hours on puts the scrub
    /// mid-run, where the magnet parks it on the run's fastest point — a snap
    /// stop — so the pill reads the peak rate.
    ///
    /// Eastport, not Boston: the magnet only has a fastest point to park on
    /// when the run clears the ramp's first anchor (0.6 m/hr — a slower run
    /// grows no flow arrow, and the drag snaps to a turn instead, where the
    /// pill names the stop). Boston's weaker limb dips under the anchor at
    /// neaps; Eastport's worst-case limb (M2 − S2 − N2) stays well over it,
    /// any day of the lunar month.
    func testFastTideCommentaryNamesTheRate() throws {
        let app = launch("-seedGate", "-networkKillSwitch")
        openSearch(app, "eastport")
        pickSearchResult(app, app.staticTexts["Eastport"].firstMatch)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 10))
        settleLayout(strip)
        let pill = commentaryPill(app)
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "no commentary pill on the Eastport detail")
        pill.tap()
        settleScrub(app)
        // The tap's destination depends on the water at "now": already fast,
        // it goes to the run's peak — the pill reads the rate and there is
        // nothing left to stage. Quiet, it parks on the next TURN, and
        // mid-run is a drag away. The hold releases the drag at rest: a
        // flicked release keeps UIScrollView momentum, which carries the
        // scrub about a half-cycle on, and the magnet then parks it on the
        // next turn — slack water — instead.
        //
        // That drag is measured in POINTS against the magnet, never as a
        // fraction of the strip (#289). The tap has just parked the
        // centerline exactly ON a stop, and the magnet pulls it back onto any
        // stop within `Timeline.magnetPts` — so a drag shorter than that
        // radius is a no-op that re-reads the very label it was staged to
        // change. The `dx: 0.4` this replaces was ~40 pt on a phone, inside
        // the 46 pt radius, and had been sized when `Timeline.pph` was still
        // 12: it silently shrank under the magnet when the NEAPS pass widened
        // the strip to 18, and only ever passed on the days the tap happened
        // to land somewhere already fast.
        //
        // Three hours clears the radius with room (54 pt at 18 pt/hr) and is
        // about a quarter-cycle from a turn, which is where a semidiurnal run
        // runs fastest — the run Eastport always grows (the doc comment
        // above). Both numbers are the app's own and a UI test cannot link
        // them, so they are spelled out here and asserted below rather than
        // trusted.
        let pointsPerHour: CGFloat = 18     // Timeline.pph
        let dragHours: CGFloat = 3
        let namesTheRate = #"^(Rising|Falling) \d+(\.\d+)? (ft|m)/hr$"#
        if pill.label.range(of: namesTheRate, options: .regularExpression) == nil {
            let parked = scrubClock(app)
            let dx = dragHours * pointsPerHour / strip.frame.width
            strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.3,
                       thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5 - dx, dy: 0.5)),
                       withVelocity: .default,
                       thenHoldForDuration: 0.5)
            settleScrub(app)
            XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                      "the commentary did not come back after the drag")
            // The failure #289 was actually about: a drag inside the magnet
            // snaps straight back, and the label mismatch below then reads as
            // "the commentary is wrong" rather than "the scrub never moved".
            XCTAssertNotEqual(scrubClock(app), parked,
                              "the drag did not clear the magnet — the scrub is still parked on \(parked)")
        }
        XCTAssert(pill.label.range(of: namesTheRate, options: .regularExpression) != nil,
                  "over a fast tide the commentary names the rate: '\(pill.label)'")
        save(app, "fast-tide-commentary.png")
    }

    /// The commentary pill names the stop ahead and walks to it: tapping it
    /// scrubs the strip there, so the lead's time moves and the pill returns
    /// naming the stop after that one. Its phrasing follows the scrub — "in"
    /// counts from the reader, "later" from wherever on the strip they are
    /// looking — so the trip out and the trip home read differently.
    func testCommentaryTapScrubsToTheStopItNames() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 10))
        settleLayout(strip)  // the intro is still sliding the strip to now

        // The pill fades in once the scrub rests, so hittability is the wait,
        // not existence.
        let pill = commentaryPill(app)
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "no commentary pill on the tide detail")
        let saidBefore = pill.label
        XCTAssert(saidBefore.contains(" in "),
                  "parked on now, the commentary counts from the reader: '\(saidBefore)'")
        let clockBefore = scrubClock(app)

        pill.tap()
        settleScrub(app)
        XCTAssertNotEqual(scrubClock(app), clockBefore,
                          "tapping the commentary did not scrub to the stop it names")
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "the commentary did not come back after the jump")
        XCTAssertNotEqual(pill.label, saidBefore,
                          "the commentary must name the next stop, not the one just landed on")
        XCTAssert(pill.label.hasSuffix("later"),
                  "scrubbed away, the commentary counts from the strip: '\(pill.label)'")
        save(app, "commentary-tapped.png")

        // Home again, and the count is the reader's once more.
        app.buttons["detail-return-now"].firstMatch.tap()
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "the commentary did not come back after returning to now")
        XCTAssert(pill.label.contains(" in "),
                  "back on now, the commentary counts from the reader: '\(pill.label)'")
    }

    /// Return-to-now from HISTORY: the Now pill rides the strip's chrome row
    /// on the side now is, so scrubbing back puts it on the right, arrow
    /// pointing that way — and it must still bring the strip home.
    func testReturnToNowFromHistory() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.appears(within: 5))
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let now = app.buttons["detail-return-now"].firstMatch
        XCTAssert(now.appears(within: 5), "no return-to-now after scrubbing back")
        save(app, "history-before-now.png")
        // One read, one layout (settled — see `settled`'s doc in ScreenshotTestCase): the
        // strip is the ruler, since the pill lives inside its chrome row.
        let places = settled { [now.frame, strip.frame] }
        XCTAssert(places[0].midX > places[1].midX,
                  "scrubbed into history, the Now pill belongs on the right: "
                  + "\(places[0].midX) vs strip mid \(places[1].midX)")
        XCTAssert(now.isHittable, "return-to-now is not hittable: \(now.frame)")
        now.tap()
        XCTAssert(now.disappears(within: 10), "return-to-now did not bring the strip home")
        save(app, "history-after-now.png")
    }

    /// Scrubbed into the FUTURE, now is behind you: the Now pill takes the
    /// left edge of the strip's chrome row with its arrow pointing back there,
    /// and appearing costs the header chrome nothing — the pill lives on the
    /// strip, not in the header's top row, so the star and the back button
    /// never move when it comes and goes.
    func testNowPillSitsLeftWhenScrubbedForward() throws {
        let app = launch("-seedGate")
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
        now.tap()
        _ = now.disappears(within: 10)
        XCTAssertFalse(app.buttons["detail-return-now"].exists,
                       "return-to-now did not clear after returning to now")
        XCTAssertEqual(settled { star.frame }.minX, starBefore.minX, accuracy: 0.5,
                       "the star moved when return-to-now went away")
    }

    /// #222: the Moon tile is the way into the moon's own facts, and the
    /// eclipse rows are destinations — tapping one moves the window to it.
    func testTheMoonTileOpensItsSheetAndTheEclipseRowJumps() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
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
        // The eclipse list runs off the bottom of a phone screen, so the half
        // of this sheet that carries the three kinds has no shot otherwise.
        app.swipeUp()
        save(app, "moon-sheet-eclipses.png")
        // Both swipes decelerate, and the tap below lands on a row that is
        // still moving otherwise — the scroll ends with no accessibility
        // signal, the same gap `settleLayout` exists for (#331).
        app.swipeDown()
        settleLayout(next)

        next.tap()

        // The sheet closes, and the window has moved: the next eclipse is
        // months out, so the range bar has to be saying so. Both are WAITS —
        // a sheet dismissal is animated, and `exists` read on the line after
        // the tap catches it mid-flight (it did, first run).
        XCTAssert(app.navigationBars["Moon"].disappears(within: 10),
                  "the sheet stayed up after a jump")
        XCTAssert(app.staticTexts["not this week"].appears(within: 10),
                  "the jump did not move the window")
        save(app, "moon-sheet-jumped.png")
    }
}
