// Slackwater — GPL v3. The App Store sets (#4): five frames, shot once per
// device size App Store Connect requires. Same generator mechanism as
// WebsiteScreenshots — gated on SLACKWATER_SHOTS, driven by
// scripts/screenshots.sh, which pins the simulator, the 9:41 status bar and
// the directory the PNGs land in. That script's header carries the two
// commands; the frames are not committed.
//
// Everything that decides what is ON a frame is pinned: the app clock and the
// location fix and favorites come from `ShotWalk`, and each scrub instant is
// read off the station's own schedule rather than written down, so a
// regenerated harmonic bundle moves the frame instead of quietly flattening
// it. Frames are numbered because App Store Connect orders an upload by
// filename.
//
// Two standing constraints on what may appear. Premium is out of the Release
// build (#470), so the walk never opens Settings or the widgets gallery —
// the only two places PREMIUM_ENABLED surfaces anything, and both are on in
// the Debug build these tests run against. And nothing here may imply
// navigation use.
import XCTest

final class AppStoreScreenshots: ShotWalk {
    /// How wide a slice of the world the map frame shows, in degrees of
    /// longitude across the map pane, and where it is centered. Regional, not
    /// continental: the chart style stops drawing coastline and bathymetry
    /// detail long before a continent fits, and a wider camera flattens the
    /// Salish Sea into one grey shape with the pins as specks. At this span
    /// the passes are passes and every pin sits on a place.
    private let mapSpanDegrees = 2.4
    private let mapCenter = "48.30,-123.20"

    /// One favorite, not `ShotWalk`'s two. A phone fits four cards above the
    /// FAB row, and the frame is about the three groups being on screen
    /// together — a second favorite pushes the Near Me header under the FABs.
    override func setUp() {
        super.setUp()
        seededFavorites = "noaa/9444900"
    }

    func testAppStoreShots() throws {
        try skipUnlessShooting()
        // Every accepted size is a portrait pixel count, and a simulator keeps
        // whatever orientation the last run left it in.
        XCUIDevice.shared.orientation = .portrait

        currentsOnSlack()
        tideMidRise()
        scrubbedUnderTheMoon()
        nearbyWithFavorites()
        mapAtRegionalScale()
    }

    // MARK: - 1. Currents centered on slack

    private func currentsOnSlack() {
        // Two launches: the first only to read the schedule. `-scrubInstant`
        // is a launch argument, so the instant has to be known before the app
        // starts, and the slack the frame is about is the station's own — a
        // time written down here would go on producing a frame after the
        // harmonics moved under it, just not a slack one.
        var app = launchShots(scrubTo: "12:00")
        openDeceptionPass(app)
        let slack = scheduleTimes(app, naming: "SLACK").daytime

        app = launchShots(scrubTo: slack)
        openDeceptionPass(app)
        assertCurrentDetailRendered(app)
        settleScrub(app, at: clock12(slack))
        XCTAssert(leadReading(app).label.localizedCaseInsensitiveContains("slack"),
                  "the currents frame is not on slack: \(leadReading(app).label)")
        save(app, "01-currents-slack.png")
    }

    // MARK: - 2. A genuinely varied tide

    private func tideMidRise() {
        // Seattle on a full moon: a mixed tide at its spring range, with the
        // diurnal inequality that makes one of the day's two highs plainly
        // taller than the other.
        var app = launchShots(scrubTo: "12:00")
        openStation(app, search: "seattle", named: "Seattle")
        let high = scheduleTimes(app, naming: "HIGH").daytime
        // A quarter cycle before the high is where a semidiurnal tide runs
        // fastest, so the frame carries the movement chevrons and a rate of
        // rise rather than a turn's flat water.
        let rising = high.hoursEarlier(3)

        app = launchShots(scrubTo: rising)
        openStation(app, search: "seattle", named: "Seattle")
        settleScrub(app, at: clock12(rising))
        XCTAssert(commentaryPill(app).label.hasPrefix("Rising"),
                  "the tide frame should be mid-rise, not \(commentaryPill(app).label)")
        save(app, "02-tide-rising.png")
    }

    // MARK: - 3. The scrubber, parked away from now

    private func scrubbedUnderTheMoon() {
        // Parked at night, which is the frame's whole point twice over: the
        // sky behind the strip is dark with the full moon in it, and the
        // centerline is hours off `now`, so the return-to-now pill is on
        // screen saying this is a timeline you move rather than a table you
        // read. Parked by launch argument rather than by a synthesised drag —
        // the strip's magnet pulls a released drag onto the nearest stop, and
        // which stop that is depends on the device's strip width.
        let app = launchShots(scrubTo: "23:30")
        openFridayHarbor(app)
        settleScrub(app, at: "11:30pm")
        XCTAssert(app.buttons["Return to now"].appears(within: 5),
                  "the centerline is not parked off now")
        save(app, "03-scrubber.png")
    }

