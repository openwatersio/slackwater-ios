// Slackwater — GPL v3. Every test that fetches live from IWLS and fits on the
// device. Each costs minutes; all of them skip themselves unless
// ./scripts/test.sh --full is what started the run (skipUnlessFull).
//
// They share ONE class deliberately. XCTest runs a class's tests serially on a
// single simulator clone, so keeping them together is what stops several clones
// hitting the API at once — the fetcher's 2.5 s pacing is per process, and a
// clone is its own process, so it cannot pace what another clone is doing.
// A live-IWLS test added anywhere else in this target loses that guarantee.
import UIKit
import XCTest

final class LiveFetchTests: ScreenshotTestCase {
    // Canadian (CHS) stations — pending state, a REAL end-to-end fit
    // against live IWLS, then the airplane-mode day-after relaunch. One test,
    // in order, because the offline half depends on the fit half's stored model.
    func testM3ChsPendingFitOffline() throws {
        try skipUnlessFull()
        // Scoped to Victoria. Unscoped, every launch also starts the
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
        // shows numbers. (Cards are not buttons: rows navigate via a hidden
        // link.)
        // Scoped to the search overlay's ScrollView: the list behind
        // it is accessibility-hidden but still QUERYABLE, so an unscoped match
        // can pick up some other station's Rising/Falling and let the test walk
        // into a Victoria that is still downloading. Scoping to a ScrollView is
        // not enough either: `app.scrollViews.firstMatch` resolves to whichever
        // scroll view the query walks first, which is the list BEHIND the
        // overlay, so the wait returns on some other station's card and the
        // test opens a Victoria with no model — the waiting page, four
        // assertions down.
        // The pending card carrying Victoria's own id is the unambiguous signal:
        // it exists while the fit is outstanding and goes away when it lands.
        XCTAssert(pending.waitForNonExistence(timeout: 300), "Victoria never fitted — IWLS unreachable?")
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
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
        pickSearchResult(app, app.staticTexts["Victoria"].firstMatch)
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["⤒ HIGH"].firstMatch.waitForExistence(timeout: 5)
                  || app.staticTexts["⤓ LOW"].firstMatch.waitForExistence(timeout: 5))
    }

    // A validated CHS current gate (Dodd Narrows) — pending copy in the
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
        // Pending: identity + the honest currents message, no numbers. By id —
        // the copy alone matches every undownloaded station.
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

        pickSearchResult(app, app.staticTexts["Dodd Narrows"].firstMatch)
        // Full current-detail anatomy: the slack countdown and the CHS
        // provenance footer (device-computed, not CHS-published). Dodd is
        // a 210-day gate, so the card above lands on its 60-day fast answer —
        // the final footer is the tell that the full model has replaced
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
        pickSearchResult(app, app.staticTexts["Dodd Narrows"].firstMatch)
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.waitForExistence(timeout: 10))
    }

    // After the reference port fits (live IWLS), the gate card
    // shows the phase pill + next slack, and the detail renders the
    // current-only strip (the port sources slacks, it is
    // not a track of its own), slack rows with no speeds, and the derived
    // provenance copy.
    func testM46MalibuDerivedGate() throws {
        try skipUnlessFull()
        // Point Atkinson is 100 km from the Victoria fallback, so it is
        // NOT in the auto-fit set — opening the gate is what downloads it,
        // which is the behaviour under test. Scoped so that is the only fit in
        // flight (testM3ChsPendingFitOffline says why unscoped live tests
        // fight each other).
        let app = launch("-seedGate", "-chsFitOnly", "chs-point-atkinson")

        // ONE tap. The gate always opens — showing the ⚠️ download
        // warning if its reference port (Point Atkinson) isn't fitted yet —
        // and opening it moves that port to the front of the queue, so the
        // page fills in live with no second tap and no back-and-forth.
        openSearch(app, "malibu")
        pickSearchResult(app, app.staticTexts["Malibu Rapids"].firstMatch)
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

        // Print today's rendered schedule times into the test log, to be read
        // against CHS's published ones. Scoped to the rows via scheduleValues:
        // unscoped, this print would quietly include iPad sidebar card readings.
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
        sleep(4)  // tiles: MLNMapView surfaces no load state to XCUITest
        // Malibu (50.16, -123.85) sits north-west of the camera — drag the
        // map content south-east to bring the pin into the frame's middle
        // (one full drag + one short one; two full drags left it at the edge).
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo:
                map.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.8)))
        sleep(1)  // the pan's own inertia, before the second drag starts
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.35))
            .press(forDuration: 0.1, thenDragTo:
                map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.62)))
        sleep(3)  // the newly exposed tiles, for the shot — again, no predicate
        save(app, "m46-malibu-map.png")
    }

    // The offline-downloads system — the indicator beside the gear, the
    // manager it opens, the proximity-ordered queue, and the no-dead-taps rule:
    // an unfitted station opens its detail with the ⚠️ explanation and
    // jumps to the front of the queue. Runs against LIVE IWLS from a clean
    // store — nothing here waits for a fit to land, only for the
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
        // the indicator's own value flips to "Downloading, x of y ready" once a job is claimed
        waitFor(indicator, "value BEGINSWITH 'Downloading'", timeout: 30)

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
        // queue sorts them. The list is the DOWNLOAD SET, so Sooke (30 km
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

        // No dead taps: the farthest station in the catalogue is last in
        // the queue and has nothing to show — tapping it still opens a detail,
        // and that detail explains itself.
        openSearch(app, "weynton")
        pickSearchResult(app, app.staticTexts["Weynton Passage"].firstMatch)
        XCTAssert(app.staticTexts.matching(NSPredicate(
            format: "label == 'Waiting' OR label == 'Downloading…'"
        )).firstMatch.waitForExistence(timeout: 5),
                  "a queued station must expose its live queue state")
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

    /// The nearest tide port, at its validated 60 d — the baseline the gate
    /// numbers below are read against.
    func testM51NearestTidePortTimeToFirstUsable() throws {
        try skipUnlessFull()
        let t0 = Date()
        let app = launch("-chsResetModels", "-seedGate", "-chsFitOnly", "chs-victoria",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        openSearch(app, "victoria")
        // By station id, not by copy. Every undownloaded Canadian station
        // says "Canadian tidal predictions", and "victoria" matches several.
        let pending = app.descendants(matching: .any)["chs-pending-chs-victoria"].firstMatch
        XCTAssert(pending.waitForExistence(timeout: 15), "no CHS Victoria card in the results")
        // timed below: wait on the card itself, not a poll grid that lands in the number
        _ = pending.waitForNonExistence(timeout: 240)
        XCTAssertFalse(pending.exists, "Victoria never fitted — IWLS unreachable?")
        report("nearest tide port (60 d)", t0)
        XCTAssert(app.scrollViews.firstMatch.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^\\d+\\.\\d+ (ft|m)$")).firstMatch.exists,
                  "a fitted port must show a height, not just lose its pending copy")
    }

    /// A gate validated at 60 d: one short fetch, straight to FINAL. The
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
        pickSearchResult(app, app.staticTexts["Active Pass"].firstMatch)
        XCTAssert(app.staticTexts["NEXT SLACK"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'can be off by up to'")).firstMatch.exists,
                       "no fast-answer warning belongs on a final model")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'computed on this device'")).firstMatch.exists,
                  "final models keep the ordinary CHS provenance footer")
    }

    /// A 210-day gate shows its fast answer at ~60 d, says by how
    /// much it can be wrong AT THIS PASS, then refines in place under an open
    /// page — the amber marking clearing is the transition to final.
    func testM51ProvisionalGateShowsFastAnswerThenRefines() throws {
        try skipUnlessFull()
        let t0 = Date()
        let app = launch("-chsResetModels", "-seedGate", "-chsFitOnly", "chs-dodd-narrows",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        openSearch(app, "dodd")

        // The fast answer, in the list: the amber "Refining · ±35 min" strip and
        // a tilde'd reading, and that is ALL. Amber PROSE on the card measures
        // 1.03:1 against the palest station gradient, and a bare ⚠️ badge says
        // nothing a reader could act on (#93). The full explanation lives on
        // the detail.
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
        // time-of-day form this test can land on (observed on iPad at 6:07 PM).
        // Both forms keep a hedged number on the card.
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '~'")).firstMatch.exists,
                  "the tilde stays: the reading itself must still say it is not exact")

        // …and in the detail: the ⚠️ family, with the real number in it.
        pickSearchResult(app, app.staticTexts["Dodd Narrows"].firstMatch)
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
        _ = warning.waitForNonExistence(timeout: 300)
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
        waitFor(dodd, "label CONTAINS 'Refining'", timeout: 300)
        XCTAssert(dodd.label.contains("Refining"),
                  "the manager never showed the usable-but-unfinished state")
        XCTAssert(dodd.label.contains("FAST ANSWER ±35 MIN"),
                  "the manager must say how good the fast answer is, not just that there is one")
        app.buttons["Done"].tap()
    }

    /// Opening a station while a long gate is mid-download must not wait the
    /// gate out: the running job steps aside at the next CHUNK — and comes back
    /// to what it already fetched. Honouring the promotion only at the next
    /// STATION boundary costs up to ~2.5 min.
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
        pickSearchResult(app, app.staticTexts["Tofino"].firstMatch)
        XCTAssert(app.staticTexts["Downloading…"].waitForExistence(timeout: 10))
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
        let yieldStart = Date()
        waitFor(tofino, "label CONTAINS 'Downloading'", timeout: 300)
        XCTAssert(tofino.label.contains("Downloading"),
                  "opening a station did not interrupt the gate in flight "
                  + "(waited \(Int(-yieldStart.timeIntervalSinceNow)) s)")
        XCTAssert(app.descendants(matching: .any)["download-row-chs-dodd-narrows"]
            .firstMatch.label.contains("Waiting"), "the yielded gate must go back to waiting, not fail")
        print("M51 interrupt: promoted station started \(String(format: "%.1f", -t0.timeIntervalSinceNow)) s after the open")

        // And it resumes: once the promoted port is done the gate carries on
        // from its cached chunks (never re-fetching them — ChsProvisionalTests).
        // Same deadline as above: this clock covers Tofino's whole download,
        // which load stretches just as much as the yield (#65).
        waitFor(dodd, "label CONTAINS 'Downloading'", timeout: 300)
        XCTAssert(dodd.label.contains("Downloading"), "the yielded gate never resumed")
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
        // auto-fit set, so the set is downloading in the background throughout
        // — it should start with nothing, since nothing auto-downloads Nova
        // Scotia. Tap the CARD, not the name: at regular width the sidebar
        // behind the search overlay is accessibility-hidden but still
        // queryable, so `staticTexts["Halifax"].firstMatch` can resolve to
        // the hidden one.
        pickSearchResult(app, app.descendants(matching: .any)["chs-pending-chs-halifax"].firstMatch)
        XCTAssert(app.staticTexts["Downloading…"].waitForExistence(timeout: 20))

        // Promotion yields the running auto-fit job at its next chunk (~2.5 s),
        // then one 60-day tide fit: ~30 s of paced requests.
        let start = Date.now
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 180),
                  "an opened Canadian station never fitted")
        print(String(format: "M53 on-demand fit of Halifax: %.0f s", Date.now.timeIntervalSince(start)))
        XCTAssertFalse(scheduleValues(app, "\\b\\d+\\.\\d+ (?:ft|m)\\b").isEmpty,
                       "fitted, but no numbers")
    }

    /// Full-plan only (`skipUnlessFull` — run via ./scripts/test.sh --full):
    /// verified against REAL IWLS rather than a seeded window.
    /// Sechelt Rapids is one of the 7 fit-reject gates (ChsCurrentGate.swift) — this
    /// proves IWLS actually resolves and serves wcsp1/wcdp1 (its station pair) for a
    /// gate CHS rejects for on-device fitting, which is the online set's entire premise.
    /// No `-networkKillSwitch`, no `-seedOnlineWindow`: `-chsResetModels` wipes any
    /// stored window so `OnlineGateDetailView.onAppear` has to fetch live. If IWLS
    /// stops resolving or serving this station, the honesty card persists and the
    /// `online-provenance` wait times out — see the failure message below, which is
    /// the actual signal this test exists to produce: a timeout here means Sechelt
    /// may need dropping from the online set, a human call.
    func testOnlineGateLiveFetch() throws {
        try skipUnlessFull()
        let app = launch("-seedGate", "-chsResetModels",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)

        // Generous ceiling: a live IWLS fetch, not a seeded window.
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
}
