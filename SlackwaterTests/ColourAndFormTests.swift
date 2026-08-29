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
            // The `l.fill(area,` triggers that used to live here are gone with
            // the two clipped direction fills (#97) — the current track's
            // colour is now guarded by function scope in the test below,
            // which is stronger than a line pairing.
            return line.contains("Color(hex:") &&
                (line.contains("maxFlood") || line.contains("maxEbb") ||
                 line.contains("\"FLOOD\"") || line.contains("\"EBB\"") ||
                 line.contains("Rectangle().fill("))    // the legend reference-line fill
        }
        XCTAssertTrue(offenders.isEmpty, "hardcoded direction colour in TimelineStrip.swift: \(offenders)")
    }

    // MARK: - The speed ramp (#97)

    /// Hue on the current track means speed now, not direction. The fills were
    /// clipped to the zero line, so blue could only ever render above it and
    /// amber below — hue was restating position while magnitude had no channel
    /// at all. Direction keeps its two novice-legible carriers here (position
    /// about the zero line, and the rotated set arrow); this asserts nothing
    /// quietly puts it back on colour.
    ///
    /// Scoped to `drawCurrent`'s body rather than the file: `drawTide`
    /// legitimately keeps `SN.rising`/`SN.falling`, which is #95's question,
    /// not this one's.
    func testCurrentTrackDoesNotSpeakDirectionInColour() throws {
        let source = try repoSource("Slackwater/TimelineStrip.swift")
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("private func drawCurrent(") }),
              let offset = lines[(start + 1)...].firstIndex(where: { $0 == "    }" })
        else { return XCTFail("drawCurrent's body not found — this tripwire needs retargeting") }
        let body = lines[start...offset]
        // `SN.flood`/`SN.ebb` catch their `…Label` variants as substrings.
        // `SN.leaf` is the slack-only green, which once stood in for the flood
        // fill; it has no business in this function under any name.
        let banned = ["SN.flood", "SN.ebb", "SN.rising", "SN.falling", "SN.leaf"]
        let offenders = body.filter { line in banned.contains(where: line.contains) }
        XCTAssertTrue(offenders.isEmpty,
                      "direction colour inside drawCurrent: \(offenders)")
        XCTAssertGreaterThan(body.count, 40, "body extraction looks wrong — check the guard above")
    }

    /// Green means slack and only slack. A ramp that passes through green puts
    /// a second, opposite meaning a few hundred points from the column that
    /// means *go* — which is the specific reason this is not a rainbow.
    func testSpeedRampContainsNoGreen() {
        for i in 0...40 {
            let t = Double(i) / 40
            let c = SN.speedRGB(t)
            XCTAssertFalse(c.g > c.r && c.g > c.b,
                           "the ramp is green-dominant at t=\(t); green is reserved for slack")
        }
    }

    func testSpeedRampRunsFromYellowThroughOrangeToRed() {
        let low = SN.speedRGB(0)
        let high = SN.speedRGB(1)
        XCTAssertGreaterThan(low.r, low.b, "the threshold colour must read yellow")
        XCTAssertGreaterThan(low.g, low.b, "the threshold colour must read yellow")
        XCTAssertGreaterThan(high.r, high.g, "the fastest water must read red")
        XCTAssertGreaterThan(high.g, high.b, "the fastest water must not return to purple")
    }

    /// A label sitting on the fill has to be readable at both ends of a ramp
    /// that runs dark to bright. Before #97 the inside ink was a fixed white,
    /// which was fine on a flat 0.32 fill and fails on `#F5C96B`.
    ///
    /// The applicable floor is WCAG's 3:1 — the mark is a 14pt semibold speed,
    /// which is large text. 4:1 is asserted instead because that is what the
    /// ramp actually delivers at its worst point (the white↔ink crossover at
    /// t ≈ 0.90, where both options measure ≈4.3:1). A stop edit that pushes
    /// it below 4 has changed something worth looking at.
    func testSpeedInkStaysReadableOnItsOwnFill() {
        for i in 0...40 {
            let t = Double(i) / 40
            let ink = rgb(SN.speedInk(t)) == rgb(.white) ? "FFFFFF" : "05122A"
            XCTAssertGreaterThan(contrast(ink, rampHex(t)), 4,
                                 "label ink is unreadable on the fill at t=\(t)")
        }
    }

    /// The ramp at `t` as a hex string, for the luminance/contrast helpers.
    private func rampHex(_ t: Double) -> String {
        let c = SN.speedRGB(t)
        return String(format: "%02X%02X%02X",
                      Int(c.r.rounded()), Int(c.g.rounded()), Int(c.b.rounded()))
    }

    /// Colour is the STATE axis. The "and never kind" this used to be named for
    /// is unenforceable by construction now — `colour(for:)` takes a `Tone` and
    /// nothing else, so there is no kind to pass it (StationGlyph.swift). The
    /// assertion that carried that half had decayed to
    /// `assertSameColour(colour(for: .slack), colour(for: .slack))` — literally
    /// x == x — when kind left the signature, and passed forever after.
    func testGlyphColourIsTheStateAxis() {
        // Different states: different colours.
        assertDifferentColour(StationGlyph.colour(for: .flood), StationGlyph.colour(for: .ebb),
                              "flood and ebb must not share a colour")
        assertSameColour(StationGlyph.colour(for: .rising), StationGlyph.colour(for: .flood),
                         "rising and flood are one end of the axis")
        assertSameColour(StationGlyph.colour(for: .slack), SN.go, "slack is the go colour")
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
            "0x00121F",   // the detail-page blue SN.canvas replaced
            "0x000E22",   // the strip's own moon limb, folded into SN.moonLimb
            "0x000C1E",   // the FAB's own shadow blue, folded into SN.shadow
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

    func testColourLiteralsLiveInTheme() throws {
        let allowed: Set<String> = ["Theme.swift", "TimelineStrip.swift"]
        var offenders: [String] = []
        for (name, source) in try appSources() where !allowed.contains(name) {
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where codeOnly(line).contains("Color(hex:") {
                offenders.append("\(name):\(n + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "hex colour literal outside \(allowed.sorted().joined(separator: ", ")) — use or add an SN token:\n"
                      + offenders.joined(separator: "\n"))
    }

    /// The one surviving list-card state→tone binding. Every colour defect on
    /// this branch lived in a binding, not a token: invert the phase and the
    /// glyph draws a perfectly valid colour for a state it isn't in, with
    /// every token, `colour(for:)`, `path(for:)` and source-grep test still
    /// green. `StationCardView`'s and `CurrentCardView`'s twins were deleted
    /// when #95 settled tide colour and nothing claimed them (their ponytail
    /// note's trigger).
    func testCardGlyphToneBindings() {
        // Derived gate: the phase word, no speed exists.
        XCTAssertEqual(ChsGateCardView.glyphTone(.flood), .flood)
        XCTAssertEqual(ChsGateCardView.glyphTone(.ebb), .ebb)
        XCTAssertEqual(ChsGateCardView.glyphTone(.slack), .slack)
        XCTAssertEqual(ChsGateCardView.glyphTone(nil), .unknown)

        // And the tone lands on the colour the rule says — the binding and
        // the palette asserted end to end.
        assertSameColour(StationGlyph.colour(for: ChsGateCardView.glyphTone(.slack)),
                         SN.go, "a gate at slack draws go")
    }

    /// Issue #14: no sheet row may still render the flat empty 38pt square
    /// left over from the gradient deletion — the rows that still carry a kind
    /// mark (the chooser sheet, the downloads manager) draw a real
    /// `StationGlyph`. The list's cards and recent rows draw none at all.
    func testNoFlatCardFillChipRemains() throws {
        var offenders: [String] = []
        for (name, source) in try appSources() {
            let flat = source.replacingOccurrences(
                of: "\\s+", with: " ", options: .regularExpression)
            if flat.contains(".fill(SN.cardFill) .frame(width: 38, height: 38)") {
                offenders.append(name)
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "flat 38pt cardFill chip still drawn in: \(offenders)")
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
        // #13: the expression is now to-color(state, match(...)) — a state
        // that IS a colour (speed-bearing current pins) renders as itself,
        // a named state falls through to the match below.
        XCTAssertEqual(PIN_STATE_COLOUR.first as? String, "to-color")
        let match = try XCTUnwrap(PIN_STATE_COLOUR[2] as? [Any])
        var seen: Set<String> = []
        var i = 2   // past "match" and ["get", "state"]
        while i + 1 < match.count {
            let state = try XCTUnwrap(match[i] as? String)
            let hex = try XCTUnwrap(match[i + 1] as? String)
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
        XCTAssertEqual(match.last as? String, PIN_NEUTRAL, "the fallback must be PIN_NEUTRAL")
    }

    /// #13: a speed-bearing current pin's colour is the #97 ramp darkened by
    /// the land-contrast factor — except inside the slack window, where it is
    /// the go colour. The boundary is `slackThresholdKn`, the same number the
    /// strip's green column uses.
    func testCurrentPinColourIsRampOutsideWindowGoInside() {
        let still = record(speedKn: 0)
        XCTAssertEqual(currentPinColour(still, at: refTime),
                       mapHex(SN.goHex, darkenedBy: PIN_STATE_DARKEN), "slack pin must be go")
        let fast = record(speedKn: 3.0)
        XCTAssertEqual(currentPinColour(fast, at: refTime),
                       pinRampHex(forSpeedKn: 3.0), "moving pin must be the darkened ramp")
        XCTAssertNotEqual(currentPinColour(fast, at: refTime),
                          mapHex(SN.goHex, darkenedBy: PIN_STATE_DARKEN),
                          "a moving pin must never read go")
    }

    /// The darkened pin ramp must clear the 3:1 land floor at every speed it
    /// can actually render (above the threshold — below it the pin is go),
    /// and must never read green: green is the window's, exclusively.
    func testPinRampClearsContrastAndNeverGreen() throws {
        let source = try repoSource("Slackwater/MapStyleBuilder.swift")
        let match = try XCTUnwrap(
            source.range(of: ##"let LAND_TONE = "#[0-9a-fA-F]{6}""##, options: .regularExpression),
            "LAND_TONE must stay a plain hex literal this test can read")
        let land = String(source[match].suffix(8).prefix(7))
        var kn = slackThresholdKn + 0.01
        while kn <= 17 {
            let hex = pinRampHex(forSpeedKn: kn)
            XCTAssertGreaterThanOrEqual(contrast(hex, land), 3.0,
                                        "pin ramp at \(kn) kn (\(hex)) is under 3:1 on land")
            let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
            let (r, g, b) = (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
            XCTAssertFalse(g > r && g > b, "pin ramp at \(kn) kn reads green — green means go")
            kn += 0.25
        }
    }

    private var refTime: Date { Date(timeIntervalSince1970: 1_787_000_000) }
    private func record(speedKn: Double) -> CurrentStationRecord {
        // M2 amplitude 0 → speed is meanFlow exactly, at any instant.
        CurrentStationRecord(
            id: "t", name: "t", region: "t", aliases: [], latitude: 0, longitude: 0,
            timezone: "UTC", floodDirection: 0, ebbDirection: 180, meanFlow: speedKn,
            tideReference: nil, constituents: [.init(name: "M2", amplitude: 0, phase: 0)])
    }

    func testPinFeaturesCarryStateAndBothLayersShareOneColourExpression() throws {
        // The feature builder and the layers that colour it live in two files;
        // the rule spans both, so it is scanned as one text.
        let source = try repoSource("Slackwater/MapPinState.swift")
            + repoSource("Slackwater/MapStyleBuilder.swift")
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
        let source = try repoSource("Slackwater/MapStyleBuilder.swift")
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
        let source = try repoSource("Slackwater/MapStyleBuilder.swift")
        let match = try XCTUnwrap(
            source.range(of: ##"let LAND_TONE = "#[0-9a-fA-F]{6}""##, options: .regularExpression),
            "LAND_TONE must stay a plain hex literal this test can read")
        let land = String(source[match].suffix(8).prefix(7))

        let stateMatch = try XCTUnwrap(PIN_STATE_COLOUR[2] as? [Any])
        var fills: [String: String] = ["unknown": try XCTUnwrap(stateMatch.last as? String)]
        var i = 2   // past "match" and ["get", "state"]
        while i + 1 < stateMatch.count {
            fills[try XCTUnwrap(stateMatch[i] as? String)] =
                try XCTUnwrap(stateMatch[i + 1] as? String)
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
