// Slackwater — GPL v3. PatchField provider tests (grown-patches spec §5,
// task-7-brief.md). Transcribed from the brief verbatim.
import XCTest
@testable import Slackwater

final class PatchFieldTests: XCTestCase {
    /// Fixture: one patch, anchor = bundled NOAA station PUG1701, two cells
    /// (scale 0.5 / bearing 90 / width 200; scale 2.0 / bearing 270 / width 300).
    /// `provider` defaults to "noaa" — pass "chs" to exercise the CHS anchor
    /// branch (the bin bytes are identical either way; only the anchor lookup
    /// differs, and an unresolvable anchor never reaches the cell bytes).
    private func fixture(provider: String = "noaa", anchorId: String = "PUG1701") -> (Data, Data) {
        var bin = Data()
        func cell(_ verts: [(Double, Double)], _ scale: Float16, _ bearing: Float16, _ width: Float16) {
            for (lon, lat) in verts {
                withUnsafeBytes(of: Float(lon).bitPattern.littleEndian) { bin.append(contentsOf: $0) }
                withUnsafeBytes(of: Float(lat).bitPattern.littleEndian) { bin.append(contentsOf: $0) }
            }
            for v: Float16 in [scale, bearing, width] {
                withUnsafeBytes(of: v.bitPattern.littleEndian) { bin.append(contentsOf: $0) }
            }
        }
        cell([(-122.64, 48.40), (-122.63, 48.40), (-122.63, 48.41)], 0.5, 90, 200)
        cell([(-122.64, 48.41), (-122.63, 48.41), (-122.63, 48.42)], 2.0, 270, 300)
        let header = """
        {"format_version": 1, "region": "salish", "patches":
         [{"id": "test-pass", "anchor": {"provider": "\(provider)", "station_id": "\(anchorId)"},
           "cell_count": 2, "offset": 0}]}
        """
        return (bin, Data(header.utf8))
    }

