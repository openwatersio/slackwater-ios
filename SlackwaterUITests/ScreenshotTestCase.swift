// Slackwater — GPL v3. The shared base for the UI-test classes that walk the
// app's surfaces and save screenshots. They double as the smoke check that
// every interaction actually responds.
//
// The app opens on the first-run gate, then the list — tests seed or reset that
// state explicitly (-seedGate / -resetGate) because a UserDefaults value passed
// as a launch argument would mask in-app writes.
//
// The suite is split across several classes because XCTest distributes parallel
// work per CLASS, not per test: with `parallelizable` set on this target in
// TestPlans/Slackwater.xctestplan, each class gets its own simulator clone. The
// four screenshot classes are weight-balanced from measured durations so the
// clones finish together, and every live-IWLS test lives in LiveFetchTests so
// those requests stay sequential however many clones run — a clone is its own
// process, and the fetcher's request pacing cannot coordinate across processes.
import UIKit
import XCTest
import Darwin

class ScreenshotTestCase: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["M1_SHOT_DIR"] ?? "/tmp"
    static let fixtureNow = "1788868800"
    static let fixtureDate = Date(timeIntervalSince1970: TimeInterval(fixtureNow)!)

    func testArguments(_ args: [String], live: Bool = false) -> [String] {
        var result = args + ["-noCloudSync", "-currentFillOff", "-chartPacksOff",
                             "-nowEpoch", Self.fixtureNow]
        if !live && !args.contains("-chsFixture") && !args.contains("-networkKillSwitch") {
            result.append("-networkKillSwitch")
        }
        return result
    }

    func releaseFixture(_ token: String, _ checkpoint: String) {
        let name = "org.openwaters.slackwater.ui.\(token).\(checkpoint)"
        XCTAssertEqual(name.withCString { notify_post($0) }, NOTIFY_STATUS_OK,
                       "could not release UI fixture checkpoint \(checkpoint)")
    }

    /// Wait for a condition `waitForExistence` cannot express — hittability,
    /// keyboard focus, a label the app rewrites when the work behind it lands.
    /// Generous by default: on a machine running parallel simulator clones a
    /// wait that passes costs nothing, while one that is too short costs an
    /// intermittent failure, the worst thing a guard suite can carry.
    /// Returns rather than asserts — the caller's own assertion, taken after
    /// the wait, is what reports the failure and names it.
    @discardableResult
    func waitFor(_ element: XCUIElement, _ condition: String,
                 timeout: TimeInterval = 10) -> Bool {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: condition),
                                            object: element)
        return XCTWaiter().wait(for: [met], timeout: timeout) == .completed
    }

    /// Search lives behind the bottom-left FAB. Opens it and types with
    /// NO field tap — typeText throws unless the field already has keyboard
    /// focus, so every use doubles as the keyboard-up-immediately assertion.
    func openSearch(_ app: XCUIApplication, _ text: String) {
        let fab = app.buttons["Search"].firstMatch
        XCTAssert(fab.waitForExistence(timeout: 10), "search FAB did not appear")
        // retap if dropped — once search opens the FAB is a11y-hidden, so no double-fire
        let field = app.textFields.firstMatch
        var opened = false
        for _ in 0..<3 {
            if fab.exists, fab.isHittable { fab.tap() }
            if field.waitForExistence(timeout: 5) { opened = true; break }
        }
        XCTAssert(opened, "search input did not appear")
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
        XCTAssert(XCTWaiter().wait(for: [focused], timeout: 10) == .completed,
                  "search field did not take keyboard focus")
        field.typeText(text)
    }

    /// Tap a search result and confirm the pick actually landed. The overlay
    /// closes itself on a successful pick, so the search field disappearing
    /// IS the landed signal — and the one queryable thing a dropped tap
    /// leaves unchanged. Same dropped-tap mechanism and bounded retap as
    /// openSearch's FAB: under clone load a tap can land mid-refilter (each
    /// keystroke re-ranks the results) and die silently. Retapping cannot
    /// double-fire — once the overlay closes, the result card is gone.
    func pickSearchResult(_ app: XCUIApplication, _ result: XCUIElement) {
        XCTAssert(result.waitForExistence(timeout: 10), "search result did not appear")
        let field = app.textFields.firstMatch
        for _ in 0..<3 {
            // `exists`, not `isHittable`: a result under the search bar reads
            // as not hittable yet takes the tap (ten "Boston" hits since #268
            // put the tide station fourth, under the bar). The guard is for a
            // result that vanished mid-refilter, and `exists` is that test.
            if result.exists { result.tap() }
            if field.waitForNonExistence(timeout: 5) { return }
        }
        XCTFail("tap on a search result never closed the search overlay")
    }

    /// The X glass circle beside the bottom input.
    func closeSearch(_ app: XCUIApplication) {
        app.buttons["Close search"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
    }

    /// The list's own scroll container. `app.swipeUp()` gestures at the centre
    /// of the whole app, which in the iPad split lands in the DETAIL pane and
    /// scrolls nothing — the sidebar list has to be swiped directly. The pane
    /// opens on a station, so "the first scroll view" is the detail's as often
    /// as the list's: go by identifier, and only then guess.
    func listContainer(_ app: XCUIApplication) -> XCUIElement {
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
    /// ~80pt exclusion the schedule-row taps apply inline, "home indicator
    /// band" case). Bare `isHittable` alone is not enough for
    /// elements near the list's bottom — XCUITest counts an element hittable
    /// the moment any part of it is on-screen and unobscured by an ancestor's
    /// clipping, which can be true while it still sits directly under the
    /// FAB circles' own hit-test region: a swipe or tap aimed at it then
    /// silently lands on the FAB instead and nothing happens (confirmed by
    /// diagnostic frame dumps: at the bare-isHittable stopping point the
    /// Recents row's bottom edge sat within 1pt of the FAB zone's top edge;
    /// one more swipe carried it clear by ~68pt and it stayed there — the
    /// list was genuinely bottomed out, not still scrolling).
    func scrollTo(_ el: XCUIElement, in app: XCUIApplication) {
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
    /// a window-normalized offset (dy 0.8) misses the strip on iPad.
    func scrubStrip(_ app: XCUIApplication) {
        let strip = app.otherElements["timeline-strip"].firstMatch
        XCTAssert(strip.waitForExistence(timeout: 5), "timeline strip missing")
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo:
                strip.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
    }

    /// The standard preamble: launch with `args`, wait for the list. Tests
    /// whose first screen is not the list (the FTUE gate, -openMap) and
    /// mid-test relaunches on an existing app stay inline.
    func launch(_ args: String...) -> XCUIApplication {
        launch(args)
    }

    func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // -noCloudSync on every launch: favourites live in iCloud KVS (#134),
        // the simulator's copy outlives the run, and a test that stars a gate
        // would otherwise leak it into the next test's "clean" device.
        app.launchArguments = testArguments(args)
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        return app
    }

    func launchLive(_ args: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = testArguments(args, live: true)
        app.launch()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 10))
        return app
    }

    /// The small live-IWLS compatibility smoke class skips itself outside
    /// `./scripts/test.sh --live`, which sets
    /// TEST_RUNNER_SLACKWATER_LIVE=1 — xcodebuild strips the prefix and sets
    /// the rest on this UI-test runner process, the same route M1_SHOT_DIR
    /// rides above.
    func skipUnlessLive() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SLACKWATER_LIVE"] == nil,
                      "live IWLS smoke — run ./scripts/test.sh --live")
    }

    /// Units live in Settings only: toggle there.
    func setUnits(_ app: XCUIApplication, _ label: String) {
        app.buttons["Settings"].tap()
        let segment = app.buttons[label]
        XCTAssert(segment.waitForExistence(timeout: 5))
        // The sheet's two fixed statements, asserted on the way past. Every
        // caller of this helper already has them on screen, so they are checked
        // here rather than in a test of its own with its own launch and its own
        // Settings round trip.
        XCTAssert(app.staticTexts["Not for navigation."].exists,
                  "the settings sheet lost its disclaimer")
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'VersaTiles'")).firstMatch.exists,
                  "the settings sheet lost its map attribution")
        segment.tap()
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
    }

    /// Search "friday" via the FAB → tap the tide card → detail (the overlay
    /// closes itself on the pick).
    func openFridayHarbor(_ app: XCUIApplication) {
        openSearch(app, "friday")
        pickSearchResult(app, app.staticTexts["Friday Harbor"].firstMatch)
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
    }

    /// The share of an element's pixels that differ from its most common
    /// colour — "is anything drawn here". Measured on this strip: 0.008 blank
    /// (centerline, riding dot and the ft axis, all SwiftUI overlay ON TOP of
    /// the canvas), 0.13 drawn. The 0.05 threshold sits in the order of
    /// magnitude between them, so it needs no per-device tuning.
    func inkFraction(_ element: XCUIElement) -> Double {
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

    /// Tap the pin at (lat, lon) on the fixed Salish camera, by mercator math.
    func tapPin(_ map: XCUIElement, _ lat: Double, _ lon: Double) {
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

    /// Tap the detail's header title: the map comes up and the detail is gone.
    /// The camera move itself is not independently assertable — no accessibility
    /// surface exposes `MLNMapView`'s live center — so this is the navigation
    /// contract; the `.id(mapFocusToken)` remount is verified by reading
    /// MapScreen.swift (#32).
    func assertTitleTapFocusesMap(_ app: XCUIApplication) {
        // Top of the detail, under the status bar clearance — should be
        // hittable the moment the header renders, no scroll needed.
        let title = app.descendants(matching: .any)["detail-title"].firstMatch
        XCTAssert(title.waitForExistence(timeout: 10), "detail-title missing")
        // bounded retap (see pickSearchResult); a landed tap pops the title with the detail
        let canvas = app.otherElements["map-canvas"].firstMatch
        var shown = false
        for _ in 0..<3 {
            if title.exists, title.isHittable { title.tap() }
            if canvas.waitForExistence(timeout: 5) { shown = true; break }
        }
        XCTAssert(shown, "the title tap did not show the map")
        XCTAssertFalse(app.otherElements["detail-header"].exists,
                       "the title tap must pop the detail, not layer the map over it")
    }

    /// Time-to-first-usable, printed into the test log. These four numbers —
    /// nearest tide port, 60-day gate, 210-day gate provisional, same gate
    /// final — are what the fast answer exists to move, so they get measured,
    /// not guessed.
    func report(_ what: String, _ from: Date) {
        print("M51 TTFU · \(what): \(String(format: "%.1f", -from.timeIntervalSinceNow)) s")
    }

    /// Drag from the very left edge — the interactive pop, not a content swipe.
    /// Anchored to the detail header's own band (near its bottom, not its
    /// screen-midpoint fraction) when a header is on screen: the header is only
    /// a third of the screen tall, and a start point
    /// close to the top of the screen — under the status bar / Dynamic
    /// Island — silently loses the touch to the system rather than the app's
    /// edge-pop gesture (verified by sweeping dy: 0.05 never pops, 0.15
    /// always does, on a 141pt-tall header). Low in the header stays clear of
    /// that zone at any Dynamic Type size. On the root list (no header, e.g.
    /// the no-op check) fall back to the same safe screen fraction.
    func edgeSwipeBack(_ app: XCUIApplication) {
        let header = app.otherElements["detail-header"].firstMatch
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

    /// The lead reading under the centerline — the page's one readout, and the
    /// only element that carries the scrubbed time. `LeadCard` combines its
    /// children, so the eyebrow, the value and the time arrive as one label and
    /// no bare "4:22pm" static text exists to query.
    func leadReading(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["detail-reading"].firstMatch
    }

    /// The time the strip's centerline is parked on ("1:42pm"), pulled out of
    /// the lead's combined label. Never nil: a missing readout is a hard test
    /// failure inside the query itself. One resolve on purpose — an `exists`
    /// pre-check is a second snapshot, and callers read this mid-deceleration,
    /// where the extra round trip lands the read after the moment the assertion
    /// is about. The whole label is the fallback: it moves with the scrub too,
    /// so a settle still settles.
    func scrubClock(_ app: XCUIApplication) -> String {
        let label = leadReading(app).label
        guard let time = label.range(of: "\\d{1,2}:\\d{2}(am|pm)",
                                     options: .regularExpression) else { return label }
        return String(label[time])
    }

    /// A current detail — harmonic station or gate — has rendered: the lead
    /// reading over the strip and the Next max tile beside the moon. The pair
    /// is what says "this page is a live current detail" rather than a pending
    /// or honesty card, and both are anatomy every current kind shares.
    func assertCurrentDetailRendered(_ app: XCUIApplication, timeout: TimeInterval = 10) {
        XCTAssert(leadReading(app).waitForExistence(timeout: timeout),
                  "no lead reading on the current detail")
        // Case-insensitive: the tile's eyebrow combines a MonoLabel that
        // uppercases with an accessibility label that does not.
        XCTAssert(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] 'Next max'")).firstMatch
            .waitForExistence(timeout: timeout),
                  "no Next max tile on the current detail")
    }

    /// The glass pill on the strip's chrome row, naming the stop ahead. Every
    /// scrubable detail has one; a current's names a slack, a run or a max.
    func commentaryPill(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["commentary"].firstMatch
    }

    /// The schedule rows' accessibility labels — NOT every "HH:mm" label on
    /// screen, which also picks up the chart annotations. Callers need the
    /// schedule scoped out of the whole hierarchy, see below.
    ///
    /// Scoping matters on iPad and only on iPad. The split-view sidebar renders
    /// live station cards with the reading on the card's right, so they emit
    /// `X.X ft` strings that match the same regexes the schedule rows do. A
    /// caller that scrapes twice and diffs then blames the detail
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
    func scheduleRowLabels(_ app: XCUIApplication) -> [String] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'schedule-row-d'"))
            .allElementsBoundByIndex
            .compactMap { $0.exists ? $0.label : nil }
    }

    /// Every substring of the schedule rows matching `pattern`. Unanchored by
    /// design: the row label is a combined string like "05:48 2.2 ft ↑ HIGH",
    /// so an anchored `^…$` — one value per element — matches nothing.
    func scheduleValues(_ app: XCUIApplication, _ pattern: String) -> Set<String> {
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

    func save(_ app: XCUIApplication, _ name: String) {
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
    /// and the next read, which is how testM50RecentsNamesFit failed again on a
    /// 3pt shift when the row's gap is only 2pt (PR #25). So read EVERY frame
    /// a comparison needs inside this closure: it re-reads them all together
    /// until two consecutive passes agree, and hands back that ONE layout.
    /// Never re-read `.frame` after this.
    func settled<T: Equatable>(_ read: () -> T) -> T {
        var snapshot = read()
        for _ in 0..<20 {
            usleep(250_000)
            let again = read()
            if again == snapshot { break }
            snapshot = again
        }
        return snapshot
    }

    /// A transition — a push, a pop, a rotation, a swipe's deceleration — ends
    /// with no accessibility signal of any kind, so settle a frame the
    /// transition actually moves and carry on from there. Two consecutive
    /// agreeing reads (`settled`) is the animation having stopped.
    func settleLayout(_ element: XCUIElement) { _ = settled { element.frame } }

    /// The strip parked. A scrub's time lands in two steps — the scroll
    /// decelerates, then the magnet snaps to the nearest stop and writes
    /// `scrubTime` when ITS animation ends (TimelineStrip's scroll
    /// coordinator) — and neither step exposes an element to wait on. The
    /// centerline reading moves with every frame of both, so settling it
    /// settles them.
    func settleScrub(_ app: XCUIApplication) { _ = settled { scrubClock(app) } }

    /// ChsAmberCard's action renders as a `.plain` Button whose label is an
    /// HStack; whether XCUI surfaces it as a button or a static text has
    /// differed by card, so try both rather than guess.
    func tapAmberAction(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons[label].firstMatch
        if button.exists { button.tap(); return }
        let text = app.staticTexts[label].firstMatch
        XCTAssert(text.waitForExistence(timeout: 5), "amber action \"\(label)\" is not on screen")
        text.tap()
    }
}
