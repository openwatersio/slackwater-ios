// Slackwater — GPL v3. Getting around: the first-run gate, the search FAB,
// the pin map, the split layout, and the ways in and out of a detail.
//
// One of the weight-balanced screenshot classes — see ScreenshotTestCase.swift
// for the helpers and for why the suite is split this way.
import UIKit
import XCTest

final class MapSearchAndNavigationTests: ScreenshotTestCase {
    // Current stations sit in the list beside the tide ports; walk into
    // Deception Pass and scrub the signed velocity curve.
    func testM2Currents() throws {
        let app = launch("-seedGate")
        // wait (briefly) for a reading — screenshot only; an undownloaded list shows none
        _ = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^-?\\d+\\.\\d+ (ft|m|kn)$"))
            .firstMatch.appears(within: 5)
        save(app, "m2-list-mixed.png")

        // Search finds the current station; its detail is the signed curve.
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        assertCurrentDetailRendered(app)

        // Scrub: pan the combined tide+current strip, release.
        scrubStrip(app)
        settleScrub(app)
        save(app, "m2-current-scrubbed.png")
    }

    // First-run gate — the search bypass lands in the search experience, and
    // the choice sticks across relaunch without reopening search.
    // (The Use-My-Location path needs the system permission dialog; exercised
    // manually via simctl privacy.)
    func testM4Gate() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-resetGate"])
        app.launch()

