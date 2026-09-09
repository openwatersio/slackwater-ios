// Slackwater — GPL v3. What the app shows with no network: the downloads
// manager and its queue, the pending and waiting pages, the online gates
// against seeded windows, and the bundled harmonics that need no download.
// Held deterministic by -networkKillSwitch and the seed hooks, so nothing
// here waits on a live fit — those are LiveFetchTests.
//
// One of the weight-balanced screenshot classes — see ScreenshotTestCase.swift
// for the helpers and for why the suite is split this way.
import UIKit
import XCTest

final class OfflineCoverageTests: ScreenshotTestCase {
    // The CHS pending card speaks plain language — held pending by the network
    // kill switch (no fit can start, honest offline stand-in). Both station
    // kinds in one launch: a plain CHS tide port (Victoria) and a DERIVED gate
    // (Malibu Rapids), which is pending for a different reason — its reference
    // port, Point Atkinson, is the thing that is unfitted. One launch, because
    // they assert the same string under identical launch args.
    func testChsPendingCopy() throws {
        // Victoria fix: the pending copy is what a QUEUED station says, and the
        // queue is built from the ranking anchor. Without an explicit fix the
        // anchor is whatever station the previous test opened, which decides
        // whether Victoria is in the download set at all.
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")  // Victoria
        // The visible card is an icon and two words (#93), but the
        // plain-language copy still has to reach VoiceOver, which is the reader
        // with the LEAST context, not the most.
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

    // #38: the derived-gate strip, offline, in the FAST plan. A derived gate
    // is the one path where EVERY slack takes the windowless branch — no
    // `slackWindows` by design, so every gate event draws a dropline + gutter
    // time and never a band — and testM46MalibuDerivedGate (the only other
    // render of it) needs a live IWLS fit, so without this test a normal run
    // renders it nowhere. `-seedTideModel` stores a synthetic fit for the
    // reference port (Point Atkinson) before ChsFitService's one-time directory
    // read, so the same detail renders with no network; `-networkKillSwitch`
    // keeps it honest. No `-chsResetModels`: the seed hook wipes the store itself
    // (combining them would delete the seed — TestSeeds.swift's comment).
    func testM46MalibuDerivedGateSeededOffline() throws {
        let app = launch("-seedGate", "-networkKillSwitch",
                         "-seedTideModel", "chs-point-atkinson")

        openSearch(app, "malibu")
        pickSearchResult(app, app.staticTexts["Malibu Rapids"].firstMatch)

        // A derived gate predicts no speed, so its lead is the phase word over
        // the time and nothing else — the one detail kind whose reading has no
        // number in it (spec §3).
        let lead = leadReading(app)
        XCTAssert(lead.waitForExistence(timeout: 10),
                  "seeded reference fit did not render the derived-gate detail")
        let leadLabel = lead.label
        XCTAssertNotNil(leadLabel.range(of: "flooding|ebbing|slack",
                                        options: [.regularExpression, .caseInsensitive]),
                        "the derived-gate lead must speak the phase word, got '\(leadLabel)'")
        XCTAssertFalse(leadLabel.contains("kn"),
                       "a derived gate publishes no speed: '\(leadLabel)'")
        XCTAssert(app.staticTexts["9 kn flood & ebb"].waitForExistence(timeout: 5),
                  "derived gate lost the magnitude context under its tiles")
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
        sleep(1)  // the header's offline tile floor; MLNMapView reports nothing
        save(app, "m46-derived-gate-seeded.png")

        // A derived gate scrubs like the other three, so it needs the same way
        // home: the Now pill on the strip's chrome row.
        scrubStrip(app)
        let now = app.buttons["detail-return-now"].firstMatch
        XCTAssert(now.waitForExistence(timeout: 5),
                  "scrubbing a derived gate revealed no return-to-now")
        XCTAssert(now.isHittable, "return-to-now is not hittable: \(now.frame)")
        now.tap()
        XCTAssert(now.waitForNonExistence(timeout: 10),
                  "return-to-now did not bring the derived-gate strip home")
    }

    /// Issue #33: a Downloads row is a live tap — it closes the sheet and opens
    /// the station's own detail via `openChsRoute` (Theme.swift), the same
    /// generalized closure the online-gate honesty card's nearest-shipped link
    /// shares. `-chsResetModels` wipes the model
    /// store so the whole queue starts `.pending`, and the Victoria fix
    /// puts Victoria itself at distance zero from the ranking anchor — so it is
    /// the queue's first job, deterministically. The fix is not optional: the
    /// queue is adopted from the anchor and nothing else seeds it, so without
    /// one this test inherits whatever station the previous test opened
    /// (#205 — `init` sorts around the fallback, it does not adopt it).
    /// The chart-pack card in the offline manager: automatic downloads have
    /// to be visible, or a sailor cannot tell whether the map is ready before
    /// leaving signal.
    func testChartPackCardShowsStateAndOffersRefresh() throws {
        let app = launch("-seedGate", "-fixLat", "48.406", "-fixLon", "-122.643")
        app.buttons["offline-status"].firstMatch.tap()
        // The state line is the card: a VStack identifier does not surface as
        // its own element, so assert on what the user actually reads.
        let state = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'CHARTS'")).firstMatch
        XCTAssert(state.waitForExistence(timeout: 10),
                  "the downloads manager must say what state the map is in")
        save(app, "chart-packs-manager.png")
        XCTAssert(app.buttons["charts-refresh"].firstMatch.exists,
                  "a sailor must be able to top the charts up before departure")
    }

    func testDownloadsRowOpensDetail() throws {
        let app = launch("-seedGate", "-chsResetModels",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")  // Victoria

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
        let header = app.otherElements["detail-header"].firstMatch
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

    /// The row's own tap gesture and the Retry button (`service.promote`, shown
    /// only on a `.failed` job) are siblings in the same `HStack` — the Retry
    /// button ahead of `.contentShape`/`.onTapGesture` in the modifier chain,
    /// per the row-tap comment. This proves the button wins the hit test
    /// rather than the row's gesture swallowing it (#33). `-chsFailOnly`
    /// (ChsFitService.swift) marks a job `.failed` at launch, no network
    /// attempt — a real fetch failure isn't deterministic for a fast test, and
    /// `-networkKillSwitch` keeps every OTHER job inert too (`run()`'s claim
    /// loop only ever touches `.pending` jobs, so the seeded `.failed` status
    /// sticks until something explicitly retries it).
    ///
    /// Seeded on Victoria HARBOUR, deliberately NOT plain Victoria: at regular
    /// width the split layout auto-selects a first detail on `.onAppear`
    /// (StationListView.swift), and under this test's Victoria fix that is the
    /// nearest station — chs-victoria itself. `ChsDetailView.onAppear`
    /// unconditionally promotes whatever route it shows, so seeding
    /// chs-victoria as `.failed` is self-defeating on iPad: auto-select
    /// opens it and silently un-fails it before this test ever touches the
    /// sheet (confirmed live — the Retry button and the "still failed"
    /// precondition are gone by the very first read). Victoria
    /// Harbour is the second-nearest port — queued (inside the auto-fit set's
    /// nearest 6 ports) but never auto-selected — so it stays genuinely
    /// `.failed` until this test's own tap.
    func testDownloadsRowRetryButtonWinsOverRowTap() throws {
        let app = launch("-seedGate", "-chsResetModels", "-networkKillSwitch",
                         "-chsFailOnly", "chs-victoria-harbour",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")  // Victoria

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
        waitFor(row, "label CONTAINS 'YOU OPENED' AND label CONTAINS 'Waiting'")

        // Promote's own visible effect proves the BUTTON's action ran: the
        // failed row flips to promoted+pending — "YOU OPENED" and "Waiting"
        // replace the Retry pill. The row renders EITHER the Retry button OR
        // `statusText(job)`, never both (OfflineDownloads.swift's `row(_:)`),
        // so "Waiting" in the label already implies Retry is gone.
        let label = row.label
        XCTAssert(label.contains("YOU OPENED") && label.contains("Waiting"),
                  "tapping Retry did not promote the row — expected \"YOU OPENED\"/\"Waiting\" in its label, got \"\(label)\"")

        // And the row tap's OWN effect never fired: the sheet is still up.
        // NOT a bare "no detail-header exists" check — on iPad the split
        // layout auto-selects Victoria's OWN detail underneath this sheet
        // regardless of anything this test does (the same auto-select the
        // doc comment above routes around), so a header legitimately exists
        // throughout. The header's NAME is the tell: if the row's gesture had
        // fired instead of the button, it would have pushed Victoria
        // Harbour's detail, replacing what's shown.
        XCTAssert(app.staticTexts["Downloads"].exists,
                  "the row's onTapGesture must not have fired — the Retry button owns this tap")
        let header = app.otherElements["detail-header"].firstMatch
        if header.exists {
            XCTAssertFalse(header.staticTexts["Victoria Harbour"].firstMatch.exists,
                           "no detail should have opened — the button, not the row, must have handled the tap")
        }
    }

    /// #205: far from Canadian water, nothing downloads and the manager is
    /// empty. This is the reported bug end to end — the reporter opened this
    /// sheet from Massachusetts and found 30 Canadian downloads in flight.
    ///
    /// Boston is the fix because it is the reported one and because it is the
    /// case the unit budget tests structurally cannot see: they exercise
    /// Victoria and Halifax, which sit on Canadian water, where an unguarded
    /// port budget and a guarded one produce the same six ports. Its nearest
    /// CHS port is Montréal Jetée #1 at 402 km — a river gauge — while its
    /// nearest station of any source is NOAA Boston at 1 km.
    ///
    /// Both halves are asserted here because they fail independently: a fitted
    /// row means the port radius let a far station through, and an online-gate
    /// row means the manager listed a Salish pass it can never fetch.
    func testFarFromCanadaDownloadsNothing() throws {
        // Favorites intentionally download regardless of distance; earlier
        // tests can leave a Canadian favorite on this simulator.
        let app = launch("-seedGate", "-resetFavorites", "-chsResetModels", "-networkKillSwitch",
                         "-fixLat", "42.3601", "-fixLon", "-71.0589")  // Boston

        app.buttons["offline-status"].firstMatch.tap()
        XCTAssert(app.staticTexts["Downloads"].waitForExistence(timeout: 5),
                  "the indicator did not open the downloads manager")
        save(app, "downloads-boston.png")

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'download-row-'"))
        XCTAssertEqual(rows.count, 0,
                       "a Boston fix must download no Canadian station: \(rows.count) rows")
    }

    // MARK: - The US and Canada

    /// A station 4,000 km from the Salish Sea is searchable, opens, and draws a
    /// real curve from bundled NOAA harmonics — no download, no signal needed,
    /// same screen as Friday Harbor.
    func testM53UsEastCoastStationRendersACurve() throws {
        // Airplane mode: whatever renders here is bundled, not fetched.
        let app = launch("-seedGate", "-networkKillSwitch")

        openSearch(app, "boston")
        pickSearchResult(app, app.staticTexts["Boston"].firstMatch)

        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 10),
                  "an east-coast station did not open a real detail")
        XCTAssert(app.staticTexts["MA"].firstMatch.exists,
                  "the region line fell back to the Salish gazetteer")
        // A curve, not an empty chart: heights and clock times both render, and
        // Boston's range is metres — the numbers are the station's own.
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty,
                       "no height readings on the Boston detail")
        XCTAssertGreaterThanOrEqual(scheduleValues(app, "\\b\\d{1,2}:\\d{2}(?:am|pm)\\b").count, 3,
                                    "no schedule on the Boston detail")
        sleep(3)  // header map tiles: MLNMapView surfaces no load state to XCUITest
        save(app, "m53-us-station.png")

        // And the west coast, through the same path.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "san francisco")
        pickSearchResult(app, app.staticTexts["San Francisco (Golden Gate)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 10))
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
        pickSearchResult(app, app.descendants(matching: .any)["chs-pending-chs-halifax"].firstMatch)

        XCTAssert(app.staticTexts["Waiting for signal"].waitForExistence(timeout: 8),
                  "opening an undownloaded Canadian station must explain itself")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'works offline'")).firstMatch.exists)
        // The waiting page wears the same name header the four scrub details
        // do, and nothing else above the status card — no map, no strip.
        XCTAssert(app.otherElements["detail-header"].exists,
                  "the waiting page must still name the station it is waiting for")
        XCTAssertFalse(app.otherElements["detail-map-header"].exists,
                       "no map header belongs above a station that has no data yet")
        XCTAssertFalse(app.otherElements["timeline-strip"].exists,
                       "an undownloaded station has nothing to draw")

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

    // MARK: - Online gates (the 7 fit-reject gates, fetched-on-demand CHS
    // predictions instead of an on-device fit — no network here either: the
    // seeded test relies on `ChsModelStore.saveOnline` writing a covering
    // window before the app ever draws a frame. The unfetched honesty-card
    // walk lives in ListAndFavoritesTests, beside the other star-resolution
    // tests.)

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
        // passing. (The reset runs first — the seed hook touches
        // ChsFitService.shared before seeding, precisely for this.)
        let app = launch("-seedGate", "-chsResetModels",
                         "-seedOnlineWindow", "chs-sechelt-rapids",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)

        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "the seeded window did not render the fetched strip")
        assertCurrentDetailRendered(app)
        let pill = commentaryPill(app)
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "no commentary pill on the online-gate detail")
        XCTAssert(pill.label.hasPrefix("Slack") || pill.label.contains("Max")
                  || pill.label.hasPrefix("Flood") || pill.label.hasPrefix("Ebb"),
                  "the commentary must name a current stop, got '\(pill.label)'")

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
        XCTAssertFalse(app.descendants(matching: .any)["online-honesty-card"].firstMatch.exists,
                       "a covering window must render the real detail, not the honesty card")

        // #38: the fetched strip (slack BANDS, unlike the derived gate's
        // droplines) must actually draw, and a normal run should leave a
        // screenshot of it — this was the only offline render of the online
        // strip and nothing ever looked at it.
        let ink = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(ink > 0.05, "the online-gate strip drew nothing — ink \(ink)")
        sleep(1)  // the header's tile floor; MLNMapView reports nothing
        save(app, "online-gate-seeded.png")
    }

    /// Paging an online gate to a week nobody has downloaded, with no network,
    /// must SAY so — not render an empty strip that reads as slack water all
    /// week. Same picker choreography as `testPickingADateMovesTheWindow`, two
    /// months out so no 30-day window could cover it. The honesty card is not
    /// a dead end: the week-range bar survives it, and its picker is the way
    /// back to a week the app holds (#67 item 2), so the navigation back button
    /// is not the only way off this screen.
    func testOnlineGatePagedBeyondItsWindowOffline() throws {
        let app = launch("-seedGate", "-chsResetModels",
                         "-seedOnlineWindow", "chs-sechelt-rapids",
                         "-networkKillSwitch",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "the seeded window should render before we page off it")

        app.descendants(matching: .any)["week-range-bar"].firstMatch.tap()
        XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch
            .waitForExistence(timeout: 5))
        stepMonth(app, "Next Month")
        stepMonth(app, "Next Month")   // two months out — past the 30-day window
        tapDay(app.collectionViews.buttons.element(boundBy: 10))
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
        stepMonth(app, "Previous Month")
        stepMonth(app, "Previous Month")
        let todayCell = app.collectionViews.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'today'")).firstMatch
        XCTAssert(todayCell.exists, "the graphical picker labels today's cell")
        tapDay(todayCell)
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()
        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "back on the seeded week, the strip must render from disk — offline")
    }

    /// #67 item 4, hermetically: two DISJOINT seeded blocks, no network. A
    /// single-window store discards today's block when the far seed saves,
    /// which this test's very first strip assertion catches; and paging into
    /// the far block must render from disk, which is the multi-block payoff.
    func testOnlineGatePagesBetweenSeededBlocksOffline() throws {
        let app = launch("-seedGate", "-chsResetModels",
                         "-seedOnlineWindow", "chs-sechelt-rapids",
                         "-seedOnlineFarWindow", "chs-sechelt-rapids",
                         "-networkKillSwitch",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)

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
            stepMonth(app, "Next Month")
            monthsAdvanced += 1
        }
        XCTAssert(targetCell.waitForExistence(timeout: 1),
                  "today+45d cell (\(targetLabel)) not found within 3 months forward")
        tapDay(targetCell)
        app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()

        XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
                  "a far week the app holds on disk must render offline, not honesty-card")
        XCTAssertFalse(app.descendants(matching: .any)["online-honesty-card"].firstMatch.exists)
        let ink = inkFraction(app.otherElements["timeline-strip"].firstMatch)
        XCTAssert(ink > 0.05, "the far block's strip drew nothing — ink \(ink)")
        save(app, "online-gate-far-block.png")
    }
}