    func testCellsScaleAnchorSpeed() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        // Bundled NOAA current-station ids are provider-prefixed ("noaa/PUG1701",
        // see currents.json) — the brief's bare "PUG1701" lookup never matches
        // and throws here regardless of PatchField's own correctness; fixed per
        // this repo's CLAUDE.md ("check it and say so rather than complying").
        let anchor = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/PUG1701" })
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let signed = try XCTUnwrap(anchor.engineStation
            .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed)
        let cells = field.cells(at: date)
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(cells[0].speedKn, abs(signed) * 0.5, accuracy: 1e-9)
        XCTAssertEqual(cells[1].speedKn, abs(signed) * 2.0, accuracy: 1e-9)
        let expected0 = signed >= 0 ? 90.0 : 270.0
        XCTAssertEqual(cells[0].bearingDeg, expected0, accuracy: 0.1)
    }

    func testSampleReturnsMatchedAnchorVector() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        let anchor = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/PUG1701" })
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let signed = try XCTUnwrap(anchor.engineStation
            .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed)
        let coordinate = try XCTUnwrap(field.cells(at: date).first?.polygon.first)
        let vector = try XCTUnwrap(field.sample(at: coordinate, time: date))
        XCTAssertEqual(vector.speedKn, abs(signed) * 0.5, accuracy: 1e-9)
        XCTAssertEqual(vector.bearingDeg, signed >= 0 ? 90 : 270, accuracy: 0.1)
    }

    func testSampleReturnsNilOutsideCoverageOrWithoutAnchor() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        XCTAssertNil(field.sample(at: .init(latitude: 10, longitude: 10), time: Date()))

        let (missingBin, missingHeader) = fixture(anchorId: "NO-SUCH-STATION")
        let missing = try XCTUnwrap(PatchField(bin: missingBin, headerJSON: missingHeader))
        let coordinate = try XCTUnwrap(field.cells(at: Date()).first?.polygon.first)
        XCTAssertNil(missing.sample(at: coordinate, time: Date()))
    }

    func testSampleUsesReciprocalBearingForEbb() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        let anchor = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/PUG1701" })
        let ebbDate = try XCTUnwrap((0...48).lazy.map {
            Date(timeIntervalSince1970: 1_787_000_000 + Double($0 * 1_800))
        }.first { date in
            anchor.engineStation
                .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed ?? 0 < 0
        })
        let coordinate = try XCTUnwrap(field.cells(at: ebbDate).first?.polygon.first)
        let vector = try XCTUnwrap(field.sample(at: coordinate, time: ebbDate))
        XCTAssertEqual(vector.bearingDeg, 270, accuracy: 0.1)
    }

    func testUnresolvableAnchorVendsNothing() throws {
        let (bin, header) = fixture(anchorId: "NO-SUCH-STATION")
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        XCTAssertTrue(field.cells(at: Date()).isEmpty)   // absence stays absence
    }

    // Coverage gate: the "chs" arm of anchorSpeed's provider switch had zero
    // test coverage — a typo in the provider string or an inverted condition
    // there would pass the full suite silently. The cheap, fixture-free case:
    // an unknown CHS gate id short-circuits at ChsCurrentGateInfo.all.first
    // before ChsModelStore.loadCurrent is even called, so no on-disk model
    // fixture is needed to prove absence stays absence through this branch too.
    func testUnresolvableChsAnchorVendsNothing() throws {
        let (bin, header) = fixture(provider: "chs", anchorId: "chs-no-such-gate")
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        XCTAssertTrue(field.cells(at: Date()).isEmpty)
        XCTAssertTrue(field.samples(at: Date()).isEmpty)
    }

    func testBBoxCullUsesTriangleExtent() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        let tiny = FillBBox(minLon: -122.636, minLat: 48.402, maxLon: -122.635, maxLat: 48.403)
        XCTAssertEqual(field.cells(at: Date(), in: tiny).count, 1)  // inside cell 0 only
    }

    func testSamplesCarrySignAndExtent() throws {
        let (bin, header) = fixture()
        let field = try XCTUnwrap(PatchField(bin: bin, headerJSON: header))
        let anchor = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/PUG1701" })
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let signed = try XCTUnwrap(anchor.engineStation
            .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed)
        let samples = field.samples(at: date)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].signedKn, signed * 0.5, accuracy: 1e-9)
        XCTAssertEqual(samples[0].extentM, 200, accuracy: 0.5)
    }

    func testMalformedHeaderFailsInit() {
        let (bin, _) = fixture()
        XCTAssertNil(PatchField(bin: bin, headerJSON: Data("{}".utf8)))
        XCTAssertNil(PatchField(bin: Data(), headerJSON: {
            let (_, h) = fixture(); return h
        }()))  // cell_count*30 != bin length
    }

    func testRealBundleLoads() throws {
        // Activates once patches-salish.bin is committed; mirrors FillFieldTests' skip idiom.
        guard let field = PatchField() else { throw XCTSkip("patches-salish not bundled yet") }
        XCTAssertFalse(field.cells(at: Date(timeIntervalSince1970: 1_787_000_000)).isEmpty)
    }

    // Real golden: tacoma-narrows' first cell (patches-salish.json's
    // "offset": 300, i.e. bin byte 300 -- global cell index 10, since
    // deception-pass ships 0 cells and seymour-narrows' 10 precede it).
    // Decoded directly from Slackwater/Resources/patches-salish.bin with a
    // throwaway `python3 -c "import struct; ..."` script, independent of
    // PatchField: scale 0.80517578125 (f16-exact), bearingDeg 157.0,
    // widthM 1625.0. pack.py's docstring: the two triangles of one section
    // interval carry identical scale/bearing/width, so bin index 11 (the
    // interval's second triangle) decodes to the same three values -- not a
    // coincidence to be surprised by if this pin is ever re-derived.
    //
    // This is a REGRESSION pin against this generation (the FillFieldTests
    // real-bundle golden pattern), not an independent derivation -- refit
    // invalidates deliberately. `cells(at:)` folds the anchor's sign into
    // `bearingDeg`, so the scale-level pins are checked through
    // `samples(at:)` instead, whose `bearingDeg` is always the cell's own
    // (unsigned) channel axis and whose `extentM` is `widthM` verbatim --
    // matching on both pinned values finds this exact cell without needing
    // a fragile array-index assumption about which anchors resolve in a
    // given test environment. `signedKn` is checked against
    // `anchorSigned * pinnedScale`, computed from the PUG1527 anchor record
    // in-test at a fixed instant (the FillFieldTests golden pattern) rather
    // than pinning a numeric literal for it, since deriving that literal
    // would mean re-deriving the harmonic model too.
    func testRealBundleGoldenCellTacoma() throws {
        guard let field = PatchField() else { throw XCTSkip("patches-salish not bundled yet") }
        let anchor = try XCTUnwrap(CurrentStationRecord.all.first { $0.id == "noaa/PUG1527" })
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let signed = try XCTUnwrap(anchor.engineStation
            .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed)

        let pinnedScale = 0.80517578125
        let pinnedBearing = 157.0
        let pinnedWidth = 1625.0

        let cell = try XCTUnwrap(field.samples(at: date).first {
            $0.bearingDeg == pinnedBearing && $0.extentM == pinnedWidth
        })
        XCTAssertEqual(cell.signedKn, signed * pinnedScale, accuracy: 1e-9)
        XCTAssertEqual(cell.bearingDeg, pinnedBearing, accuracy: 1e-9)
        XCTAssertEqual(cell.extentM, pinnedWidth, accuracy: 1e-9)
    }
}
