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
        from.set(["a", "b"], forKey: "slackwater.favorites")
        from.set(["c"], forKey: "slackwater.recents")

        AppGroup.migrateIfNeeded(into: into, from: from)
        XCTAssertEqual(into.stringArray(forKey: "slackwater.favorites"), ["a", "b"])
        XCTAssertEqual(into.stringArray(forKey: "slackwater.recents"), ["c"])

        // A second run must not clobber post-migration edits.
        into.set(["z"], forKey: "slackwater.favorites")
        from.set(["stale"], forKey: "slackwater.favorites")
        AppGroup.migrateIfNeeded(into: into, from: from)
        XCTAssertEqual(into.stringArray(forKey: "slackwater.favorites"), ["z"])
    }

    func testChsModelsDirLivesInSharedContainer() {
        XCTAssert(ChsModelStore.dir.path.hasSuffix("ChsModels"))
        XCTAssertEqual(ChsModelStore.dir.deletingLastPathComponent().path,
                       AppGroup.container.path)
    }
}
