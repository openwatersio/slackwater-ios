// Slackwater — GPL v3. Tiers are stopping points on one distance-sorted
// queue, and the cohort is what makes the in-view tier a fixed set rather
// than a moving target.
import XCTest
@testable import Slackwater

final class DownloadTierTests: XCTestCase {
    private let victoria = (lat: 48.4284, lon: -123.3656)

    private func job(_ id: String, _ lat: Double, _ lon: Double) -> ChsJob {
        ChsJob(id: id, name: id, region: "test", isCurrent: false,
               latitude: lat, longitude: lon, fitDays: 60)
    }

    func testInViewAdmitsOnlyTheCohort() {
        let inside = job("a", 48.43, -123.37)
        let outside = job("b", 48.44, -123.38)
        let cohort: Set<String> = ["a"]
        XCTAssertTrue(DownloadTier.inView.admits(inside, from: victoria, cohort: cohort))
        XCTAssertFalse(DownloadTier.inView.admits(outside, from: victoria, cohort: cohort),
                       "proximity must not smuggle a station into the automatic tier")
    }

    func testNearbyAdmitsInsideTwentyFiveKilometresAndTheCohort() {
        let close = job("close", 48.50, -123.40)          // ~9 km
        let far = job("far", 49.28, -123.12)              // ~95 km, Vancouver
        XCTAssertTrue(DownloadTier.nearby.admits(close, from: victoria, cohort: []))
        XCTAssertFalse(DownloadTier.nearby.admits(far, from: victoria, cohort: []))
        XCTAssertTrue(DownloadTier.nearby.admits(far, from: victoria, cohort: ["far"]),
                      "a station already on screen stays admitted at every tier")
    }

    func testEverythingAdmitsOutToTheExistingRadius() {
        let reachable = job("reachable", 49.28, -123.12)   // ~95 km, Vancouver
        let halifax = job("halifax", 44.6488, -63.5752)
        XCTAssertTrue(DownloadTier.everything.admits(reachable, from: victoria, cohort: []))
        XCTAssertFalse(DownloadTier.everything.admits(halifax, from: victoria, cohort: []),
                       "the widest tier still stops at the existing radius")
    }

    func testNearbyRadiusIsTwentyFive() {
        XCTAssertEqual(DownloadTier.nearbyRadiusKm, 25)
    }
}