        XCTAssert(app.staticTexts["Slackwater"].appears(within: 10))
        XCTAssertFalse(app.staticTexts["Find the water near you"].exists)
        XCTAssert(app.staticTexts["Real example station"].exists)
        XCTAssert(app.staticTexts["Friday Harbor"].exists)
        XCTAssert(app.descendants(matching: .any)["25-hour curve"].firstMatch.appears(within: 5))
        XCTAssert(app.staticTexts["Tide and Current predictions nearby."].exists)
        XCTAssert(app.staticTexts["Keeps working offline."].exists)
        XCTAssert(app.staticTexts["Your location stays on this device."].exists)
        XCTAssert(app.buttons["Find tides near me"].exists)
        save(app, "m4-gate.png")
        app.buttons["Search for a place"].tap()
        let field = app.textFields.firstMatch
        XCTAssert(field.appears(within: 5), "gate bypass did not open search")
        XCTAssert(waitFor(field, "hasKeyboardFocus == true"),
                  "the gate's search field did not take keyboard focus")
        field.typeText("friday")  // works only if the field auto-focused
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.appears(within: 5))
        closeSearch(app)

        app.terminate()
        app.launchArguments = testArguments([])
        app.launch()
        XCTAssert(stationList(app).appears(within: 10))
        XCTAssertFalse(app.textFields.firstMatch.exists,
                       "search must not reopen on relaunch — the handoff is one-shot")
    }

    // Pin map — opens from the floating button, land + pins render, and a
    // pin tap opens the station's detail. Two cases, one per pin layer: the
    // dots are split into station-pins-current (circle, Deception Pass) and
    // station-pins-tide (square, Kanaka Bay), and the web port silently dropped
    // tap handling for one kind when it split the same way — so both
    // layers must prove they reach the same tap handler. The pin's screen
    // point is pure web-mercator math from the fixed camera
    // (center 48.35,-123.05 · zoom 7.35 · 512pt world tiles); the launch hook
    // fixes the camera for this test.
    func testM4MapPinToDetail() throws {
        for (lat, lon, name) in [
            (48.40618896484375, -122.64311981201172, "Deception Pass (Narrows)"),  // current → circle
            (48.48500061035156, -123.08300018310547, "Kanaka Bay"),                // NOAA tide → square
        ] {
            // Pin coordinates below use this fixed Salish camera.
            let app = launch("-seedGate", "-resetRecents", "-locDenied",
                             "-mapCenter", "48.35,-123.05")
            app.buttons["Map"].tap()
            let map = app.otherElements["map-canvas"].firstMatch
            XCTAssert(map.appears(within: 5))
            // No header, no X — the toggle FAB (the list icon) is
            // the way back, and the left FAB flips to My Location over the map.
            XCTAssertFalse(app.staticTexts["MAP"].exists, "map must carry no header chrome")
            XCTAssert(app.buttons["List"].exists, "toggle FAB did not flip to the list icon")
            XCTAssert(app.buttons["My Location"].exists, "locate FAB missing over the map")
            sleep(5)  // tiles + the camera settling before tapPin trusts the fixed camera
            // One map shot, not one per pin — the second lap would overwrite it.
            if name == "Deception Pass (Narrows)" { save(app, "m41-map-zoom.png") }
            tapPin(map, lat, lon)
            // The pin tap raises the preview card; the card opens the detail.
            tapThroughPreview(app)
            XCTAssert(app.staticTexts["Today"].appears(within: 5),
                      "the preview card tap did not open a station detail")
            XCTAssert(app.staticTexts[name].firstMatch.appears(within: 5))
            app.terminate()
        }
    }

    /// Issue #401: an unavailable station's ring explains itself instead of
    /// leaving the map blank. Gijon, because it is the issue's own example and
    /// because nothing Slackwater may ship is within 154 km of it — so at this
    /// camera the ring is the only pin on screen and the centre tap can only
    /// have hit it.
    ///
    /// Zoom 11, not `locateZoom`: the ring's layer is gated at
    /// `NAME_MIN_ZOOM`, and a test sitting exactly on a minimum-zoom boundary
    /// is a test that fails the day someone nudges the constant.
    func testM4UnavailableStationExplainsItself() throws {
        // Inline, not `launch(...)`: that helper waits for the station list,
        // and `-openMap` opens the map instead.
        let app = XCUIApplication()
        app.launchArguments = testArguments(["-seedGate", "-openMap", "-locDenied",
                                             "-mapCenter", "43.558,-5.698", "-mapZoom", "11"])
        app.launch()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.appears(within: 15))
        sleep(5)  // tiles + the camera settling, as testM4MapPinToDetail does
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let card = app.descendants(matching: .any)["unavailable-station-card"].firstMatch
        XCTAssert(card.appears(within: 5), "the ring tap raised no explanation")
        XCTAssert(app.staticTexts["Gijon"].firstMatch.exists, "the card does not name the station")
        // The card says two things and no more — the licence argument lives on
        // the detail page, not on the map.
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "not yet available")).firstMatch.exists,
            "the card does not say the station is unavailable")
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "cc-by-nc")).firstMatch.exists,
            "licence jargon must not reach the map card")
        // And it is NOT a station card: there is nothing to scrub.
        XCTAssertFalse(app.descendants(matching: .any)["map-preview-card"].firstMatch.exists,
                       "an unavailable station must not raise a station preview")
        save(app, "m4-unavailable-station.png")

        // The card's one link opens the page that explains it.
        app.staticTexts["We need your help"].firstMatch.tap()
        let detail = app.descendants(matching: .any)["unavailable-detail"].firstMatch
        XCTAssert(detail.appears(within: 5), "the card's link opened no detail page")
        XCTAssert(app.descendants(matching: .any)["unavailable-support-ask"]
                    .firstMatch.exists, "the detail page makes no ask")
        // The ask has to be actionable: one inline contact link, not prose
        // inviting the reader to find an address themselves.
        XCTAssert(app.descendants(matching: .any)["unavailable-contact"]
                    .firstMatch.exists, "the ask offers no way to get in touch")
        // The Nearby section is the way out. Rows carry a combined label
        // ("Santander, Cantabria · Tide · NOAA, 83 nm"), so match a prefix the
        // way testNearbyFiltersOpensAStationAndOpensTheMap does — Santander is
        // the nearest station Slackwater may ship to Gijon, 154 km east.
        let nearby = app.descendants(matching: .any)["nearby"].firstMatch
        XCTAssert(nearby.appears(within: 10), "no Nearby section on the detail page")
        let rows = nearby.descendants(matching: .any).matching(identifier: "nearby-station")
        XCTAssert(rows.firstMatch.appears(within: 10), "Nearby lists no stations")
        let labels = rows.allElementsBoundByIndex.map(\.label)
        XCTAssert(labels.contains { $0.hasPrefix("Santander") },
                  "Nearby does not offer the nearest shippable station, got "
                  + labels.joined(separator: " | "))
        // Starring an unavailable station would persist an id nothing resolves.
        XCTAssertFalse(app.buttons["Add favorite"].firstMatch.exists,
                       "an unavailable station must not be favoritable")
        // One back button. DetailHeader brings its own, so a detail that
        // forgets `.toolbar(.hidden, for: .navigationBar)` renders the
        // system's above it — two chevrons, which no other assertion here can
        // see.
        XCTAssertEqual(app.navigationBars.count, 0,
                       "the detail page did not hide the system navigation bar")
        XCTAssertEqual(app.buttons.matching(identifier: "detail-back").count, 1,
                       "the detail page shows more than one back button")
        save(app, "m4-unavailable-detail.png")
    }

    // A gate detail shows no tide — the port's numbers live on the port's own
    // detail, one tap through the quiet link.
    func testM4TideAtPortLink() throws {
        let app = launch("-seedGate")

        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))

        // Nothing tide-shaped on the gate detail.
        XCTAssertFalse(app.staticTexts["TIDE AT DECEPTION PASS STATE PARK"].exists,
                       "the paired tide readout is retired")
        // Two calls, not one `&&`: an `&&` only fails when BOTH row kinds
        // leak, so a single stray HIGH (or LOW) row would pass silently.
        XCTAssertFalse(app.staticTexts["⤒ HIGH"].firstMatch.exists,
                       "port tide rows must not appear in a gate schedule")
        XCTAssertFalse(app.staticTexts["⤓ LOW"].firstMatch.exists,
                       "port tide rows must not appear in a gate schedule")
        // What the gate does say is the commentary pill: the stop ahead,
        // named and walked to — a slack, a run, or the sun when it is nearer.
        let pill = commentaryPill(app)
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "no commentary pill on the gate detail")
        XCTAssert(namesACurrentStop(pill.label),
                  "the commentary must name a stop, got '\(pill.label)'")
        let strip = app.otherElements["timeline-strip"].firstMatch
        _ = strip.appears(within: 10)
        settleLayout(strip)  // the chart is most of this picture
        save(app, "m4-gate-detail.png")

        // The link opens the port's own detail with its schedule. Tide rows
        // are the primary tell, checked FIRST: a gate schedule can never show
        // HIGH/LOW, so their presence is unambiguous proof navigation actually
        // happened. The port's name
        // is checked second and only as a station-identity confirmation — on
        // iPad the sidebar's always-visible Recents section can carry the
        // exact same station name whether or not the tap navigated (bit us:
        // an exact-text existence check on the name alone false-positived
        // there against a stale Recents row while the pane was still showing
        // the gate).
        let link = app.descendants(matching: .any).matching(identifier: "tide-at-port").firstMatch
        XCTAssert(link.appears(within: 5), "tide-at-port link missing")
        link.tap()
        XCTAssert(app.staticTexts["⤒ HIGH"].firstMatch.appears(within: 8)
                  || app.staticTexts["⤓ LOW"].firstMatch.appears(within: 8),
                  "port detail shows its own tide schedule")
        XCTAssert(app.staticTexts["Deception Pass State Park"].firstMatch.exists,
                  "the link did not open the reference port's detail")
    }

    // iPad split layout — regular width gets the web's ≥62rem shape
    // (styles.css): persistent sidebar (search + groups) beside the detail
    // pane, in both orientations. Skipped on iPhone, which keeps the stack.
    func testM44IPadSplit() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only layout test")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch("-seedGate")
        // The pane opens on the first row, not the placeholder — the
        // placeholder is only reachable by clearing the pane (map toggle).
        XCTAssert(app.otherElements["detail-header"].appears(within: 10),
                  "regular width did not auto-select a station into the detail pane")
        openFridayHarbor(app)
        // The sidebar must still be on screen while the detail shows —
        // a split, not a push.
        XCTAssert(stationList(app).exists, "sidebar gone — not a split layout")
        XCTAssert(app.otherElements["timeline-strip"].appears(within: 5))
        // A second pick replaces the detail (no stacking) — web sidebar behavior.
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        // the current detail's own anatomy is the tell that the pane swapped
        assertCurrentDetailRendered(app)
        sleep(5)  // header map tiles: MLNMapView surfaces no load state to XCUITest
        save(app, "m44-ipad-landscape.png")

        // Regular width: the FABs live in the sidebar column; the map
        // FAB swaps the detail pane to the map (replacing the shown detail),
        // flips to the list icon, and toggling back lands on the placeholder.
        app.buttons["Map"].firstMatch.tap()
        XCTAssert(app.otherElements["map-canvas"].appears(within: 5),
                  "map did not take over the detail pane")
        XCTAssert(app.buttons["List"].exists, "toggle FAB did not flip to the list icon")
        XCTAssert(app.buttons["My Location"].exists, "locate FAB missing while the map shows")
        app.buttons["List"].firstMatch.tap()
        XCTAssert(app.staticTexts["Pick a station"].appears(within: 5),
                  "toggle back did not land on the placeholder")

        XCUIDevice.shared.orientation = .portrait
        settleLayout(app.windows.firstMatch)  // the rotation, by the window it resizes
        XCTAssert(stationList(app).exists, "portrait dropped the sidebar")
        save(app, "m44-ipad-portrait.png")
    }

    // The floating toolbar — search FAB bottom-left opens the bottom-input
    // search with the keyboard up; the X beside the input exits in one tap;
    // the map FAB toggles the surface in place and flips to the list icon (no
    // header, no close chrome); over the map the left FAB becomes My Location.
    func testM45SearchFabAndMapToggle() throws {
        let app = launch("-seedGate")

        // No top search bar on the list; both FABs present.
        XCTAssertFalse(app.textFields.firstMatch.exists, "top search bar must be gone")
        XCTAssert(app.buttons["Search"].exists)
        XCTAssert(app.buttons["Map"].exists)

        // Search FAB → bottom input, keyboard up (openSearch types with no
        // field tap), results fill the space above.
        openSearch(app, "friday")
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.appears(within: 5))
        XCTAssert(app.buttons["Close search"].exists, "X missing beside the input")

        // X beside the input: one tap back to the list, keyboard gone.
        closeSearch(app)
        XCTAssertFalse(app.textFields.firstMatch.exists, "X did not close search")

        // Map FAB: the surface swaps in place, the button becomes the list
        // icon, and no chrome sits over the map.
        app.buttons["Map"].tap()
        XCTAssert(app.otherElements["map-canvas"].appears(within: 5))
        XCTAssertFalse(app.staticTexts["MAP"].exists, "map must carry no header")
        XCTAssert(app.buttons["List"].exists, "toggle did not flip to the list icon")

        // #43: the "not for navigation" pill belongs ON the FAB row, not
        // floating above it mid-chart. Asserted as geometry rather than by
        // eye — placing it at a fixed constant (96pt from the screen edge, past
        // the safe area) looks right in one simulator and wrong on the
        // next, which is exactly what a frame comparison catches.
        let disclaimer = app.staticTexts["map-disclaimer"].firstMatch
        XCTAssert(disclaimer.appears(within: 5), "map disclaimer missing")
        let toggle = app.buttons["List"].firstMatch
        XCTAssertGreaterThan(disclaimer.frame.minY, toggle.frame.minY,
                             "the pill floats above the FABs instead of sitting on their row")
        XCTAssertLessThanOrEqual(disclaimer.frame.maxY, toggle.frame.maxY + 1,
                                 "the pill hangs below the FAB row, into the home indicator")

        // Over the map the left FAB is My Location, not Search.
        XCTAssert(app.buttons["My Location"].exists, "locate FAB missing over the map")
        XCTAssertFalse(app.buttons["Search"].exists, "search FAB must not sit over the map")

        // Toggle back: list returns, the button is the map icon again.
        XCTAssert(app.buttons["List"].appears(within: 5))
        app.buttons["List"].tap()
        XCTAssert(stationList(app).appears(within: 5))
        XCTAssert(app.buttons["Map"].exists, "toggle did not flip back to the map icon")
    }

    /// Issue #32: the detail header title jumps to the map, focused on the
    /// detail's own station (StationListView.swift `openMapFocused`/`mapFocus`,
    /// DetailHeader.swift's title). No accessibility surface exposes an
    /// `MLNMapView`'s live center/zoom to XCUITest — nothing in this file
    /// reads one — so this proves the navigation contract (map up, detail
    /// gone) rather than the actual camera position; `mapFocus`/`stationZoom`
    /// wiring the correct center/zoom into `MapViewRepresentable` is covered
    /// by reading the source, same as the rest of MapStyler's camera
    /// assertion, which nothing here exercises either.
    ///
    /// Two entry paths, one launch. They assert the identical contract and
    /// differ only in how the detail is reached, which is worth a second leg
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

        // Leg 2 — detail reached from a MAP PIN. That path leaves `showMap`
        // already `true` on iPhone, so the map pane doesn't naturally remount
        // for the title tap that follows.
        // `.id(mapFocusToken)` on `MapViewRepresentable` forces the remount and
        // `makeUIView` applies the focus (MapScreen.swift). iPhone-only: on iPad
        // the preview card's tap resets `showMap` before opening, so the
        // scenario cannot arise there — an inline guard rather than a
        // whole-test skip, so leg 1 still runs on both.
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.appears(within: 5))
        sleep(5)  // tiles + camera for the tap below; neither reaches XCUITest
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tapThroughPreview(app)
        XCTAssert(app.staticTexts["Today"].appears(within: 5),
                  "the pin tap did not open a detail")
        assertTitleTapFocusesMap(app)
    }

    // The map needs no map-specific path — a pin tap goes through the
    // same open() as a row, so an unfitted station lands on the same warning
    // detail. Held unfitted by the kill switch, so this is deterministic.
    func testM48MapPinToUnfittedDetail() throws {
        // The camera is put ON Race Passage rather than aimed at it from the
        // wide Salish view: at national scale a finger-sized box over that pin
        // holds several dots, so "the nearest dot to the tap" is not reliably
        // the one this test means. The fix is the fix — the discovery map opens
        // on it — plus a station-scale zoom.
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch",
                         "-fixLat", "48.3067", "-fixLon", "-123.5367", "-mapZoom", "11")
        app.buttons["Map"].tap()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.appears(within: 5))
        sleep(5)  // tiles + camera for the tap below; neither reaches XCUITest

        // Dead centre: the camera is on the station, so the pin is the middle.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tapThroughPreview(app)
        XCTAssert(app.staticTexts["Waiting for signal"].appears(within: 8),
                  "an offline station must headline what it is waiting for")
        XCTAssert(app.staticTexts["Race Passage"].firstMatch.exists)

        // Offline: the established honest register, and no bogus ETA.
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'need a moment of signal'")).firstMatch.exists,
                  "offline warning must keep the moment-of-signal copy")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Nothing downloads without a connection'"))
            .firstMatch.exists)
    }

    /// The nav bar is hidden app-wide for the map-hero chrome, and UIKit
    /// disables `interactivePopGestureRecognizer` whenever it is — leaving the
    /// button as the only way back on iPhone unless the gesture is re-armed by
    /// hand. Both halves are asserted, because
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
        XCTAssert(app.otherElements["timeline-strip"].appears(within: 5))
        let before = scrubClock(app)
        scrubStrip(app)
        settleScrub(app)  // read the parked time, not one mid-deceleration
        XCTAssert(app.otherElements["timeline-strip"].exists,
                  "a drag inside the strip popped the detail — the edge gesture is too greedy")
        XCTAssertNotEqual(scrubClock(app), before,
                          "a drag inside the strip no longer scrubs")

        edgeSwipeBack(app)
        XCTAssert(stationList(app).appears(within: 5),
                  "edge swipe did not pop the tide detail")

        // (b) current detail.
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        assertCurrentDetailRendered(app)
        edgeSwipeBack(app)
        XCTAssert(stationList(app).appears(within: 5),
                  "edge swipe did not pop the current detail")

        // (c) the CHS waiting page — no chart at all, held there by the kill switch.
        openSearch(app, "victoria")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(app.staticTexts["Waiting for signal"].appears(within: 10))
        edgeSwipeBack(app)
        XCTAssert(stationList(app).appears(within: 5),
                  "edge swipe did not pop the CHS waiting page")

        // (d) a derived gate — Malibu Rapids, likewise pending offline.
        openSearch(app, "malibu")
        pickSearchResult(app, app.staticTexts["Malibu Rapids"].firstMatch)
        XCTAssert(app.staticTexts["Waiting for signal"].appears(within: 10))
        edgeSwipeBack(app)
        XCTAssert(stationList(app).appears(within: 5),
                  "edge swipe did not pop the derived-gate detail")

        // Reaching the list after every detail verifies the shared edge-pop
        // coordinator. UIKit itself declines interactive-pop at root.
    }

    /// iPad: a fresh launch opens the first row in the detail pane instead
    /// of the "Pick a station" invitation. Only when nothing is selected — a
    /// pick already made is never overridden.
    func testM52IPadAutoSelectsTheFirstStation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("regular-width behaviour")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")
        XCTAssert(app.otherElements["detail-header"].appears(within: 10),
                  "the detail pane did not open a station on launch")
        XCTAssertFalse(app.staticTexts["Pick a station"].exists,
                       "the placeholder is still what a fresh iPad launch shows")
        // The sidebar is intact — this is a selection, not a push.
        XCTAssert(stationList(app).exists)

        // Don't fight the user: a deliberate pick stands, and coming back to
        // the list does not re-run the auto-select.
        openSearch(app, "friday")
        pickSearchResult(app, app.staticTexts["Friday Harbor"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 10))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists,
                  "the auto-selection overrode a deliberate pick")
    }

    /// Search at 3,125 stations: bounded, nearest-first, and honest about what
    /// it is not showing.
    func testM53SearchAtNationalScale() throws {
        // `-resetRecents` is load-bearing, not hygiene: the ranking anchor is
        // Fix -> recents -> fallback; use a Victoria fix for this ranking check.
        // The full plan runs testM53OnDemandCanadianStationFitsWhenOpened (Halifax)
        // immediately before this, which leaves the anchor 4,500 km east with no
        // BC or WA port inside the truncated set. The fast plan skips that test,
        // so only the full run would go red.
        let app = launch("-seedGate", "-networkKillSwitch", "-resetRecents",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        // "port" matches several hundred stations nationally.
        openSearch(app, "port")
        XCTAssert(app.descendants(matching: .any)["search-truncated"].firstMatch
                    .appears(within: 5),
                  "a query matching hundreds of stations must say it truncated")
        // Nearest-first: from the Victoria fix the top of the list is
        // local water, not an alphabetical trip to Alaska.
        XCTAssert(app.staticTexts["Portage Inlet"].firstMatch.exists ||
                  app.staticTexts["Port Townsend"].firstMatch.exists,
                  "results are not ranked by distance from the fix")

        // Narrowing removes the truncation notice — the list is complete again.
        app.textFields.firstMatch.typeText(" townsend")
        _ = app.descendants(matching: .any)["search-truncated"].firstMatch
            .disappears(within: 10)
        XCTAssertFalse(app.descendants(matching: .any)["search-truncated"].firstMatch.exists,
                       "a narrow query must not claim to be truncated")
        closeSearch(app)
    }

    /// iPad search results sit in columns, not one card stretched across the
    /// whole screen: some pair of result texts shares a row. Names, not
    /// positions — "port" matches dozens, whichever ranks first.
    func testSearchResultsGridOnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only layout test")
        }
        for (orientation, shot) in [(UIDeviceOrientation.portrait, "search-grid-ipad-portrait.png"),
                                    (.landscapeLeft, "search-grid-ipad-landscape.png")] {
            XCUIDevice.shared.orientation = orientation
            let app = launch("-seedGate", "-resetRecents")
            openSearch(app, "port")
            XCTAssert(app.descendants(matching: .any)["search-truncated"].firstMatch.appears(within: 5))
            let frames = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Port'"))
                .allElementsBoundByIndex.prefix(12).map(\.frame)
            XCTAssert(frames.contains { a in
                frames.contains { b in abs(a.minY - b.minY) < 1 && b.minX - a.minX > 100 }
            }, "no two search results share a row in \(orientation.rawValue)")
            save(app, shot)
            app.terminate()
        }
    }

    /// The map at continental scale. Thousands of pins is a grey smear
    /// without the far band's collision thinning; this walks the camera out
    /// to the whole country, times the gestures — which now price the
    /// collision engine over the whole bundle — and checks the map is still
    /// a map afterwards.
    func testM53MapAtContinentalZoom() throws {
        let app = XCUIApplication()
        // z3.2 over the Salish camera longitude: the west coast from Mexico to
        // Alaska, offline, with everything the bundle knows on it. The camera
        // is stated rather than pinched into place — five synthesised pinches
        // land somewhere no assertion can name.
        app.launchArguments = testArguments(["-seedGate", "-openMap", "-mapZoom", "3.2",
                                             "-mapCenter", "48.35,-123.05"])
        app.launch()
        let map = app.otherElements["map-canvas"].firstMatch
        XCTAssert(map.appears(within: 15))
        sleep(6)  // tiles + symbol placement must settle before the TIMED pinches; neither reaches XCUITest
        save(app, "m53-map-continental.png")

        // Then the interaction cost, timed: zooming the collision-thinned
        // source at the scale where every station is a candidate symbol.
        let start = Date.now
        for _ in 0..<5 { map.pinch(withScale: 1.6, velocity: 2) }
        let gestures = Date.now.timeIntervalSince(start)
        // No pin count in the line. A UI test cannot see `StationItem.all`
        // (separate target, no `@testable`), so any count printed here is a
        // hardcoded literal that reads as a measurement and goes stale the next
        // time the bundle grows. A diagnostic that states a number it cannot
        // check is worse than one that states only what it timed.
        print(String(format: "map · 5 pinches at z3.2 over the whole world bundle: %.2f s", gestures))
        XCTAssertLessThan(gestures, 20, "zooming the world pin map should not take 20 seconds")

        // Still responsive and still a map afterwards.
        XCTAssert(app.buttons["List"].exists, "the map chrome stopped responding")
        XCTAssert(app.buttons["My Location"].exists)
        app.buttons["List"].tap()
        XCTAssert(stationList(app).appears(within: 5))
    }
}
