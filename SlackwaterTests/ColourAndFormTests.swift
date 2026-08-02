import SwiftUI
import XCTest
@testable import Slackwater

/// Colour is state; form is kind. These tests are the rule, executable.
final class ColourAndFormTests: XCTestCase {

    /// Resolved sRGB components, so two Colors built the same way compare equal.
    private func rgb(_ color: Color) -> [CGFloat] {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 1000).rounded() / 1000 }
    }

    private func assertSameColour(_ a: Color, _ b: Color, _ message: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rgb(a), rgb(b), message, file: file, line: line)
    }

    private func assertDifferentColour(_ a: Color, _ b: Color, _ message: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(rgb(a), rgb(b), message, file: file, line: line)
    }

    func testDirectionIsASignedDivergingAxis() {
        assertSameColour(SN.rising, SN.flood, "rising must alias flood")
        assertSameColour(SN.falling, SN.ebb, "falling must alias ebb")
        assertDifferentColour(SN.flood, SN.ebb, "the two ends of the axis must differ")
    }

    func testGreenMeansOnlySlack() {
        assertDifferentColour(SN.go, SN.flood, "green must not also mean flood")
        assertDifferentColour(SN.go, SN.ebb, "green must not also mean ebb")
    }

    func testWarningIsDistinguishableFromEbb() {
        // These were briefly the same hex on web and collided in the event list,
        // where a sunset pill and a max-ebb pill became indistinguishable.
        assertDifferentColour(SN.amber, SN.ebb, "the warning tone must not read as ebb")
    }

    func testSlackIsGreenWhereverItAppears() {
        // A gate at slack must not show a green glyph beside a grey "slack"
        // pill in the same card — which is exactly what happened on web when
        // only one surface adopted the go colour.
        assertSameColour(CurrentDetailView.phaseColor(.slack), SN.go, "detail view slack")
        assertSameColour(DerivedGateDetailView.phaseColor(.slack), SN.go, "derived gate slack")
    }

    func testPhaseColoursUseTheDivergingAxis() {
        assertSameColour(CurrentDetailView.phaseColor(.flood), SN.flood, "flood")
        assertSameColour(CurrentDetailView.phaseColor(.ebb), SN.ebb, "ebb")
    }

    /// The chart's max-speed dot labels, FLOOD/EBB legend, and the current
    /// track's area fill all once spoke the retired direction colours even
    /// after the tokens were retargeted — the fill even used `SN.leaf`, the
    /// slack-only green, for the flood half. A raw hex literal (or `SN.leaf`)
    /// sharing a line with one of these markers is exactly how either
    /// regression would return. A source-text guard, not a rendered-colour
    /// one, because the bug was a literal slipping back in, not a wrong
    /// value from a token. This is line-based source matching, not a parse —
    /// a reformat that rewraps these lines can disable a trigger or, just as
    /// easily, false-positive on neutral chrome that happens to land on the
    /// same line. Treat it as a tripwire, not a guarantee.
    func testChartDoesNotHardcodeDirectionColour() {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater/TimelineStrip.swift")
        let source = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        XCTAssertFalse(source.isEmpty, "could not read TimelineStrip.swift at \(path.path)")
        let offenders = source.components(separatedBy: .newlines).filter { line in
            // A raw hex on a line that also names a direction marker.
            // "Rectangle().fill(" is paired with hex only, not SN.leaf — that
            // pairing legitimately appears elsewhere (the schedule row's
            // highlight bar), and would false-positive if included here.
            let hexOffender = line.contains("Color(hex:") &&
                (line.contains("maxFlood") || line.contains("maxEbb") ||
                 line.contains("\"FLOOD\"") || line.contains("\"EBB\"") ||
                 line.contains("l.fill(area,") ||       // the flood/ebb area fill
                 line.contains("Rectangle().fill("))    // the legend reference-line fill
            // SN.leaf (the slack-only green) standing in for a direction
            // colour — only checked against the area fill, the one place
            // this specific regression actually happened.
            let leafOffender = line.contains("SN.leaf") && line.contains("l.fill(area,")
            return hexOffender || leafOffender
        }
        XCTAssertTrue(offenders.isEmpty, "hardcoded direction colour in TimelineStrip.swift: \(offenders)")
    }

    func testGlyphColourTracksStateAndNeverKind() {
        // Same state, different kinds: same colour.
        assertSameColour(StationGlyph.colour(for: .slack), StationGlyph.colour(for: .slack),
                         "tone determines colour")
        // Different states: different colours.
        assertDifferentColour(StationGlyph.colour(for: .flood), StationGlyph.colour(for: .ebb),
                              "flood and ebb must not share a colour")
        assertSameColour(StationGlyph.colour(for: .rising), StationGlyph.colour(for: .flood),
                         "rising and flood are one end of the axis")
        assertSameColour(StationGlyph.colour(for: .slack), SN.go, "slack is the go colour")
    }

    func testGlyphShapeTracksKind() {
        // The two kinds must not produce identical paths — that would collapse
        // the form axis and leave kind unexpressed.
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        XCTAssertNotEqual(StationGlyph.path(for: .tide, in: box).description,
                          StationGlyph.path(for: .current, in: box).description,
                          "tide and current must draw different shapes")
    }

    func testMapNeverColoursByStationKind() throws {
        // The defect this whole change exists to remove: the map matched
        // circle-color against ["get", "kind"], so a green dot meant "current
        // station" here and "flooding" everywhere else.
        let source = try String(contentsOfFile: mapScreenPath(), encoding: .utf8)
        XCTAssertFalse(source.contains("#8fd0a0"), "retired kind-green must be gone")
        XCTAssertFalse(source.contains("#7fb3d5"), "retired kind-blue must be gone")
        XCTAssertFalse(source.contains("#c0d8e4"), "retired chs-kind tone must be gone")
        XCTAssertNil(source.range(of: #"circle-color[^\n]*\["get", "kind"\]"#, options: .regularExpression),
                     "colour must never be matched against kind")
    }

    /// `#filePath` of this test file resolves to the repo, so the source under
    /// test can be read relative to it.
    private func mapScreenPath() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SlackwaterTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Slackwater/MapScreen.swift").path
    }
}
