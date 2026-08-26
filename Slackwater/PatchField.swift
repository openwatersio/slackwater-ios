// Slackwater — GPL v3. PatchField provider (grown-patches spec §5,
// task-7-brief.md): loads the committed patches bundle
// (tools/patch-pipeline/pack.py, format_version 1) and evaluates each
// patch's ANCHOR harmonic (a bundled NOAA current station or a fitted CHS
// gate) once per call, then scales that single signed speed per cell —
// this is a hand-grown channel model, not an independently-fitted mesh
// element the way FillField's elements are.
//
// Binary layout (little-endian, per cell, offsets from the sidecar JSON
// header's per-patch `offset` + `cell_count` — see pack.py's module
// docstring, the one normative spec this file must agree with):
//   3 x (f32 lon, f32 lat)   # triangle vertices (24 B)
//   f16 scale                # A(anchor)/A(here)
//   f16 bearingDeg            # flood set direction
//   f16 widthM                # local channel width (channel-2 sample extent)
// = 30 bytes/cell, cells concatenated per patch in header order, no gaps.
//
// Anchor resolution: NOAA station ids are bundled provider-prefixed
// ("noaa/PUG1701", see currents.json) while CHS gate ids are already bare
// ("chs-dodd-narrows", see chs-current-gates.json) — the two providers use
// different id shapes on purpose, not an inconsistency to paper over.
// An anchor that can't resolve (unknown id, CHS model not yet fitted on
// device) vends no cells for that patch: absence stays absence, no
// partial/flagged state.
import CoreLocation
import Foundation
import TideEngine

/// One channel-2 oriented flow sample: a cell's centroid + the SIGNED
/// (not `abs`) anchor speed scaled to that cell, plus the cell's physical
/// extent. `bearingDeg` is the channel axis (unsigned, the flood-set
/// direction the geometry carries) — `signedKn`'s sign is what tells a
/// consumer whether flow currently runs with or against it.
struct PatchSample {
    let center: CLLocationCoordinate2D
    let bearingDeg: Double
    let signedKn: Double
    let extentM: Double
}

private struct PatchAnchor: Decodable {
    let provider: String
    let stationId: String

    enum CodingKeys: String, CodingKey {
        case provider
        case stationId = "station_id"
    }
}

private struct PatchEntry: Decodable {
    let anchor: PatchAnchor
    let cellCount: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case anchor
        case cellCount = "cell_count"
        case offset
    }
}

/// The patches bundle header's fields PatchField actually needs. `id` per
/// patch (the pass slug) isn't read — nothing here needs to name a patch,
/// only walk its cells.
private struct PatchHeader: Decodable {
    let formatVersion: Int
    let patches: [PatchEntry]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case patches
    }
}

/// Loads a committed patches bundle (`patches-<region>.bin` + `.json`) and
/// vends per-cell `FillCell`s (for the fill render path) or `PatchSample`s
/// (channel-2 oriented) evaluated at a given instant. `init?` fails on any
/// missing/malformed resource or header — there is no partial-load state.
final class PatchField {
    private let bin: [UInt8]
    private let header: PatchHeader

    /// Loads `<resource>.bin` + `<resource>.json` from the app bundle. Fails
    /// (returns nil) rather than crash when the resource is absent.
    convenience init?(resource: String = "patches-salish") {
        guard let binURL = Bundle.main.url(forResource: resource, withExtension: "bin"),
              let jsonURL = Bundle.main.url(forResource: resource, withExtension: "json"),
              let bin = try? Data(contentsOf: binURL),
              let json = try? Data(contentsOf: jsonURL)
        else { return nil }
        self.init(bin: bin, headerJSON: json)
    }

    /// Explicit-data init — the seam a test uses to load a fixture bundle
    /// without needing it registered as an app-bundle resource. Validates
    /// `formatVersion == 1` and that every patch's declared `offset` lands
    /// exactly where the previous patches' cells end, with the last patch's
    /// end matching `bin.count` exactly — a gap or an overrun is a malformed
    /// bundle, not something to decode defensively around.
    init?(bin: Data, headerJSON: Data) {
        guard let header = try? JSONDecoder().decode(PatchHeader.self, from: headerJSON),
              header.formatVersion == 1
        else { return nil }
        var expectedOffset = 0
        for patch in header.patches {
            guard patch.offset == expectedOffset, patch.cellCount >= 0 else { return nil }
            expectedOffset += patch.cellCount * 30
        }
        guard expectedOffset == bin.count else { return nil }
        self.bin = [UInt8](bin)
        self.header = header
    }

