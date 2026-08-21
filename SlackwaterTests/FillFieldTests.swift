// Slackwater — GPL v3. FillField provider tests (fill-phase-b-design.md §4,
// task-6-brief.md). The `fill-fixture.bin`/`.json` pair in Fixtures/ was
// generated with `tools/fill-pipeline/pack.py` against a synthetic 3-element
// survivors+mesh input (not hand-typed bytes) — the same tool that will
// produce the real `fill-salish` bundle, so this is the third reader against
// pack.py's one normative layout (the second is test_pack.py's own
// `_read_bundle`).
import XCTest
import TideEngine
@testable import Slackwater

final class FillFieldTests: XCTestCase {
    private func loadFixture() throws -> FillField {
        let bundle = Bundle(for: FillFieldTests.self)
        let binURL = try XCTUnwrap(bundle.url(forResource: "fill-fixture", withExtension: "bin"))
        let jsonURL = try XCTUnwrap(bundle.url(forResource: "fill-fixture", withExtension: "json"))
        let field = try XCTUnwrap(FillField(bin: try Data(contentsOf: binURL),
                                             headerJSON: try Data(contentsOf: jsonURL)))
        return field
    }

    // (a) Bundle load: element count matches the header, vertex coordinates
    // round-trip (f32 precision), and the bbox cull actually culls — proving
    // the id table resolved (a bad id→name map would leave every axis empty
    // and every speed 0, which testGolden below would also catch harder).
    func testLoadsFixtureBundle() throws {
        let field = try loadFixture()
        let cells = field.cells(at: Date(timeIntervalSince1970: 1_787_000_000))
        XCTAssertEqual(cells.count, 3, "fixture header declares element_count 3")

        let first = try XCTUnwrap(cells.first)
        XCTAssertEqual(first.polygon.count, 3)
        // Fixture element 0 verts: (-123.0, 48.7), (-122.99, 48.7), (-123.0, 48.71) —
        // f32 round-trip, so 1e-4 deg (~1 cm) tolerance not 1e-6.
        XCTAssertEqual(first.polygon[0].longitude, -123.0, accuracy: 1e-4)
        XCTAssertEqual(first.polygon[0].latitude, 48.7, accuracy: 1e-4)
        XCTAssertEqual(first.polygon[1].longitude, -122.99, accuracy: 1e-4)
        XCTAssertEqual(first.polygon[2].latitude, 48.71, accuracy: 1e-4)
        XCTAssertGreaterThan(first.speedKn, 0, "M2+K1 constituents decoded, so speed isn't the empty-axis zero")

        // bbox cull: a box that contains none of the fixture's elements
        // (they're all west of -122, the whole fixture sits around -123/-122.5)
        // must drop them; nil must not.
        let excluding = FillBBox(minLon: 10, minLat: 10, maxLon: 20, maxLat: 20)
        XCTAssertEqual(field.cells(at: Date(timeIntervalSince1970: 1_787_000_000), in: excluding).count, 0)
        let including = FillBBox(minLon: -126, minLat: 47, maxLon: -122, maxLat: 50)
        XCTAssertEqual(field.cells(at: Date(timeIntervalSince1970: 1_787_000_000), in: including).count, 3)
    }

