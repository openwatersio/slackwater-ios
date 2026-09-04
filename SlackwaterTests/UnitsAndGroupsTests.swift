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

    // MARK: - Station regions: one distance unit, compass points intact (M50)

    /// The bundled region lines are NOAA's own qualifiers, normalized by
    /// tools/enrich-currents.mjs. Two things must hold on every one of them.
    func testBundledRegionsAreNauticalAndShoutTheirCompassPoints() {
        let titleCased = try! NSRegularExpression(
            pattern: "\\b(Nne|Ene|Ese|Sse|Ssw|Wsw|Wnw|Nnw|Ne|Se|Sw|Nw)\\b")
        // A distance, not a proper noun: Deepwater Point sits on the Miles
        // River (a subordinate current station since #268).
        let statute = try! NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?\\s*(?:mi\\.|miles?)\\b",
                                               options: .caseInsensitive)
        let regions = StationItem.all.map(\.region)
        XCTAssertFalse(regions.isEmpty, "no bundled stations — did the resources ship?")
        for region in regions {
            let r = NSRange(region.startIndex..., in: region)
            XCTAssertNil(titleCased.firstMatch(in: region, range: r),
                         "compass abbreviation title-cased in \"\(region)\" (SSE, not Sse)")
            XCTAssertNil(statute.firstMatch(in: region, range: r),
                         "statute miles in \"\(region)\" — the distance pill speaks nm")
        }
    }

    /// The specific card Bryan found: "7.6 mi. Sse" is now "6.6 nm SSE".
    func testDiscoveryIslandSubtitleRendersFixed() {
        let regions = StationItem.all.filter { $0.name == "Discovery Island" }.map(\.region)
        // Three since #268: the subordinate current station 2.6 nm SSE joined.
        XCTAssertEqual(Set(regions), ["3.0 nm NE", "6.6 nm SSE", "2.6 nm SSE"])
    }

    // MARK: - One entry per place (M50 matching-station grouping)

    func testSameNamedStationsCollapseToTheNearest() {
        let ranked = StationItem.all.sorted {
            $0.km(fromLat: firstRunFix.lat, lon: firstRunFix.lon) <
            $1.km(fromLat: firstRunFix.lat, lon: firstRunFix.lon)
        }
        let places = StationGroups(ranked: ranked)
        let discovery = ranked.filter { $0.name == "Discovery Island" }
        XCTAssertEqual(discovery.count, 3, "the collision this exists for (three since #268)")
        let shown = places.collapse(discovery.map(\.id))
        XCTAssertEqual(shown, [discovery[0].id], "one entry per name, the nearest")
        XCTAssertEqual(places.shownIds, places.collapse(ranked.map(\.id)),
                       "the memoised list is the same collapse the per-render call made")
        XCTAssertEqual(places.shown(discovery[1].id), discovery[0].id)
        XCTAssertEqual(places.matches(discovery[0]).map(\.id), discovery.map(\.id),
                       "the chooser still offers both, nearest first")
    }

    /// A unique name is untouched — and gets no chooser (one option is noise).
    func testUniqueNameIsItsOwnEntry() {
        let ranked = StationItem.all
        let places = StationGroups(ranked: ranked)
        let friday = ranked.first { $0.id == TideStationRecord.fridayHarborID }!
        XCTAssertEqual(places.shown(friday.id), friday.id)
        XCTAssertEqual(places.matches(friday).count, 1)
    }

    /// Collapse keeps input order and drops the duplicates behind it — the
    /// Recents case (visit both Point Wilsons, see one row).
    func testCollapseKeepsOrderAndDedupes() {
        let ranked = StationItem.all.sorted {
            $0.km(fromLat: firstRunFix.lat, lon: firstRunFix.lon) <
            $1.km(fromLat: firstRunFix.lat, lon: firstRunFix.lon)
        }
        let places = StationGroups(ranked: ranked)
        let wilsons = ranked.filter { $0.name == "Point Wilson" }
        XCTAssertEqual(wilsons.count, 4)  // four since #268: PCT1496, 0.7 nm east
        let friday = TideStationRecord.fridayHarborID
        XCTAssertEqual(places.collapse([wilsons[2].id, friday, wilsons[0].id]),
                       [wilsons[0].id, friday])
    }

    /// Series and provider are what a chooser row says when the names match.
    func testKindLabelsDistinguishSeriesAndProvider() {
        let byId = Dictionary(StationItem.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byId[TideStationRecord.fridayHarborID]?.kindLabel, "Tide · NOAA")
        XCTAssertEqual(byId["current:noaa/PUG1744"]?.kindLabel, "Current · NOAA")
        XCTAssertEqual(byId["chs-victoria"]?.kindLabel, "Tide · CHS")
        XCTAssertEqual(byId["chs-active-pass"]?.kindLabel, "Current · CHS")
    }

    // MARK: - RecentsStore auto-select skip (M52 handshake, #3)

    /// The skip is scoped to the station auto-select opened. An unfitted CHS
    /// station's waiting view records nothing, so a bare flag would survive it
    /// and silently drop the next station the user genuinely opens (#3).
    @MainActor
    func testAutoSelectSkipDoesNotLeakToNextStation() {
        let store = RecentsStore.shared
        let auto = "auto-\(UUID().uuidString)"
        let opened = "opened-\(UUID().uuidString)"
        // Auto-select lands on an unfitted CHS station: skip armed, nothing
        // ever recorded for it. The user then opens another station.
        store.skipNextRecordID = auto
        store.record(opened)
        XCTAssertTrue(store.ids.contains(opened),
                      "a genuinely opened station must not be eaten by a stale auto-select skip")
        XCTAssertNil(store.skipNextRecordID, "any record attempt disarms the skip")
        // The normal handshake still holds: the auto-opened detail itself is
        // skipped once, then counts as viewed on a real revisit.
        store.skipNextRecordID = auto
        store.record(auto)
        XCTAssertFalse(store.ids.contains(auto), "the auto-opened detail is not the user viewing a station")
        store.record(auto)
        XCTAssertTrue(store.ids.contains(auto), "a later genuine open must record")
        store.remove(opened)
        store.remove(auto)
    }

    // MARK: - FavoritesStore round trip (ends clean — App Group defaults)

    @MainActor
    func testFavoriteToggleRoundTrip() {
        let store = FavoritesStore.shared
        let id = "test-station-\(UUID().uuidString)"
        XCTAssertFalse(store.contains(id))
        store.toggle(id)
        XCTAssertTrue(store.contains(id), "toggle must add a new favorite")
        XCTAssertEqual(AppGroup.defaults.stringArray(forKey: AppGroup.favoritesKey)?.contains(id), true)
        store.toggle(id)
        XCTAssertFalse(store.contains(id), "second toggle must remove it")
        // Spec §9: unfavoriting re-files to Recents.
        XCTAssertTrue(RecentsStore.shared.ids.contains(id))
        RecentsStore.shared.remove(id)
        XCTAssertFalse(RecentsStore.shared.ids.contains(id), "remove must clear the recent")
    }
}
