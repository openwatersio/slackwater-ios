// Slackwater — GPL v3. Static current fill and direction style behavior —
// the runtime layers both fill providers and the direction arrows draw
// through, the colour transfer, and the launch-override contract.
import MapLibre
import XCTest
@testable import Slackwater

final class CurrentFillTests: XCTestCase {
    private func source(_ id: String) -> MLNShapeSource {
        MLNShapeSource(identifier: id, shape: nil, options: nil)
    }

    func testFillIsOnExceptForTestLaunchOverride() {
        XCTAssertTrue(currentFillEnabled(arguments: []))
        XCTAssertFalse(currentFillEnabled(arguments: ["-currentFillOff"]))

        // A value left by a released build must not remain a hidden user setting.
        UserDefaults.standard.set(false, forKey: "showCurrentFill")
        XCTAssertTrue(currentFillEnabled(arguments: []))
        UserDefaults.standard.removeObject(forKey: "showCurrentFill")
    }

    /// The runtime fill layers: identical paint minus the source binding
    /// (one ramp, one opacity law, one no-green rule for both providers), a
    /// per-feature colour, antialias off, and an opacity that rides speed but
    /// never reaches zero — certified coverage must stay distinguishable from
    /// true no-data (spec §1). Patch-above-fill ordering is `attach`’s add
    /// order, checked on the identifiers here.
    func testFillLayersSharePaintAndColourPerFeature() {
        let layers = fillStyleLayers(fill: source(CurrentFillRenderer.sourceID),
                                     patch: source(CurrentFillRenderer.patchSourceID))
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

    /// The static direction channel: one map-aligned, collision-managed
    /// symbol layer per source, rotated per feature from the "bearing"
    /// attribute, ink-tinted, and gated to detail zooms. The animation
    /// channel is gone — these four layers are everything the current
    /// renderer adds.
    func testDirectionLayersAreMapAlignedSymbolsAndNoStreaksRemain() {
        let layers = fillStyleLayers(fill: source(CurrentFillRenderer.sourceID),
                                     patch: source(CurrentFillRenderer.patchSourceID))
        XCTAssertEqual(layers.direction.identifier, CurrentFillRenderer.directionLayerID)
        XCTAssertEqual(layers.patchDirection.identifier, CurrentFillRenderer.patchDirectionLayerID)
        for layer in [layers.direction, layers.patchDirection] {
            XCTAssertNotNil(layer.predicate,
                            "\(layer.identifier) must take only the point geometry")
            XCTAssertEqual(layer.minimumZoomLevel, Float(CURRENT_DIRECTION_MIN_ZOOM))
            XCTAssertEqual(layer.iconImageName?.constantValue as? String,
                           CurrentFillRenderer.directionImageID)
            XCTAssertTrue(String(describing: layer.iconRotation).contains("bearing"),
                          "\(layer.identifier) must rotate per feature")
            XCTAssertEqual(layer.iconRotationAlignment.constantValue as? String, "map")
            XCTAssertEqual(layer.iconPitchAlignment.constantValue as? String, "map")
            XCTAssertEqual(layer.iconAllowsOverlap.constantValue as? Bool, false,
                           "arrows are collision-managed, never a solid sheet")
            XCTAssertEqual((layer.iconColor.constantValue as? UIColor)?.description,
                           hexColor(CHART_INK).description)
        }
        let ids = [layers.fill, layers.patch, layers.direction, layers.patchDirection]
            .map(\.identifier)
        XCTAssertFalse(ids.contains { $0.contains("streak") },
                       "the animation channel is gone — nothing may recreate it")
    }

    /// The colour transfer is the composition of the two shipped #97 pieces —
    /// endpoints pin the ramp, and no speed may ever produce a green (green
    /// means transitable and only the gates may say it; spec §1 ruling).
    func testFillColourIsTheSharedRampAndNeverGreen() {
        XCTAssertEqual(fillColourHex(forSpeedKn: 0), "#f5c96b")     // threshold yellow
        XCTAssertEqual(fillColourHex(forSpeedKn: 99), "#c93a32")    // clamped red ceiling
        // Mid-anchor: kn=3 is exactly t=1/3 by the strip’s own anchors.
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
