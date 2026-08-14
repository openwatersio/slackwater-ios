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
    func testChartDoesNotHardcodeDirectionColour() throws {
        let source = try repoSource("Slackwater/TimelineStrip.swift")
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

    /// Every value this branch retired, banned from every source file — not
    /// from the one file an audit happened to be looking at.
    ///
    /// Twice now a retired literal survived an audit that only greped where it
    /// expected the bug: `0xE0B45A` sat in `SlackwaterApp.swift`'s
    /// location-denied card, five times, through the entire amber split, in the
    /// My Location slot directly above Near Me glyphs drawing the new ebb — the
    /// exact adjacency the split existed to prevent. So this scans everything
    /// and whitelists nothing. A legitimate use is a conversation, not an
    /// exception: `Theme.swift`'s amber comment was reworded to stop spelling
    /// the value rather than being excluded from the scan.
    func testNoSourceFileSpellsARetiredColour() throws {
        let retired = [
            "0xE0B45A",   // the golden amber SN.amber moved away from
            "0x7FB4D8",   // the retired falling hue
            "#8fd0a0",    // map kind-green
            "#7fb3d5",    // map kind-blue
            "#c0d8e4",    // map chs-kind tone
        ]
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated() {
                for hex in retired where line.range(of: hex, options: .caseInsensitive) != nil {
                    offenders.append("\(name):\(n + 1): \(hex)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "retired colour literal still in source:\n" + offenders.joined(separator: "\n"))
    }

    /// The three list-card state→tone bindings. Every colour defect on this
    /// branch lived in a binding, not a token: invert `state.rising` and the
    /// card draws a perfectly valid flood blue on a falling tide, with every
    /// token, `colour(for:)`, `path(for:)` and source-grep test still green.
    func testCardGlyphToneBindings() {
        // Tide: rising ↔ .rising, falling ↔ .falling, no reading ↔ .unknown.
        XCTAssertEqual(StationCardView.glyphTone(CardState(height: 1, rising: true, next: nil)), .rising)
        XCTAssertEqual(StationCardView.glyphTone(CardState(height: 1, rising: false, next: nil)), .falling)
        XCTAssertEqual(StationCardView.glyphTone(nil), .unknown)

        // Current: signed velocity through currentPhase, slack included.
        XCTAssertEqual(CurrentCardView.glyphTone(CurrentCardState(signed: 3, next: nil)), .flood)
        XCTAssertEqual(CurrentCardView.glyphTone(CurrentCardState(signed: -3, next: nil)), .ebb)
        XCTAssertEqual(CurrentCardView.glyphTone(CurrentCardState(signed: 0, next: nil)), .slack)
        XCTAssertEqual(CurrentCardView.glyphTone(nil), .unknown)

        // Derived gate: the phase word, no speed exists.
        XCTAssertEqual(ChsGateCardView.glyphTone(.flood), .flood)
        XCTAssertEqual(ChsGateCardView.glyphTone(.ebb), .ebb)
        XCTAssertEqual(ChsGateCardView.glyphTone(.slack), .slack)
        XCTAssertEqual(ChsGateCardView.glyphTone(nil), .unknown)

        // And the tones each land on the colour the rule says they do — the
        // binding and the palette asserted end to end, which is the whole
        // chain a wrong glyph colour can break.
        assertSameColour(StationGlyph.colour(for: StationCardView.glyphTone(
            CardState(height: 1, rising: true, next: nil))), SN.flood, "a rising tide draws flood")
        assertSameColour(StationGlyph.colour(for: CurrentCardView.glyphTone(
            CurrentCardState(signed: 0, next: nil))), SN.go, "a gate at slack draws go")
    }

    /// The map's palette must BE the tokens. Its colours are hex strings
    /// (MapLibre style dicts cannot hold a Swift `Color`), and while they were
    /// hand-maintained nothing tied them to `Theme.swift`: retarget `SN.flood`
    /// and the map kept the old blue — two blues both meaning flood, and not
    /// one failing test. They are derived from the token hexes now; this
    /// asserts the wiring, i.e. that `rising` reaches flood and not ebb.
    func testMapPinHexesTrackTheTokens() throws {
        let expected: [String: UInt32] = [
            "rising": SN.floodHex, "flood": SN.floodHex,
            "falling": SN.ebbHex, "ebb": SN.ebbHex,
            "slack": SN.goHex,
        ]
        var seen: Set<String> = []
        var i = 2   // past "match" and ["get", "state"]
        while i + 1 < PIN_STATE_COLOUR.count {
            let state = try XCTUnwrap(PIN_STATE_COLOUR[i] as? String)
            let hex = try XCTUnwrap(PIN_STATE_COLOUR[i + 1] as? String)
            // Darkened by the map's one land-contrast factor (issue #13), but
            // still FROM the token — retarget SN.flood and the map follows.
            XCTAssertEqual(hex, mapHex(try XCTUnwrap(expected[state], "unexpected pin state \(state)"),
                                       darkenedBy: PIN_STATE_DARKEN),
                           "map pin colour for \(state)")
            seen.insert(state)
            i += 2
        }
        XCTAssertEqual(seen, Set(expected.keys), "every state must have a pin colour")

        // One grey for "unknown" across surfaces: the map's neutral pin is the
        // same token the card glyph draws, and the match's fallback references
        // that constant rather than repeating its value.
        XCTAssertEqual(PIN_NEUTRAL, mapHex(SN.steelHex), "the unknown pin must be SN.steel")
        assertSameColour(StationGlyph.colour(for: .unknown), SN.steel, "the unknown glyph must be SN.steel")
        XCTAssertEqual(PIN_STATE_COLOUR.last as? String, PIN_NEUTRAL, "the fallback must be PIN_NEUTRAL")
    }

    func testPinFeaturesCarryStateAndBothLayersShareOneColourExpression() throws {
        let source = try repoSource("Slackwater/MapScreen.swift")
        // Every pin feature must declare a state, defaulting to unknown.
        XCTAssertTrue(source.contains("\"state\""), "pin features must carry a state property")
        // Colour must be matched against state, never kind.
        XCTAssertNotNil(source.range(of: #"\["get", "state"\]"#, options: .regularExpression),
                        "colour must be driven by state")
        XCTAssertNil(source.range(of: #"(circle-color|icon-color)[^\n]*\["get", "kind"\]"#,
                                  options: .regularExpression),
                     "colour must never be matched against kind")
    }

    /// WCAG relative luminance, for the contrast floor below.
    private func luminance(_ hex: String) -> Double {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16) ?? 0
        let parts = [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff].map { c -> Double in
            let s = Double(c) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The pale water's price, and the reason every pin carries an ink outline.
    ///
    /// On the old navy water a pin's FILL cleared WCAG's 3:1 for a non-text
    /// mark by itself in every state. On `#e9f7ff` three of the four states
    /// fail it outright — flood 2.65, ebb 1.97, slack 2.11 — so the contrast
    /// moved to the boundary, which is a thing a bounded mark is allowed to do.
    /// That makes the outline load-bearing rather than decorative: delete it,
    /// or let the water drift lighter, and the map silently drops under the
    /// floor in exactly the states it most needs to be read in.
    ///
    /// Asserts on the outline, NOT on the fills — the fills legitimately fail
    /// now, and a test that demanded otherwise would be demanding the palette
    /// go back to navy.
    func testEveryPinOutlineClearsTheContrastFloorOnBothGrounds() throws {
        let source = try repoSource("Slackwater/MapScreen.swift")
        func literal(_ name: String) throws -> String {
            // Two-hash delimiters: the pattern contains "# (the opening quote
            // of a hex literal), which closes a single-hash raw string.
            let match = try XCTUnwrap(
                source.range(of: ##"let \##(name) = "#[0-9a-fA-F]{6}""##, options: .regularExpression),
                "\(name) must stay a plain hex literal this test can read")
            return String(source[match].suffix(8).prefix(7))
        }
        let ink = try literal("CHART_INK")
        let water = try literal("WATER_TONE")
        let land = try literal("LAND_TONE")
        for (ground, hex) in [("water", water), ("land", land)] {
            XCTAssertGreaterThanOrEqual(
                contrast(ink, hex), 3.0,
                "the pin outline is under 3:1 on the \(ground) — every pin state relies on it")
        }
        // Both kinds must actually draw that outline, and the square's comes
        // from a backing plate because MapLibre Native renders no icon-halo on
        // its template image. One kind outlined and the other not is how this
        // regressed the first time.
        XCTAssertNotNil(source.range(of: #""circle-stroke-color": CHART_INK"#),
                        "the circle pin lost its ink stroke")
        XCTAssertNotNil(source.range(of: #""icon-color": CHART_INK"#),
                        "the tide square lost its ink backing plate")
        XCTAssertTrue(source.contains("pin-square-plate"),
                      "the backing-plate image must be registered, or the plate layer draws nothing")
    }

    /// Issue #13: a pin FILL must clear WCAG 1.4.11's 3:1 over the cream land
    /// polygons on its own. The outline test above covers pale water, where
    /// the fills legitimately lean on the ink stroke — but over land the fill
    /// is what says the state, and the raw tokens washed out there (flood
    /// 2.47, ebb 1.83, go 1.96). Walks the actual match expression rather
    /// than a list of expected colours, so a new state cannot ship an
    /// unmeasured fill.
    func testEveryPinStateFillClearsTheContrastFloorOnLand() throws {
        let source = try repoSource("Slackwater/MapScreen.swift")
        let match = try XCTUnwrap(
            source.range(of: ##"let LAND_TONE = "#[0-9a-fA-F]{6}""##, options: .regularExpression),
            "LAND_TONE must stay a plain hex literal this test can read")
        let land = String(source[match].suffix(8).prefix(7))

        var fills: [String: String] = ["unknown": try XCTUnwrap(PIN_STATE_COLOUR.last as? String)]
        var i = 2   // past "match" and ["get", "state"]
        while i + 1 < PIN_STATE_COLOUR.count {
            fills[try XCTUnwrap(PIN_STATE_COLOUR[i] as? String)] =
                try XCTUnwrap(PIN_STATE_COLOUR[i + 1] as? String)
            i += 2
        }
        for (state, hex) in fills {
            XCTAssertGreaterThanOrEqual(
                contrast(hex, land), 3.0,
                "the \(state) pin fill \(hex) is under 3:1 on the land tone \(land)")
        }
        // Darkening must not collapse the hues: the two direction ends, slack
        // and the neutral must stay four tellable-apart fills, not just four
        // fills that each clear the floor.
        XCTAssertEqual(Set(fills.values).count, 4,
                       "the pin palette must keep four distinct fills: \(fills)")
    }
}
