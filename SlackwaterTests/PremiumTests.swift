// Slackwater — GPL v3. Premium entitlement derivation + shared-defaults cache
// — the part the widget's free/premium gate depends on.
import XCTest
@testable import Slackwater

final class PremiumTests: XCTestCase {
    func testCarouselOrder() {
        XCTAssertEqual(PremiumFeature.carousel(for: .mobile), [.print, .alerts, .calendars, .lockScreen, .watch, .sky])
        XCTAssertEqual(PremiumFeature.carousel(for: .mac), [.print, .alerts, .calendars, .watch, .sky])
    }

    func testSelectedPlanMissingFromAPartialLoadIsUnavailable() {
        let yearly = PremiumStore.yearlyID, lifetime = PremiumStore.lifetimeID
        XCTAssertTrue(PremiumPurchase.unavailable(loading: false, plan: yearly, loaded: [lifetime]))
        XCTAssertTrue(PremiumPurchase.unavailable(loading: false, plan: yearly, loaded: []))
        XCTAssertFalse(PremiumPurchase.unavailable(loading: true, plan: yearly, loaded: []))
        XCTAssertFalse(PremiumPurchase.unavailable(loading: false, plan: lifetime, loaded: [lifetime]))
    }

    /// Every turn's label sits wholly inside the pane or wholly outside it.
    func testSkyPaneEdgesClearEveryTurn() {
        let width: CGFloat = 160, center: CGFloat = 1000, margin: CGFloat = 40
        let turns: [CGFloat] = [925, 1060, 1200]
        let left = skyPaneLeft(width: width, center: center, turns: turns, margin: margin)
        for turn in turns {
            XCTAssertGreaterThanOrEqual(abs(turn - left), margin)
            XCTAssertGreaterThanOrEqual(abs(turn - (left + width)), margin)
        }
        XCTAssertNotEqual(left, center - width / 2, "the centred edge cuts the first turn")
        XCTAssert(((left + 16)...(left + width - 16)).contains(center))
        XCTAssertEqual(skyPaneLeft(width: width, center: center, turns: [], margin: margin), center - width / 2)
    }

    func testEntitlementDerivation() {
        XCTAssertFalse(PremiumStore.isPremium(owned: []))
        XCTAssertFalse(PremiumStore.isPremium(owned: ["some.other.product"]))
        XCTAssertTrue(PremiumStore.isPremium(owned: [PremiumStore.yearlyID]))
        XCTAssertTrue(PremiumStore.isPremium(owned: ["io.openwaters.slackwater.premium.lifetime.v2"]))
        XCTAssertTrue(PremiumStore.isPremium(owned: [PremiumStore.yearlyID,
                                                     PremiumStore.lifetimeID]))
    }

    /// T6: `.unverified` must surface as a real, human-readable error rather
    /// than silently doing nothing. Message only — StoreKitTest signs its
    /// transactions with a local certificate the app trusts, so a test session
    /// has no way to hand `purchase(_:)` an unverified result to act on.
    func testUnverifiedErrorHasAMessage() {
        XCTAssertEqual(PremiumError.unverified.errorDescription,
                       "Purchase couldn't be verified — try again.")
    }

    func testCacheRoundtrip() {
        let d = UserDefaults(suiteName: "test.premium")!
        defer { d.removePersistentDomain(forName: "test.premium") }
        PremiumStore.cache(true, into: d)
        XCTAssertTrue(d.bool(forKey: AppGroup.premiumKey))
        PremiumStore.cache(false, into: d)
        XCTAssertFalse(d.bool(forKey: AppGroup.premiumKey))
    }

    // MARK: Free day store

    @MainActor private func freeDayStore(cloud: MemoryFreeDayCloud, suite: String,
                              purchased: Bool = false) -> (FreeDayStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (FreeDayStore(cloud: cloud, defaults: defaults, purchased: { purchased }), defaults)
    }

    @MainActor func testFreeDayStartIgnoredWhenPurchased() {
        let cloud = MemoryFreeDayCloud()
        let (store, defaults) = freeDayStore(cloud: cloud, suite: "test.freeDay.purchased", purchased: true)
        defer { defaults.removePersistentDomain(forName: "test.freeDay.purchased") }
        store.start(now: Date(timeIntervalSince1970: 1_793_000_000))
        XCTAssertNil(store.lastStart)
        XCTAssertNil(cloud.dates[AppGroup.freeDayStartKey])
        XCTAssertNil(defaults.object(forKey: AppGroup.freeDayStartKey))
    }

    @MainActor func testFreeDayStartIgnoredWhenUsedThisMonth() {
        let cloud = MemoryFreeDayCloud()
        let first = Date(timeIntervalSince1970: 1_793_000_000)
        let (store, defaults) = freeDayStore(cloud: cloud, suite: "test.freeDay.used")
        defer { defaults.removePersistentDomain(forName: "test.freeDay.used") }
        store.start(now: first)
        // Two days on is still the same month in any time zone.
        store.start(now: first + 2 * 86_400)
        XCTAssertEqual(store.lastStart, first)
    }

    @MainActor func testFreeDayStartWritesBothStores() {
        let cloud = MemoryFreeDayCloud()
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let (store, defaults) = freeDayStore(cloud: cloud, suite: "test.freeDay.writes")
        defer { defaults.removePersistentDomain(forName: "test.freeDay.writes") }
        store.start(now: now)
        XCTAssertEqual(store.lastStart, now)
        XCTAssertEqual(store.current, FreeDay(start: now))
        XCTAssertEqual(cloud.dates[AppGroup.freeDayStartKey], now)
        XCTAssertEqual(defaults.object(forKey: AppGroup.freeDayStartKey) as? Date, now)
    }

    /// Another device's newer free day wins and reaches the App Group; an older one doesn't.
    @MainActor func testFreeDayAdoptsNewerCloudStart() {
        let suite = "test.freeDay.adopt"
        let older = Date(timeIntervalSince1970: 1_790_000_000)
        let newer = Date(timeIntervalSince1970: 1_793_000_000)
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(older, forKey: AppGroup.freeDayStartKey)
        let cloud = MemoryFreeDayCloud()
        cloud.dates[AppGroup.freeDayStartKey] = newer
        let store = FreeDayStore(cloud: cloud, defaults: defaults, purchased: { false })
        XCTAssertEqual(store.lastStart, newer)
        XCTAssertEqual(defaults.object(forKey: AppGroup.freeDayStartKey) as? Date, newer)

        cloud.dates[AppGroup.freeDayStartKey] = older
        store.adoptCloud()
        XCTAssertEqual(store.lastStart, newer)
    }
}

private final class MemoryFreeDayCloud: FreeDayCloud {
    var dates: [String: Date] = [:]
    func date(forKey key: String) -> Date? { dates[key] }
    func set(_ date: Date, forKey key: String) { dates[key] = date }
    func synchronize() -> Bool { true }
}
