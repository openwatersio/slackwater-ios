// Slackwater — GPL v3. App Group migration: standard-defaults state moves to
// the shared suite exactly once; the shared container hosts ChsModels.
import XCTest
@testable import Slackwater

final class AppGroupTests: XCTestCase {
    func testMigrationCopiesOnce() {
        let from = UserDefaults(suiteName: "test.from")!
        let into = UserDefaults(suiteName: "test.into")!
        defer {
            from.removePersistentDomain(forName: "test.from")
            into.removePersistentDomain(forName: "test.into")
        }
        from.set(["a", "b"], forKey: AppGroup.favoritesKey)
        from.set(["c"], forKey: AppGroup.recentsKey)

        AppGroup.migrateIfNeeded(into: into, from: from)
        XCTAssertEqual(into.stringArray(forKey: AppGroup.favoritesKey), ["a", "b"])
        XCTAssertEqual(into.stringArray(forKey: AppGroup.recentsKey), ["c"])

        // A second run must not clobber post-migration edits.
        into.set(["z"], forKey: AppGroup.favoritesKey)
        from.set(["stale"], forKey: AppGroup.favoritesKey)
        AppGroup.migrateIfNeeded(into: into, from: from)
        XCTAssertEqual(into.stringArray(forKey: AppGroup.favoritesKey), ["z"])
    }

    /// H2(2): the units settings migrate too, and they're plain strings, not
    /// arrays — `stringArray(forKey:)` would silently drop them.
    func testMigrationCopiesUnitsSettings() {
        let from = UserDefaults(suiteName: "test.units.from")!
        let into = UserDefaults(suiteName: "test.units.into")!
        defer {
            from.removePersistentDomain(forName: "test.units.from")
            into.removePersistentDomain(forName: "test.units.into")
        }
        from.set("metric", forKey: unitsKey)
        from.set("kmh", forKey: speedUnitKey)

        AppGroup.migrateIfNeeded(into: into, from: from)
        XCTAssertEqual(into.string(forKey: unitsKey), "metric")
        XCTAssertEqual(into.string(forKey: speedUnitKey), "kmh")
    }

    func testChsModelsDirLivesInSharedContainer() {
        XCTAssert(ChsModelStore.dir.path.hasSuffix("ChsModels"))
        XCTAssertEqual(ChsModelStore.dir.deletingLastPathComponent().path,
                       AppGroup.container.path)
    }

    /// B2: `AppGroup.defaults` used to migrate as a side effect of the FIRST
    /// touch from EITHER process — and the widget extension has its own,
    /// always-empty `.standard` (a different bundle id's sandbox), so a
    /// widget that ran before the app ever had migrated would flag migration
    /// "done" against nothing, permanently burning the real copy. Fixed by
    /// dropping the side effect from `defaults` entirely: only
    /// `SlackwaterApp.init()` calls `migrateIfNeeded`, explicitly, with the
    /// app's real `.standard`.
    ///
    /// "Widget ran first" is simulated by touching the shared suite with no
    /// migration call at all — the fixed `defaults` accessor performs none —
    /// so the migrated flag must still be unset when the app's real call
    /// arrives later.
    func testAppexTouchingSharedSuiteFirstDoesNotBurnMigration() {
        let shared = UserDefaults(suiteName: "test.appexFirst.shared")!
        let standard = UserDefaults(suiteName: "test.appexFirst.standard")!
        defer {
            shared.removePersistentDomain(forName: "test.appexFirst.shared")
            standard.removePersistentDomain(forName: "test.appexFirst.standard")
        }
        // The app's real pre-widget history — what a genuine migration must
        // preserve.
        standard.set(["a", "b"], forKey: AppGroup.favoritesKey)
        standard.set(["c"], forKey: AppGroup.recentsKey)

        // "Widget ran first": ordinary reads of the shared suite, the kind a
        // timeline build or a StationConfigIntent choice list does — no
        // `migrateIfNeeded` call anywhere near it, because nothing in the
        // fixed `AppGroup.defaults` accessor makes one.
        _ = shared.stringArray(forKey: AppGroup.favoritesKey)
        _ = shared.bool(forKey: AppGroup.premiumKey)

        // The app runs later and migrates explicitly — it must still see the
        // real standard-defaults content, not an already-flagged no-op.
        AppGroup.migrateIfNeeded(into: shared, from: standard)
        XCTAssertEqual(shared.stringArray(forKey: AppGroup.favoritesKey), ["a", "b"])
        XCTAssertEqual(shared.stringArray(forKey: AppGroup.recentsKey), ["c"])
    }
}
