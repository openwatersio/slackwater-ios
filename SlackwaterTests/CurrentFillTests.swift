// Slackwater — GPL v3. The current fill layer (#57 channel 1, graduation
// spec §2): style additions, the colour transfer, and the toggle contract —
// on by default, off is byte-identical to the pre-fill style.
import MapLibre
import XCTest
@testable import Slackwater

final class CurrentFillTests: XCTestCase {
    private func source(_ id: String) -> MLNShapeSource {
        MLNShapeSource(identifier: id, shape: nil, options: nil)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: currentFillKey)
        super.tearDown()
    }

    /// The layer ships ON: a clean install draws the fill without any setting
    /// being touched (graduation spec §2 — default on).
    func testFillShipsOnByDefault() {
        UserDefaults.standard.removeObject(forKey: currentFillKey)
        XCTAssertTrue(currentFillEnabled)
    }

    /// A launch-argument override arrives as a STRING ("-showCurrentFill NO"),
    /// not a Bool — the read must coerce it the same way AppStorage does, or
    /// the FAB shows off while the layer still draws (caught on screen).
    func testStringValuedDefaultReadsAsOff() {
        UserDefaults.standard.set("NO", forKey: currentFillKey)
        XCTAssertFalse(currentFillEnabled)
    }

    /// The runtime fill layers: identical paint minus the source binding
    /// (one ramp, one opacity law, one no-green rule for both providers), a
    /// per-feature colour, antialias off, and an opacity that rides speed but
    /// never reaches zero — certified coverage must stay distinguishable from
    /// true no-data (spec §1). Patch-above-fill ordering is `attach`'s add
    /// order, checked on the identifiers here.
    func testFillLayersSharePaintAndColourPerFeature() {
        let layers = fillStyleLayers(fill: source(CurrentFillRenderer.sourceID),
                                     patch: source(CurrentFillRenderer.patchSourceID),
                                     streaks: source(CurrentStreakAnimator.sourceID))
        XCTAssertEqual(layers.fill.identifier, CurrentFillRenderer.sourceID)
        XCTAssertEqual(layers.patch.identifier, CurrentFillRenderer.patchSourceID)
        for layer in [layers.fill, layers.patch] {
            // The getter normalizes to a colour cast around the key path —
            // the invariant is that the "colour" attribute drives the paint.
            XCTAssertTrue(String(describing: layer.fillColor).contains("colour"),
                          "\(layer.identifier) must colour per feature")
            XCTAssertEqual(layer.fillAntialiased.constantValue as? Bool, false,
                           "\(layer.identifier) must keep antialias off or the mesh redraws as seams")
        }
        XCTAssertEqual(layers.fill.fillColor, layers.patch.fillColor,
                       "one colour law for both providers")
        XCTAssertEqual(layers.fill.fillOpacity, layers.patch.fillOpacity,
                       "one opacity law for both providers")
        XCTAssertTrue(String(describing: layers.fill.fillOpacity).contains("\(FILL_OPACITY_FLOOR)"),
                      "the opacity floor left the paint — no-data and slack water become indistinguishable")
    }

    /// Streaks ride above both fill providers (the add order in `attach`),
    /// tails are foam and heads take the #97 ramp per feature — the state
    /// palette must never reach this channel. Tails and heads share one
    /// source, so each layer takes only the geometry it draws: a circle layer
    /// given a tail would dot every vertex of it.
    func testStreakLayersRideAboveTheFillWithFoamTailsAndRampHeads() {
        let layers = fillStyleLayers(fill: source(CurrentFillRenderer.sourceID),
                                     patch: source(CurrentFillRenderer.patchSourceID),
                                     streaks: source(CurrentStreakAnimator.sourceID))
        XCTAssertEqual(layers.streakTail.identifier, CurrentStreakAnimator.tailLayerID)
        XCTAssertEqual(layers.streakHead.identifier, CurrentStreakAnimator.headLayerID)
        // Compared by description: two UIColors built the same way are not
        // `==` unless they share a colour space.
        XCTAssertEqual((layers.streakTail.lineColor.constantValue as? UIColor)?.description,
                       hexColor(mapHex(SN.foamHex)).description,
                       "tails are foam, not the ramp")
        XCTAssertTrue(String(describing: layers.streakHead.circleColor).contains("colour"),
                      "streak heads must take the ramp colour their features carry")
        XCTAssertFalse(String(describing: layers.streakHead.circleColor)
                        .contains(String(describing: PIN_STATE_COLOUR)),
                       "the pin state palette must never reach the streak channel")
        for layer in [layers.streakTail as MLNVectorStyleLayer, layers.streakHead] {
            XCTAssertNotNil(layer.predicate,
                            "\(layer.identifier) must take only its own geometry")
            XCTAssertEqual(layer.minimumZoomLevel, Float(STREAK_MIN_ZOOM))
        }
    }

    /// The colour transfer is the composition of the two shipped #97 pieces —
    /// endpoints pin the ramp, and no speed may ever produce a green (green
    /// means transitable and only the gates may say it; spec §1 ruling).
    func testFillColourIsTheSharedRampAndNeverGreen() {
        XCTAssertEqual(fillColourHex(forSpeedKn: 0), "#f5c96b")     // threshold yellow
        XCTAssertEqual(fillColourHex(forSpeedKn: 99), "#c93a32")    // clamped red ceiling
        // Mid-anchor: kn=3 is exactly t=1/3 by the strip's own anchors.
        let c = SN.speedRGB(Timeline.rampT(forSpeedKn: 3))
        XCTAssertEqual(fillColourHex(forSpeedKn: 3),
                       String(format: "#%02x%02x%02x", Int(c.r.rounded()), Int(c.g.rounded()), Int(c.b.rounded())))
        // Never green: sweep the ramp; green must never dominate both other
        // channels the way SN.go does. (Inferno-family has no green band by
        // construction — this assertion keeps that true through any retune.)
        for kn in stride(from: 0.0, through: 17.0, by: 0.25) {
            let c = SN.speedRGB(Timeline.rampT(forSpeedKn: kn))
            XCTAssertFalse(c.g > c.r && c.g > c.b,
                           "ramp at \(kn) kn reads green — forbidden by the #97/spec ruling")
        }
    }
}
