// Slackwater — GPL v3. Speed-unit formatting (web units.ts parity) and the
// list dedupe rule (My Location > Favorites > Near Me > Recents), plus the
// FavoritesStore round trip behind the detail star and list swipes.
import XCTest
@testable import Slackwater

final class UnitsAndGroupsTests: XCTestCase {
    // MARK: - formatSpeed mirrors web units.ts (kn | kmh | ms, one decimal)

    func testFormatSpeedUnits() {
        XCTAssertEqual(formatSpeed(6.0, unit: "kn"), "6.0")
        XCTAssertEqual(formatSpeed(6.0, unit: "kmh"), "11.1")   // 6 × 1.852
        XCTAssertEqual(formatSpeed(6.0, unit: "ms"), "3.1")     // 6 × 0.514444
        // Near-zero negatives lose their sign (web unsign), post-conversion.
        XCTAssertEqual(formatSpeed(-0.02, unit: "kn"), "0.0")
        XCTAssertEqual(formatSpeed(-0.02, unit: "kmh"), "0.0")
        // An unknown value falls back to knots, like the web's default.
        XCTAssertEqual(formatSpeed(2.5, unit: "furlongs"), "2.5")
    }

    func testSpeedUnitLabels() {
        XCTAssertEqual(speedUnitLabel("kn"), "kn")
        XCTAssertEqual(speedUnitLabel("kmh"), "km/h")
        XCTAssertEqual(speedUnitLabel("ms"), "m/s")
    }

    /// The switch changes what a current card renders: same knots in, a
    /// different readout string per setting.
    func testSpeedUnitSwitchChangesReadout() {
        let knots = 3.4
        let kn = "\(formatSpeed(knots, unit: "kn")) \(speedUnitLabel("kn"))"
        let kmh = "\(formatSpeed(knots, unit: "kmh")) \(speedUnitLabel("kmh"))"
        XCTAssertEqual(kn, "3.4 kn")
        XCTAssertEqual(kmh, "6.3 km/h")
        XCTAssertNotEqual(kn, kmh)
    }

    // MARK: - Dedupe rule: each station renders in at most one group
    // (M4.5 precedence: My Location > Favorites > Near Me > Recents)

    func testHeroExcludedAndNearbyRecentShowsUnderNearMe() {
        let g = ListGroups(heroId: "a", favoriteIds: [], recentIds: ["a", "b"],
                           rankedIds: ["a", "b", "c", "d"], nearCount: 4)
        XCTAssertFalse(g.nearMe.contains("a"), "hero must not repeat in Near Me")
        XCTAssertEqual(g.nearMe, ["b", "c", "d"])
        XCTAssertEqual(g.recents, [],
                       "a station both nearby and recent shows under Near Me only")
    }

    func testFavoritesExcludedFromNearMeAndRecents() {
        let g = ListGroups(heroId: nil, favoriteIds: ["b"], recentIds: ["b", "c", "z"],
                           rankedIds: ["a", "b", "c", "d", "e"], nearCount: 3)
        XCTAssertEqual(g.favorites, ["b"])
        XCTAssertEqual(g.nearMe, ["a", "c", "d"], "Near Me backfills past excluded ids")
        XCTAssertEqual(g.recents, ["z"], "Recents holds only stations not shown above")
    }

    /// Exclusion is render-time only: drop the hero/favorite (or fall past the
    /// Near Me cut) and the persisted recent surfaces again.
    func testExclusionIsRenderTimeOnly() {
        let hidden = ListGroups(heroId: "a", favoriteIds: ["b"], recentIds: ["a", "b"],
                                rankedIds: ["a", "b"], nearCount: 2)
        XCTAssertEqual(hidden.recents, [])
        let restored = ListGroups(heroId: nil, favoriteIds: [], recentIds: ["a", "b"],
                                  rankedIds: ["a", "b", "c"], nearCount: 1)
        XCTAssertEqual(restored.nearMe, ["a"])
        XCTAssertEqual(restored.recents, ["b"],
                       "a recent past the Near Me cut surfaces in Recents")
    }

    // MARK: - FavoritesStore round trip (ends clean — shared UserDefaults)

    @MainActor
    func testFavoriteToggleRoundTrip() {
        let store = FavoritesStore.shared
        let id = "test-station-\(UUID().uuidString)"
        XCTAssertFalse(store.contains(id))
        store.toggle(id)
        XCTAssertTrue(store.contains(id), "toggle must add a new favorite")
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "slackwater.favorites")?.contains(id), true)
        store.toggle(id)
        XCTAssertFalse(store.contains(id), "second toggle must remove it")
        // Spec §9: unfavoriting re-files to Recents.
        XCTAssertTrue(RecentsStore.shared.ids.contains(id))
        RecentsStore.shared.remove(id)
        XCTAssertFalse(RecentsStore.shared.ids.contains(id), "remove must clear the recent")
    }
}
