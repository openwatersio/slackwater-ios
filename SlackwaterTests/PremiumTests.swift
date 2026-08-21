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

    func testCacheRoundtrip() {
        let d = UserDefaults(suiteName: "test.premium")!
        defer { d.removePersistentDomain(forName: "test.premium") }
        PremiumStore.cache(true, into: d)
        XCTAssertTrue(d.bool(forKey: "slackwater.premium"))
        PremiumStore.cache(false, into: d)
        XCTAssertFalse(d.bool(forKey: "slackwater.premium"))
    }
}
