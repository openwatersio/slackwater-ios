import XCTest
@testable import Slackwater

@MainActor final class UnitsCloudTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var cloud: MemoryUnitsCloud!
    private var reloads = 0

    override func setUp() async throws {
        try await super.setUp()
        suite = "UnitsCloudTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        cloud = MemoryUnitsCloud()
        reloads = 0
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func sync() -> UnitsCloud {
        UnitsCloud(defaults: defaults, cloud: cloud, reload: { self.reloads += 1 })
    }

    func testExistingCloudPreferencesWinAtLaunch() {
        defaults.set("imperial", forKey: unitsKey)
        defaults.set("kn", forKey: speedUnitKey)
        cloud.values = [unitsKey: "metric", speedUnitKey: "ms"]
        let sync = sync()
        withExtendedLifetime(sync) {
            XCTAssertEqual(defaults.string(forKey: unitsKey), "metric")
            XCTAssertEqual(defaults.string(forKey: speedUnitKey), "ms")
            XCTAssertTrue(cloud.writes.isEmpty)
            XCTAssertEqual(reloads, 1)
        }
    }

    func testOnlySavedValidPreferencesSeedMissingCloudKeys() {
        defaults.set("metric", forKey: unitsKey)
        defaults.set("unsupported", forKey: speedUnitKey)
        let sync = sync()
        XCTAssertTrue(cloud.writes.isEmpty, "an empty launch cache is not evidence of an empty cloud")
        expectation(for: NSPredicate { [cloud] _, _ in
            cloud?.values[unitsKey] as? String == "metric"
        }, evaluatedWith: nil)
        cloud.notify(NSUbiquitousKeyValueStoreServerChange)
        waitForExpectations(timeout: 3)
        withExtendedLifetime(sync) {
            XCTAssertEqual(cloud.writes, [unitsKey: "metric"])
            XCTAssertEqual(reloads, 0)
        }
    }

    func testFreshInstallDoesNotUploadDefaults() {
        XCTAssertEqual(heightUnits(defaults: defaults, locale: Locale(identifier: "en_FR")), "metric")
        let sync = sync()
        withExtendedLifetime(sync) {
            XCTAssertTrue(cloud.writes.isEmpty)
            XCTAssertNil(defaults.object(forKey: unitsKey))
            XCTAssertNil(defaults.object(forKey: speedUnitKey))
        }
    }

    func testLaunchWaitsForCloudAndRechecksValuesBeforeSeeding() {
        defaults.set("metric", forKey: unitsKey)
        defaults.set("kmh", forKey: speedUnitKey)
        let sync = sync()
        XCTAssertTrue(cloud.writes.isEmpty)

        cloud.notify(NSUbiquitousKeyValueStoreInitialSyncChange)
        XCTAssertTrue(cloud.writes.isEmpty)
        cloud.values[unitsKey] = "imperial"
        expectation(for: NSPredicate { [cloud] _, _ in
            cloud?.values[speedUnitKey] as? String == "kmh"
        }, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
        withExtendedLifetime(sync) {
            XCTAssertEqual(defaults.string(forKey: unitsKey), "imperial")
            XCTAssertEqual(cloud.values[unitsKey] as? String, "imperial")
            XCTAssertEqual(cloud.writes, [speedUnitKey: "kmh"])
        }
    }

    func testDeferredSeedRetriesMissingKeysWithoutOverwritingDownloadedValues() {
        defaults.set("imperial", forKey: unitsKey)
        defaults.set("kmh", forKey: speedUnitKey)
        cloud.deferWrites = true
        let sync = sync()
        sync.set("ms", forKey: speedUnitKey)
        cloud.values = [unitsKey: "metric"]
        cloud.deferWrites = false
        expectation(for: NSPredicate { [cloud] _, _ in
            cloud?.values[speedUnitKey] as? String == "ms"
        }, evaluatedWith: nil)
        cloud.notify(NSUbiquitousKeyValueStoreInitialSyncChange)
        waitForExpectations(timeout: 3)
        withExtendedLifetime(sync) {
            XCTAssertEqual(defaults.string(forKey: unitsKey), "metric")
            XCTAssertEqual(cloud.values[unitsKey] as? String, "metric")
            XCTAssertEqual(cloud.writes, [speedUnitKey: "ms"])
        }
    }

    func testLocalEditsWriteOnlyTheSelectedKeyAndReloadWidgets() {
        let sync = sync()
        sync.set("metric", forKey: unitsKey)
        sync.set("kmh", forKey: speedUnitKey)
        XCTAssertEqual(defaults.string(forKey: unitsKey), "metric")
        XCTAssertEqual(defaults.string(forKey: speedUnitKey), "kmh")
        XCTAssertEqual(cloud.writes, [unitsKey: "metric", speedUnitKey: "kmh"])
        XCTAssertEqual(reloads, 2)
        sync.set("kmh", forKey: speedUnitKey)
        sync.set("mph", forKey: speedUnitKey)
        sync.set("metric", forKey: "unrelated")
        XCTAssertEqual(cloud.writeCount, 2)
        XCTAssertEqual(reloads, 2)
        XCTAssertNil(defaults.object(forKey: "unrelated"))
    }

    func testIncomingChangesUpdateLocalPreferencesWithoutEchoing() {
        let sync = sync()
        cloud.values = [unitsKey: "metric", speedUnitKey: "ms"]
        cloud.notify(NSUbiquitousKeyValueStoreInitialSyncChange)
        withExtendedLifetime(sync) {
            XCTAssertEqual(defaults.string(forKey: unitsKey), "metric")
            XCTAssertEqual(defaults.string(forKey: speedUnitKey), "ms")
            XCTAssertTrue(cloud.writes.isEmpty)
            XCTAssertEqual(reloads, 1)
            cloud.notify(NSUbiquitousKeyValueStoreServerChange)
            XCTAssertEqual(reloads, 1)
        }
    }

    func testMissingAndInvalidCloudValuesPreserveLocalPreferences() {
        defaults.set("metric", forKey: unitsKey)
        defaults.set("kmh", forKey: speedUnitKey)
        cloud.values = [unitsKey: 42, speedUnitKey: "mph"]
        let sync = sync()
        withExtendedLifetime(sync) {
            XCTAssertEqual(defaults.string(forKey: unitsKey), "metric")
            XCTAssertEqual(defaults.string(forKey: speedUnitKey), "kmh")
            XCTAssertTrue(cloud.writes.isEmpty)
            cloud.values = [:]
            cloud.notify(NSUbiquitousKeyValueStoreAccountChange)
            XCTAssertEqual(defaults.string(forKey: unitsKey), "metric")
            XCTAssertEqual(defaults.string(forKey: speedUnitKey), "kmh")
            XCTAssertTrue(cloud.writes.isEmpty)
            XCTAssertEqual(reloads, 0)
        }
    }

    func testQuotaNotificationDoesNotReconcilePreferences() {
        let sync = sync()
        cloud.values = [unitsKey: "metric"]
        cloud.notify(NSUbiquitousKeyValueStoreQuotaViolationChange)
        withExtendedLifetime(sync) {
            XCTAssertNil(defaults.object(forKey: unitsKey))
            XCTAssertEqual(reloads, 0)
        }
    }

    func testComfortCurrentSyncsOnlyInRangeNumbers() {
        let key = AppGroup.slackWindowSpeedKey
        let sync = sync()
        sync.set(1.2, forKey: key)
        sync.set(42.0, forKey: key)
        sync.set("1.2", forKey: key)
        XCTAssertEqual(cloud.values[key] as? Double, 1.2)
        XCTAssertEqual(cloud.writeCount, 1)
        XCTAssertEqual(defaults.double(forKey: key), 1.2)
        XCTAssertEqual(reloads, 1)

        sync.set(1.3, forKey: key, reloading: false)
        XCTAssertEqual(cloud.values[key] as? Double, 1.3)
        XCTAssertEqual(defaults.double(forKey: key), 1.3)
        XCTAssertEqual(reloads, 1, "the stepper's steps leave the reload to its settle")
        cloud.notify(NSUbiquitousKeyValueStoreServerChange)
        XCTAssertEqual(defaults.double(forKey: key), 1.3, "an unrelated change must not revert a step")

        cloud.values[key] = 0.8
        cloud.notify(NSUbiquitousKeyValueStoreServerChange)
        XCTAssertEqual(defaults.double(forKey: key), 0.8)
        cloud.values[key] = 11.0
        cloud.notify(NSUbiquitousKeyValueStoreServerChange)
        withExtendedLifetime(sync) {
            XCTAssertEqual(defaults.double(forKey: key), 0.8)
            XCTAssertEqual(cloud.writeCount, 2, "adopting a remote value must not echo it")
            XCTAssertEqual(reloads, 2)
        }
    }

    func testSavedComfortCurrentSeedsAnEmptyCloud() {
        let key = AppGroup.slackWindowSpeedKey
        defaults.set(0.7, forKey: key)
        let sync = sync()
        expectation(for: NSPredicate { [cloud] _, _ in
            cloud?.values[key] as? Double == 0.7
        }, evaluatedWith: nil)
        cloud.notify(NSUbiquitousKeyValueStoreInitialSyncChange)
        waitForExpectations(timeout: 3)
        withExtendedLifetime(sync) { XCTAssertEqual(reloads, 0) }
    }

    func testCloudDisabledStillSavesLocalEdits() {
        XCTAssertNil(FavoritesCloud.store)
        let sync = UnitsCloud(defaults: defaults, cloud: nil, reload: { self.reloads += 1 })
        sync.set("metric", forKey: unitsKey)
        XCTAssertEqual(defaults.string(forKey: unitsKey), "metric")
        XCTAssertEqual(reloads, 1)
    }
}

private final class MemoryUnitsCloud: NSUbiquitousKeyValueStore {
    var values: [String: Any] = [:]
    var writes: [String: String] = [:]
    var writeCount = 0
    var deferWrites = false

    override func object(forKey key: String) -> Any? { values[key] }

    override func set(_ value: Any?, forKey key: String) {
        guard !deferWrites else { return }
        values[key] = value
        writes[key] = value as? String
        writeCount += 1
    }

    override func set(_ value: String?, forKey key: String) {
        set(value as Any?, forKey: key)
    }

    override func synchronize() -> Bool { true }

    func notify(_ reason: Int) {
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self,
            userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: reason,
                       NSUbiquitousKeyValueStoreChangedKeysKey: [unitsKey, speedUnitKey]])
    }
}