    /// Cell k's triangle + scale/bearing/width, decoded per this file's
    /// header-comment layout, reusing FillField's byte reader.
    private func rawCell(patchOffset: Int, k: Int) -> (verts: [CLLocationCoordinate2D], scale: Double, bearingDeg: Double, widthM: Double) {
        var r = FillByteReader(bytes: bin, pos: patchOffset + k * 30)
        var verts: [CLLocationCoordinate2D] = []
        verts.reserveCapacity(3)
        for _ in 0..<3 {
            let lon = r.f32()
            let lat = r.f32()
            verts.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        let scale = r.f16()
        let bearingDeg = r.f16()
        let widthM = r.f16()
        return (verts, scale, bearingDeg, widthM)
    }

    /// The anchor's signed speed at `date` — the app-wide 1-second-window
    /// idiom (`speeds(from:to:step:)`, same call every station card makes).
    /// NOAA resolves against the bundled catalog; CHS resolves the gate's
    /// on-device fitted model. nil (not 0) on anything unresolved: unknown
    /// id, or a CHS model that hasn't been fitted yet — absence, not a
    /// zero reading.
    private func anchorSpeed(_ anchor: PatchAnchor, at date: Date) -> Double? {
        let record: CurrentStationRecord?
        switch anchor.provider {
        case "noaa":
            record = CurrentStationRecord.all.first { $0.id == "noaa/\(anchor.stationId)" }
        case "chs":
            if let gate = ChsCurrentGateInfo.all.first(where: { $0.id == anchor.stationId }),
               let model = ChsModelStore.loadCurrent(anchor.stationId) {
                record = gate.record(with: model)
            } else {
                record = nil
            }
        default:
            record = nil
        }
        guard let record else { return nil }
        return record.engineStation
            .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed
    }

    private func vector(signedKn: Double, scale: Double, bearingDeg: Double) -> CurrentVector {
        CurrentVector(
            speedKn: abs(signedKn) * scale,
            bearingDeg: signedKn >= 0
                ? bearingDeg
                : (bearingDeg + 180).truncatingRemainder(dividingBy: 360))
    }

    /// The vector at one coordinate, or nil where no resolved patch covers it.
    /// Containment is tested before resolving an anchor so this evaluates only
    /// the matched patch.
    func sample(at coordinate: CLLocationCoordinate2D, time: Date) -> CurrentVector? {
        patches: for patch in header.patches {
            for k in 0..<patch.cellCount {
                let cell = rawCell(patchOffset: patch.offset, k: k)
                guard triangleContains(coordinate, vertices: cell.verts) else { continue }
                guard let signed = anchorSpeed(patch.anchor, at: time) else { continue patches }
                return vector(signedKn: signed, scale: cell.scale, bearingDeg: cell.bearingDeg)
            }
        }
        return nil
    }

    /// All shipped cells at `date`, optionally culled to `bbox` (see
    /// `FillBBox.overlaps(verts:)`). Each patch's anchor is evaluated once
    /// per call, not once per cell. `speedKn = |signed| × scale`;
    /// `bearingDeg` follows `setDegrees(signed:)`'s semantics applied to
    /// the cell's own axis: the cell's stored bearing when the anchor sets
    /// with it, the reciprocal when it sets against it.
    func cells(at date: Date, in bbox: FillBBox? = nil) -> [FillCell] {
        var out: [FillCell] = []
        for patch in header.patches {
            guard let signed = anchorSpeed(patch.anchor, at: date) else { continue }
            for k in 0..<patch.cellCount {
                let cell = rawCell(patchOffset: patch.offset, k: k)
                if let bbox, !bbox.overlaps(verts: cell.verts) { continue }
                let vector = vector(signedKn: signed, scale: cell.scale, bearingDeg: cell.bearingDeg)
                out.append(FillCell(polygon: cell.verts, speedKn: vector.speedKn, bearingDeg: vector.bearingDeg))
            }
        }
        return out
    }

    /// Channel-2 oriented samples at `date`: one per cell, centroid +
    /// SIGNED scaled speed (sign preserved, unlike `cells(at:)`'s `FillCell`
    /// which folds sign into bearing) + the cell's physical width.
    func samples(at date: Date) -> [PatchSample] {
        var out: [PatchSample] = []
        for patch in header.patches {
            guard let signed = anchorSpeed(patch.anchor, at: date) else { continue }
            for k in 0..<patch.cellCount {
                let cell = rawCell(patchOffset: patch.offset, k: k)
                let lat = cell.verts.reduce(0) { $0 + $1.latitude } / 3
                let lon = cell.verts.reduce(0) { $0 + $1.longitude } / 3
                out.append(PatchSample(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    bearingDeg: cell.bearingDeg,
                    signedKn: signed * cell.scale,
                    extentM: cell.widthM))
            }
        }
        return out
    }
}
