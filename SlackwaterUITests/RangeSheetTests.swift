import XCTest

/// The Range tile's sheet (detail.md §6.4) and the cases the unit tests cannot
/// reach: that the tile is a button at an ordinary station at all, that each
/// section is present or absent on the right station, and that a tapped fact
/// moves the scrubber.
///
/// Three defects in this feature passed every unit test and were only ever
/// visible on screen — levels drawn as hairlines with no labels, a figure
/// clipped by its card, and a partial day drawn as a bar collapsed to nothing.
/// These cannot see a drawing either, but they pin the structure around it.
final class RangeSheetTests: ScreenshotTestCase {
    /// §6.4 cases 16 and 18. Friday Harbor is an ordinary NOAA station with
    /// bounds, so all three sections apply; before this feature its Range tile
    /// was inert.
    func testTheRangeTileOpensASheetWithAllThreeSections() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        // Case-insensitive, as the other tile assertions in this target are:
        // the eyebrow combines an uppercasing MonoLabel with an accessibility
        // label that does not.
        let tile = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] 'range'")).firstMatch
        XCTAssert(tile.appears(within: 10), "no Range tile on the tide detail")
        tile.tap()

        XCTAssert(app.navigationBars["Range"].appears(within: 5),
                  "the Range tile did not open its sheet — it is inert again")
        for id in ["range-section-swings", "range-section-ends", "range-section-year"] {
            XCTAssert(app.descendants(matching: .any)[id].appears(within: 10),
                      "\(id) missing from the Range sheet")
        }
        save(app, "range-sheet-sections.png")
    }

    /// §6.4 case 17. Ten bundled stations have no astronomical bounds, because
    /// the database withholds LAT and HAT where Sa and Ssa are both zero — the
    /// same state every CHS fit is in, and the reason CHS cannot be reached
    /// offline in this target. The two absolute sections must be ABSENT, not
    /// empty and not zeroed.
    func testAStationWithoutBoundsShowsTheFortnightSectionAlone() throws {
        let app = launch("-seedGate")
        // Chignik rather than the nearer Winterport: Winterport also has a
        // current station on the Penobscot, and the bare name matches that row
        // first, opening a page with a Next max tile and no Range tile at all.
        // No current station shares Chignik's name.
        openSearch(app, "chignik")
        pickSearchResult(app, app.staticTexts["Chignik"].firstMatch)
        XCTAssert(leadReading(app).appears(within: 10), "Chignik detail did not render")

        let tile = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] 'range'")).firstMatch
        XCTAssert(tile.appears(within: 10), "no Range tile at Chignik")
        tile.tap()
        XCTAssert(app.navigationBars["Range"].appears(within: 5), "the sheet did not open")

        XCTAssert(app.descendants(matching: .any)["range-section-swings"].appears(within: 10),
                  "the fortnight section works everywhere and must still be here")
        XCTAssertFalse(app.descendants(matching: .any)["range-section-ends"].exists,
                       "a station with no bounds must not claim a floor or a ceiling")
        XCTAssertFalse(app.descendants(matching: .any)["range-section-year"].exists,
                       "a station with no annual constituent must not claim a season")
        save(app, "range-sheet-no-bounds.png")
    }

    /// §6.4 case 20. A superlative you cannot go and look at is trivia, so the
    /// caption that names the next bigger swing moves the scrubber to it and
    /// closes the sheet — the same contract the Moon sheet's facts keep.
    func testTappingTheNextBiggerSwingMovesTheScrubber() throws {
        let app = launch("-seedGate")
        openFridayHarbor(app)
        let lead = leadReading(app)
        XCTAssert(lead.appears(within: 10), "no lead reading")
        let before = lead.label

        let tile = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] 'range'")).firstMatch
        XCTAssert(tile.appears(within: 10), "no Range tile")
        tile.tap()
        XCTAssert(app.navigationBars["Range"].appears(within: 5), "the sheet did not open")

        let jump = app.descendants(matching: .any)["range-jump"].firstMatch
        // Absent by design when this swing is the fortnight's biggest: there is
        // nothing ahead to go to. Skip rather than fail — which swing the
        // fixture clock lands on is not this test's subject.
        try XCTSkipUnless(jump.appears(within: 10),
                          "this swing leads its fortnight, so there is no next bigger one")
        jump.tap()

        XCTAssertFalse(app.navigationBars["Range"].waitForExistence(timeout: 2),
                       "tapping a fact should close the sheet")
        XCTAssert(lead.appears(within: 10), "the detail did not come back")
        XCTAssertNotEqual(lead.label, before, "the scrubber did not move to the tapped swing")
        save(app, "range-sheet-jumped.png")
    }
}