    // MARK: - 4. Nearby list with Favorites

    private func nearbyWithFavorites() {
        let app = launchShots()
        XCTAssert(app.staticTexts["MY LOCATION"].appears(within: 10))
        XCTAssert(app.staticTexts["FAVORITES"].appears(within: 10),
                  "the seeded favorites never grouped")
        XCTAssert(app.staticTexts["NEAR ME"].appears(within: 10))
        settleLayout(app.staticTexts["NEAR ME"].firstMatch)
        save(app, "04-nearby.png")
    }

    // MARK: - 5. The map

    private func mapAtRegionalScale() {
        // The camera is set at launch and the pane's width is not the
        // window's — iPad puts the map in the split's detail column — so the
        // zoom that frames `mapSpanDegrees` is measured on THIS device and
        // the map relaunched with it. Without that, one written-down zoom
        // frames the coast on the phone and half the Pacific on the iPad.
        var app = launchShots(["-openMap", "-mapCenter", mapCenter])
        let canvas = app.otherElements["map-canvas"].firstMatch
        XCTAssert(canvas.appears(within: 10))
        let paneWidth = settled { canvas.frame.width }
        // MapLibre's world is 512 points across at zoom 0 (the same constant
        // `tapPin` works in).
        let zoom = log2(paneWidth * 360 / mapSpanDegrees / 512)

        app = launchShots(["-openMap", "-mapCenter", mapCenter,
                           "-mapZoom", String(format: "%.3f", zoom)])
        XCTAssert(app.otherElements["map-canvas"].firstMatch.appears(within: 10))
        XCTAssert(waitFor(app.staticTexts["map-settles"].firstMatch, "label != '0'"),
                  "map never settled")
        sleep(5)  // tiles never reach the accessibility tree
        save(app, "05-map.png")
    }

    // MARK: - Helpers

    private func openDeceptionPass(_ app: XCUIApplication) {
        openStation(app, search: "deception", named: "Deception Pass (Narrows)")
    }

    private func openStation(_ app: XCUIApplication, search: String, named: String) {
        openSearch(app, search)
        pickSearchResult(app, app.staticTexts[named].firstMatch)
        XCTAssert(leadReading(app).appears(within: 10), "\(named) detail did not render")
    }

    /// Every time on today's schedule whose row names `stop` — "SLACK",
    /// "HIGH" — as 24-hour "HH:mm". Today's group is the only one expanded on
    /// arrival, so these are today's rows and no scrolling is needed to reach
    /// them: the labels are in the tree whether or not the rows are on screen.
    private func scheduleTimes(_ app: XCUIApplication, naming stop: String) -> [String] {
        let times = scheduleRowLabels(app)
            .filter { $0.localizedCaseInsensitiveContains(stop) }
            .compactMap { label -> String? in
                label.range(of: #"\d{1,2}:\d{2}(am|pm)"#, options: .regularExpression)
                    .map { String(label[$0]).clock24 }
            }
        XCTAssertFalse(times.isEmpty, "no \(stop) row on today's schedule")
        return times
    }

    /// "13:22" → "1:22pm", the form the lead reading prints.
    private func clock12(_ time: String) -> String {
        let (h, m) = time.hourMinute
        return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m))\(h < 12 ? "am" : "pm")"
    }

}

private extension String {
    /// "1:22pm" → "13:22".
    var clock24: String {
        let bare = String(dropLast(2))
        let parts = bare.split(separator: ":")
        var hour = Int(parts[0]) ?? 0
        if hasSuffix("pm"), hour != 12 { hour += 12 }
        if hasSuffix("am"), hour == 12 { hour = 0 }
        return String(format: "%02d:%@", hour, String(parts[1]))
    }

    /// "13:22" → (13, 22).
    var hourMinute: (Int, Int) {
        let parts = split(separator: ":")
        return (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
    }

    /// "13:22" → "10:22". Same calendar day by construction — every caller
    /// steps back from an afternoon stop.
    func hoursEarlier(_ hours: Int) -> String {
        let (h, m) = hourMinute
        return String(format: "%02d:%02d", max(h - hours, 0), m)
    }
}

private extension Array where Element == String {
    /// The first stop at or after 11:00, else the last of the day — a frame
    /// wants a stop in daylight, and every station these walks open has one.
    var daytime: String { first { $0 >= "11:00" } ?? last! }
}
