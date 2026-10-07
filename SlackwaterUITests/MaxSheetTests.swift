import XCTest

/// The Next max tile's sheet (detail.md §6.2, §6.5), and the structural claims
/// the unit tests cannot reach: that the tile is a button at a harmonic current
/// station, which sections the sheet has, and that an online gate's stays inert.
final class MaxSheetTests: ScreenshotTestCase {
    private func nextMaxTile(_ app: XCUIApplication) -> XCUIElement {
        // Case-insensitive, like the other tile queries in this target: the
        // eyebrow combines an uppercasing MonoLabel with an accessibility
        // label that does not.
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] 'next max'")).firstMatch
    }

    /// §6.5. Deception Pass is a harmonic reference with its own constituents,
    /// so it has a fortnight to rank against.
    func testTheNextMaxTileOpensASheetWithBothSections() throws {
        let app = launch("-seedGate")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 10), "current detail did not render")

        let tile = nextMaxTile(app)
        XCTAssert(tile.appears(within: 10), "no Next max tile")
        tile.tap()
        XCTAssert(app.navigationBars["Next max"].appears(within: 5),
                  "the Next max tile did not open its sheet — it is inert again")
        for id in ["max-section-peaks", "max-section-year"] {
            XCTAssert(app.descendants(matching: .any)[id].appears(within: 15), "\(id) missing")
        }
        // The one the Range sheet has and this one must not: there is no
        // published astronomical floor and ceiling for current speed.
        XCTAssertFalse(app.descendants(matching: .any)["range-section-ends"].exists,
                       "a current has no datums to measure against")
        save(app, "max-sheet-sections.png")
    }

    /// §6.2. The caption's time is the half a reader acts on, so it survives
    /// whether the maximum marks or not.
    func testTheCaptionAlwaysCarriesATime() throws {
        let app = launch("-seedGate")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 10))
        XCTAssert(nextMaxTile(app).appears(within: 10), "no Next max tile")
        // ReadoutTile nests two accessibility elements: the eyebrow, whose
        // label is just "Next max", and the whole tile, which combines the
        // label, the value and the caption. The caption only exists on the
        // second, so take the longest label rather than the first match.
        let labels = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'next max'"))
            .allElementsBoundByIndex.map(\.label)
        let combined = try XCTUnwrap(labels.max(by: { $0.count < $1.count }))
        // Case-insensitive: "Flood at 1:09 PM" capitalises the direction and
        // "Strong flood · 1:09 PM" does not, and both are correct.
        XCTAssertTrue(combined.localizedCaseInsensitiveContains("flood")
                      || combined.localizedCaseInsensitiveContains("ebb"),
                      "the caption lost its direction: '\(combined)'")
        XCTAssertTrue(combined.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil,
                      "the caption lost its time: '\(combined)'")
    }
}