    // (b) Synthetic golden: fixture element 0 carries one constituent per
    // axis — M2 (u) and K1 (v) — with phases chosen at pack.py's precision
    // boundary (359.9/0.1 deg, see pack.py's own comment on f16's ~0.25 deg
    // worst-case ULP near the 360 wrap). Expected values are derived two
    // ways, neither of which is FillField's own byte decoder:
    //
    //  1. The exact post-round-trip amplitude/phase this test hardcodes below
    //     were read back by `tools/fill-pipeline/test_pack.py`'s independent
    //     `_read_bundle` (a from-scratch struct-unpacker, written without
    //     reference to pack_element, per its own docstring) against this same
    //     fill-fixture.bin — not by FillField. If FillField's f32/f16 decode,
    //     byte offsets, or id→name mapping disagree with that reader, this
    //     test compares against the WRONG station and fails.
    //  2. Those amplitude/phase values are then fed straight into
    //     TideEngine's own `CurrentStation.speeds(from:to:step:)` — the exact
    //     call FillField makes internally, and the exact call every other
    //     station in this app makes (CurrentStation.swift's `cardState`) —
    //     bypassing FillField's element/axis decoding entirely. A bug in
    //     FillField's axis assignment (u/v swapped), hypot/atan2 composition,
    //     or bearing normalization still shows up as a mismatch here, because
    //     this expected value is built from the *same* CurrentStation calls
    //     assembled independently, not by calling `field.cells` a second time.
    //
    // Astronomical arguments (V0+u, nodal f) are never computed in this test
    // or in FillField — both paths hand raw constituents to TideEngine and
    // let it own the astronomy, per the task's authority constraint.
    func testSyntheticGoldenTwoInstants() throws {
        let field = try loadFixture()

        // _read_bundle's decode of fill-fixture.bin's element 0 (all 3
        // elements share these constituents): u = M2 amp 1.2001953125 phase
        // 360.0 (359.9 rounds UP through the f16 wrap to exactly 360, i.e.
        // 0 -- the sharpest case pack.py's precision note describes); v = K1
        // amp 0.60009765625 phase 0.0999755859375.
        let expectedU = HarmonicConstituent(name: "M2", amplitude: 1.2001953125, phase: 360.0)
        let expectedV = HarmonicConstituent(name: "K1", amplitude: 0.60009765625, phase: 0.0999755859375)

        for t in [Date(timeIntervalSince1970: 1_787_227_200),           // 2026-08-20T12:00:00Z
                  Date(timeIntervalSince1970: 1_787_227_200 + 6 * 3600)] {  // +6h — a different M2 phase
            let uStation = CurrentStation(constituents: [expectedU], floodDirection: 0, ebbDirection: 180)
            let vStation = CurrentStation(constituents: [expectedV], floodDirection: 0, ebbDirection: 180)
            let u = try XCTUnwrap(uStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first?.speed)
            let v = try XCTUnwrap(vStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first?.speed)
            let expectedSpeed = hypot(u, v)
            let rawBearing = atan2(u, v) * 180 / .pi
            let expectedBearing = (rawBearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)

            let cell = try XCTUnwrap(field.cells(at: t).first)
            XCTAssertEqual(cell.speedKn, expectedSpeed, accuracy: 1e-9, "at \(t)")
            XCTAssertEqual(cell.bearingDeg, expectedBearing, accuracy: 1e-9, "at \(t)")

            // Convention check, stated independently of the atan2/hypot
            // expression above (which is a verbatim copy of production's, so a
            // wrong-but-consistent formula passes it). The payload's
            // (speed, bearing) must decompose back to the same (u, v)
            // TideEngine produced: east = speed*sin(bearing),
            // north = speed*cos(bearing), bearing measured from true north.
            // An axis swap, a radians/degrees slip, or atan2(v, u) survives
            // both equalities above and fails here.
            let rad = cell.bearingDeg * .pi / 180
            XCTAssertEqual(cell.speedKn * sin(rad), u, accuracy: 1e-9, "east component at \(t)")
            XCTAssertEqual(cell.speedKn * cos(rad), v, accuracy: 1e-9, "north component at \(t)")
        }
    }

    // (c) Real golden: gated on the real bundle existing. fill-salish.bin/.json
    // landed in Task 7 (2.56 MB, 13,168 elements, generated 2026-08-21T17:48:59Z,
    // bin_sha256 9165bc21...127d1 -- see the header JSON for the full digest).
    //
    // Element pinned: shipped-order position 3597 (i.e. `field.cells(at:)[3597]`),
    // picked as the element whose u-axis M2 amplitude is the *median* of all
    // 13,168 survivors (rank 6584 of 13168 by u-axis M2 amplitude, decoded
    // directly from fill-salish.bin with a throwaway script, independent of
    // FillField) -- "mid-strength", not the strongest or weakest cell, and not
    // hand-picked for a convenient answer. Its triangle sits at roughly
    // (-123.04, 48.77), the Haro Strait / Saanich Peninsula approach.
    //
    // This is a REGRESSION pin, not an independent derivation (unlike
    // testSyntheticGoldenTwoInstants's synthetic golden, which is built from
    // constituents fed straight into TideEngine by a path that never calls
    // FillField). There is no third-party published speed for this element to
    // check against -- it's a SSCOFS-fitted grid cell, not a named station --
    // so the expected value below was captured from FillField's own first run
    // against the real bundle and is pinned here to catch any future
    // regression in decode, astronomy wiring, or the fitted constants
    // themselves changing under a bundle refit.
    func testRealBundleGoldenElement() throws {
        guard Bundle.main.url(forResource: "fill-salish", withExtension: "bin") != nil else {
            throw XCTSkip("fill-salish.bin not yet committed — real golden pending")
        }
        let field = try XCTUnwrap(FillField())
        // 2026-09-01T00:00:00Z, a fixed instant with no other significance.
        let t = Date(timeIntervalSince1970: 1_788_220_800)
        let cells = field.cells(at: t)
        XCTAssertEqual(cells.count, 13168, "fill-salish header declares element_count 13168")

        let cell = cells[3597]
        // Captured from FillField's own first run against this exact bundle
        // (xcodebuild test -only-testing:SlackwaterTests/FillFieldTests,
        // iPhone 17 simulator, 2026-08-21) -- see the class comment above.
        // f16 amplitude is ~0.1% relative, phase worst-case ULP ~0.25 deg near
        // the 360 wrap (header["precision"]) -- 1e-6 tolerance is far tighter
        // than that quantization, so this pins the provider's arithmetic
        // (decode, astronomy wiring, hypot/atan2 composition), not just "some
        // value in the right ballpark."
        XCTAssertEqual(cell.speedKn, 1.7572526882345332, accuracy: 1e-6)
        XCTAssertEqual(cell.bearingDeg, 25.541084983909457, accuracy: 1e-6)
    }
}
