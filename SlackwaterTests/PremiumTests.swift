// Slackwater — GPL v3. Premium entitlement derivation + shared-defaults cache
// — the part the widget's free/premium gate depends on.
import XCTest
@testable import Slackwater

final class PremiumTests: XCTestCase {
    func testEntitlementDerivation() {
        XCTAssertFalse(PremiumStore.isPremium(owned: []))
        XCTAssertFalse(PremiumStore.isPremium(owned: ["some.other.product"]))
        XCTAssertTrue(PremiumStore.isPremium(owned: [PremiumStore.yearlyID]))
        XCTAssertTrue(PremiumStore.isPremium(owned: [PremiumStore.lifetimeID]))
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
}
