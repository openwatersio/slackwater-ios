// Slackwater — GPL v3. The watch list and Add Place, driven on a watch
// simulator (#521).
import XCTest

final class WatchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The two resets also keep the run off the real iCloud store
        // (FavoritesCloud.store); -locDenied keeps the location prompt from
        // landing on the list.
        app.launchArguments = ["-resetFavorites", "-resetRecents", "-locDenied"]
        app.launch()
    }

    func testNoLocationShowsTheLocationCardAndPlacesStill() {
        XCTAssertTrue(app.descendants(matching: .any)["location-card"].waitForExistence(timeout: 15),
                      app.debugDescription)
        XCTAssertTrue(app.buttons["place-row"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
    }

    func testTypedQueryShowsResults() {
        search("port angeles")
        XCTAssertTrue(app.buttons["search-result"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
    }

    func testQueryWithNoMatchesSaysSo() {
        search("zzqqxx")
        XCTAssertTrue(app.staticTexts["search-empty"].waitForExistence(timeout: 10),
                      app.debugDescription)
    }

    func testSwipesStarAndUnstarAPlace() {
        let first = app.buttons["place-row"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let name = first.label.components(separatedBy: ",").first ?? first.label

        first.swipeRight()
        tapButton("Favorite")
        let starred = app.buttons.matching(NSPredicate(
            format: "identifier == 'place-row' AND label BEGINSWITH %@ AND label CONTAINS 'Favorites'", name))
        XCTAssertTrue(starred.firstMatch.waitForExistence(timeout: 5), app.debugDescription)

        starred.firstMatch.swipeLeft()
        tapButton("Unfavorite")
        // It goes back to Near Me, which outranks Recents (the phone's ListGroups).
        let unstarred = NSPredicate(format: "count == 0")
        expectation(for: unstarred, evaluatedWith: starred)
        waitForExpectations(timeout: 5)
    }

    private func search(_ query: String) {
        let field = app.textFields["place-search-field"]
        let addPlace = app.buttons["add-place-row"]
        XCTAssertTrue(app.buttons["place-row"].firstMatch.waitForExistence(timeout: 15))
        // Add Place is the last row, below every card, and the list only
        // builds a row once it scrolls into view.
        for _ in 0..<10 where !(addPlace.exists && addPlace.isHittable) { app.swipeUp() }
        tap(addPlace, until: field)
        field.tap()
        app.typeText(query)
        // The watch's text input is a sheet; nothing reaches the field until Done.
        app.buttons["Done"].tap()
    }

    private func tapButton(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
    }

    /// Taps until `destination` appears. On the watch simulator a tap on a
    /// list row right after launch is sometimes dropped: the second tap
    /// navigates where the first did not, seen in about half of fresh runs.
    /// Whether a device drops it too is a device check (#549).
    private func tap(_ element: XCUIElement, until destination: XCUIElement) {
        for _ in 0..<3 where !destination.exists {
            element.tap()
            _ = destination.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(destination.exists, app.debugDescription)
    }
}
