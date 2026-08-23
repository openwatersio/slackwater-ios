// Slackwater — GPL v3. The current fill layer (#57 channel 1, graduation
// spec §2): style additions, the colour transfer, and the toggle contract —
// on by default, off is byte-identical to the pre-fill style.
import XCTest
@testable import Slackwater

final class CurrentFillTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: currentFillKey)
        super.tearDown()
    }

    /// The layer ships ON: a clean install draws the fill without any setting
    /// being touched (graduation spec §2 — default on).
    func testFillShipsOnByDefault() {
        UserDefaults.standard.removeObject(forKey: currentFillKey)
        XCTAssertTrue(currentFillEnabled)
        let style = localFallbackStyle(landUrl: "", uscaUrl: "")
        let layers = style["layers"] as? [[String: Any]] ?? []
        XCTAssertTrue(layers.contains { ($0["id"] as? String) == CurrentFillRenderer.sourceID })
    }

    /// A launch-argument override arrives as a STRING ("-showCurrentFill NO"),
    /// not a Bool — the read must coerce it the same way AppStorage does, or
    /// the FAB shows off while the layer still draws (caught on screen).
    func testStringValuedDefaultReadsAsOff() {
        UserDefaults.standard.set("NO", forKey: currentFillKey)
        XCTAssertFalse(currentFillEnabled)
    }

    /// Toggle off, the builders must emit exactly what they emitted before
    /// the fill existed — no source, no layer.
    func testToggleOffAddsNothingToTheStyle() {
        UserDefaults.standard.set(false, forKey: currentFillKey)
        XCTAssertFalse(currentFillEnabled)
        let style = localFallbackStyle(landUrl: "", uscaUrl: "")
        let sources = style["sources"] as? [String: Any] ?? [:]
        XCTAssertNil(sources[CurrentFillRenderer.sourceID])
        let layers = style["layers"] as? [[String: Any]] ?? []
        XCTAssertFalse(layers.contains { ($0["id"] as? String) == CurrentFillRenderer.sourceID })
    }

    /// Patch cells outrank backdrop cells at the mouth fringe purely by draw
    /// order, and feature order within one source does NOT guarantee paint
    /// order — so patches get their own layer, directly above the fill's
    /// (grown-patches spec §5; the ordering rule lives here by agreement).
    func testPatchLayerSitsDirectlyAboveFillWithIdenticalPaint() {
        var style: [String: Any] = ["sources": [String: Any](),
                                    "layers": [["id": "land-usca"], ["id": "station-clusters"]] as [[String: Any]]]
        addFillStyle(&style)
        let layers = style["layers"] as? [[String: Any]] ?? []
        let ids = layers.map { $0["id"] as? String ?? "" }
        let fill = ids.firstIndex(of: CurrentFillRenderer.sourceID)
        let patch = ids.firstIndex(of: CurrentFillRenderer.patchSourceID)
        XCTAssertNotNil(fill); XCTAssertNotNil(patch)
        XCTAssertEqual(patch, fill.map { $0 + 1 }, "patches must draw directly above the fill")
        XCTAssertLessThan(patch ?? 99, ids.firstIndex(of: "land-usca") ?? -1,
                          "both layers stay under land")
        // Identical paint minus the source binding: one ramp, one opacity law,
        // one no-green rule for both providers.
        var a = layers[fill!], b = layers[patch!]
        XCTAssertEqual(a["paint"] as? NSDictionary, b["paint"] as? NSDictionary)
        XCTAssertNotNil((style["sources"] as? [String: Any])?[CurrentFillRenderer.patchSourceID])
    }

    /// The fill layer sits UNDER the land layers — SSCOFS elements cross the
    /// shoreline, and land drawn over the fill clips them to water — and
    /// colours per feature from the "colour" attribute.
    func testFillLayerInsertsUnderLandAndColoursPerFeature() {
        var style: [String: Any] = ["sources": [String: Any](),
                                    "layers": [["id": "land-usca"], ["id": "station-clusters"]] as [[String: Any]]]
        addFillStyle(&style)
        let layers = style["layers"] as? [[String: Any]] ?? []
        XCTAssertEqual(layers.first?["id"] as? String, CurrentFillRenderer.sourceID)
        XCTAssertEqual(layers[2]["id"] as? String, "land-usca")
        XCTAssertEqual(layers.count, 4)
        let paint = layers.first?["paint"] as? [String: Any]
        XCTAssertEqual(paint?["fill-color"] as? [String], ["get", "colour"])
        XCTAssertEqual(paint?["fill-antialias"] as? Bool, false)
        // Opacity rides speed but never reaches zero — certified coverage
        // must stay distinguishable from true no-data (spec §1).
        let opacity = paint?["fill-opacity"] as? [Any]
        XCTAssertEqual(opacity?.first as? String, "interpolate")
        XCTAssertEqual(opacity?[4] as? Double, FILL_OPACITY_FLOOR)
        XCTAssertGreaterThan(FILL_OPACITY_FLOOR, 0)
        XCTAssertNotNil((style["sources"] as? [String: Any])?[CurrentFillRenderer.sourceID])
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
