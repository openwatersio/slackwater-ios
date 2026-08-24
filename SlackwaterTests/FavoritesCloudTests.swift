// Slackwater — GPL v3. Favourites cross devices (#134): one iCloud KVS key per
// starred station.
//
// The upgrade is the dangerous part. A user with six starred gates and no cloud
// copy yet meets an *empty* KVS on first launch after the update; adopt that
// and their list is gone, silently, with no undo. So the seed path is what
// these tests pin — plus the ordering that replaces today's per-device
// insertion order, and the guarantee that a test run never touches the real
// store.
import XCTest
@testable import Slackwater

final class FavoritesCloudTests: XCTestCase {

    // MARK: - The upgrade

    /// Nothing in the cloud yet: every local star survives, in its local order.
    func testUpgradeFromAnEmptyCloudKeepsEveryStarInOrder() {
        let local = ["dodd", "porlier", "gabriola"]
        let seed = FavoritesCloud.seed(local: local, cloud: [:], now: 1_000)
        XCTAssertEqual(seed.count, 3, "an empty cloud must not swallow a star")
        XCTAssertEqual(FavoritesCloud.order(seed), local)
    }

    /// The second device to upgrade. It has its own stars *and* sees the first
    /// device's: the union survives, the shared one keeps the older stamp
    /// (re-stamping would drag it to the end of both devices' lists), and the
    /// newcomers land after what was already there.
    func testSecondDeviceUpgradeUnionsRatherThanOverwrites() {
        let cloud = ["dodd": 10.0, "porlier": 20.0]
        let seed = FavoritesCloud.seed(local: ["porlier", "active"], cloud: cloud, now: 5)
        XCTAssertEqual(Array(seed.keys), ["active"], "an id the cloud already has must not be re-stamped")
        XCTAssertGreaterThan(seed["active"]!, 20.0, "a stamp older than the cloud's would interleave")

        let merged = cloud.merging(seed) { mine, _ in mine }
        XCTAssertEqual(FavoritesCloud.order(merged), ["dodd", "porlier", "active"])
    }

    /// `now` in the past — a device with a wrong clock, or a restored backup —
    /// still appends rather than interleaving.
    func testSeedNeverLandsBeforeTheCloudsNewestStar() {
        let seed = FavoritesCloud.seed(local: ["a"], cloud: ["b": 9_000], now: 1)
        XCTAssertGreaterThan(seed["a"]!, 9_000)
    }

    // MARK: - Reconcile (what `adopt` actually calls)

    /// The upgrade, end to end: an existing user's six gates meet an empty
    /// cloud and every one of them survives *and* gets written out.
    func testReconcileOnFirstRunSeedsTheCloudAndKeepsTheList() {
        let local = ["dodd", "porlier", "gabriola"]
        let (ids, writes) = FavoritesCloud.reconcile(local: local, cloud: [:],
                                                     migrated: false, now: 100)
        XCTAssertEqual(ids, local)
        XCTAssertEqual(Set(writes.keys), Set(local), "every star must reach the cloud")
    }

    /// A migrated device takes the cloud as the list and owes it nothing —
    /// including the star another device added while this one was closed.
    func testReconcileAfterMigrationAdoptsTheCloud() {
        let (ids, writes) = FavoritesCloud.reconcile(
            local: ["dodd"], cloud: ["dodd": 1, "porlier": 2], migrated: true, now: 100)
        XCTAssertEqual(ids, ["dodd", "porlier"])
        XCTAssertTrue(writes.isEmpty)
    }

    /// The other half of the same rule: once migrated, a key the other device
    /// removed leaves this device's list. An unstar has no other way to cross.
    func testReconcileAfterMigrationHonoursARemoteUnstar() {
        let (ids, _) = FavoritesCloud.reconcile(
            local: ["dodd", "porlier"], cloud: ["dodd": 1], migrated: true, now: 100)
        XCTAssertEqual(ids, ["dodd"])
    }

    // MARK: - Order

    func testOrderIsOldestStarFirstAndStableOnTies() {
        XCTAssertEqual(FavoritesCloud.order(["b": 2, "a": 1, "c": 3]), ["a", "b", "c"])
        // Equal stamps are reachable (a seeded upgrade, a restored backup); an
        // unstable sort would reshuffle the list on every launch.
        XCTAssertEqual(FavoritesCloud.order(["b": 1, "a": 1, "c": 1]), ["a", "b", "c"])
    }

    /// An unstar on another device arrives as a *missing key*, which is the
    /// whole reason the list is read back from the cloud's key set.
    func testARemovedKeyLeavesTheList() {
        var stamps = ["dodd": 1.0, "porlier": 2.0]
        stamps["dodd"] = nil
        XCTAssertEqual(FavoritesCloud.order(stamps), ["porlier"])
    }

    // MARK: - Reading the store

    func testStampsReadsOnlyFavouriteKeys() {
        let raw: [String: Any] = [
            FavoritesCloud.prefix + "dodd": NSNumber(value: 12.5),
            "slackwater.premium": NSNumber(value: true),
            "unrelated": "whatever",
        ]
        XCTAssertEqual(FavoritesCloud.stamps(raw), ["dodd": 12.5])
    }

    /// A key of the right shape holding the wrong type (a hand-edited store, a
    /// future format) is skipped, not force-unwrapped into a crash.
    func testStampsSkipsNonNumericValues() {
        XCTAssertEqual(FavoritesCloud.stamps([FavoritesCloud.prefix + "dodd": "soon"]), [:])
    }

    // MARK: - Tests never touch iCloud

    /// The `-resetFavorites` / `-seedFavorites` hooks and this test host share
    /// one guarantee: no real KVS. The simulator's store outlives the run, so
    /// one seeded test would leak its stars into the next launch that expects
    /// a clean device.
    func testTheStoreIsUnavailableUnderTest() {
        XCTAssertNil(FavoritesCloud.store)
    }
}
