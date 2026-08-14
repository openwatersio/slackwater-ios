// Slackwater — GPL v3. SPIKE #57: the particle field's pure math and its
// flag-off invariant — the style builders must emit exactly what they emitted
// before unless `-currentParticles` is passed.
import CoreLocation
import XCTest
@testable import Slackwater

final class CurrentParticleTests: XCTestCase {
    func testWrapRecyclesIntoRange() {
        XCTAssertEqual(particleWrap(1300, 1200), 100, accuracy: 1e-9)
        XCTAssertEqual(particleWrap(-100, 1200), 1100, accuracy: 1e-9)
        XCTAssertEqual(particleWrap(0, 1200), 0, accuracy: 1e-9)
    }

    func testCoordinateDisplacesAlongBearing() {
        let c = CLLocationCoordinate2D(latitude: 50, longitude: -125)
        // Due north: latitude up, longitude unchanged.
        let n = particleCoordinate(c, bearingDeg: 0, alongM: 1113.2, acrossM: 0)
        XCTAssertEqual(n.latitude, 50.01, accuracy: 1e-4)
        XCTAssertEqual(n.longitude, -125, accuracy: 1e-9)
        // Due east: longitude up by 1/cos(lat) more than the equator would.
        let e = particleCoordinate(c, bearingDeg: 90, alongM: 1113.2, acrossM: 0)
        XCTAssertEqual(e.latitude, 50, accuracy: 1e-6)
        XCTAssertEqual(e.longitude, -125 + 0.01 / cos(50 * .pi / 180), accuracy: 1e-4)
        // Across is perpendicular: on a north bearing it moves east only.
        let a = particleCoordinate(c, bearingDeg: 0, alongM: 0, acrossM: 100)
        XCTAssertEqual(a.latitude, 50, accuracy: 1e-6)
        XCTAssertGreaterThan(a.longitude, -125)
    }

    /// Flag off in this process, so the builder must not know the spike
    /// exists — no particle source, no particle layer.
    func testFlagOffAddsNothingToTheStyle() {
        XCTAssertFalse(currentParticlesEnabled)
        let style = localFallbackStyle(landUrl: "", uscaUrl: "")
        let sources = style["sources"] as? [String: Any] ?? [:]
        XCTAssertNil(sources[CurrentParticleAnimator.sourceID])
        let layers = style["layers"] as? [[String: Any]] ?? []
        XCTAssertFalse(layers.contains { ($0["id"] as? String) == CurrentParticleAnimator.sourceID })
    }

    /// Flag on, the additions carry the zoom threshold and the pins' own
    /// state-colour expression — one meaning, one value.
    func testParticleStyleAdditionsCarryMinzoomAndStateColour() {
        var style: [String: Any] = ["sources": [String: Any](), "layers": [[String: Any]]()]
        addParticleStyle(&style)
        let layer = (style["layers"] as? [[String: Any]])?.last
        XCTAssertEqual(layer?["minzoom"] as? Double, PARTICLE_MIN_ZOOM)
        let colour = (layer?["paint"] as? [String: Any])?["circle-color"] as? [Any]
        XCTAssertEqual(colour?.first as? String, "match")
        XCTAssertNotNil((style["sources"] as? [String: Any])?[CurrentParticleAnimator.sourceID])
    }
}
