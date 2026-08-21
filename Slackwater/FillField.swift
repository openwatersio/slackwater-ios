// Slackwater — GPL v3. FillField provider (fill-phase-b-design.md §4): loads
// the committed fill bundle (tools/fill-pipeline/pack.py, format_version 1)
// and evaluates each element's u/v at a given instant via TideEngine's own
// constituent machinery — the astronomical arguments (V0+u, nodal f) are
// never re-derived here, only reconstructed HarmonicConstituents handed to
// TideEngine, same as every other station in this app (CurrentStation.swift's
// `engineStation`, `station.speeds(from:to:step:)`).
//
// Binary layout (little-endian, per element, offsets from the sidecar JSON
// header — see pack.py's module docstring, the one normative spec this file
// must agree with):
//   u8 vert_count(=3), 3 x (f32 lon, f32 lat)
//   u8 nu, nu x (u8 constituent_id, f16 amplitude, f16 phase)   -- u axis
//   u8 nv, nv x (same)                                          -- v axis
//
// No timing semantics, no green: this vends geometry + magnitude + bearing
// only. Absence stays absence — an element not in the bundle is never
// vended (nothing here re-synthesizes a masked/no-data cell).
import CoreLocation
import Foundation
import TideEngine

/// One fill cell: a triangle + the current there at the instant `cells(at:)`
/// was asked about. Payload is deliberately just polygon+speed+bearing — the
/// render layer (#57 session) owns ramp/edge treatment on top of this.
struct FillCell {
    let polygon: [CLLocationCoordinate2D]
    let speedKn: Double
    let bearingDeg: Double
}

/// Lon/lat bounding box for a `cells(at:in:)` visibility filter. Field order
/// mirrors the header's own `bbox` (minLon, minLat, maxLon, maxLat) — no
/// MapKit/MapLibre type fits here (this app draws with MapLibre, not MapKit,
/// and the seam's consumer hasn't landed yet), so this is deliberately the
/// smallest thing that lets a caller cull off-screen elements.
struct FillBBox {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    func contains(lat: Double, lon: Double) -> Bool {
        lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat
    }
}

/// The fill bundle header's fields FillField actually needs. JSONDecoder
/// ignores the rest (corpus_window, floors, precision, sha256s, ...) —
/// provenance metadata this reader doesn't consume.
private struct FillHeader: Decodable {
    let formatVersion: Int
    let elementCount: Int
    let constituents: [String: String]
    let offsets: [Int]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case elementCount = "element_count"
        case constituents
        case offsets
    }
}

/// Reads bytes at a moving cursor over the packed element bytes, per the
/// layout in this file's header comment. Not `Data`-generic on purpose —
/// FillField holds the whole bin as `[UInt8]` once at load so every element
/// read is a plain array index, not a `Data` subscript through its indices.
private struct FillByteReader {
    let bytes: [UInt8]
    var pos: Int

    mutating func u8() -> UInt8 {
        defer { pos += 1 }
        return bytes[pos]
    }

    mutating func f32() -> Double {
        let b0 = UInt32(bytes[pos]), b1 = UInt32(bytes[pos + 1])
        let b2 = UInt32(bytes[pos + 2]), b3 = UInt32(bytes[pos + 3])
        let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        pos += 4
        return Double(Float(bitPattern: bits))
    }

    mutating func f16() -> Double {
        let b0 = UInt16(bytes[pos]), b1 = UInt16(bytes[pos + 1])
        let bits = b0 | (b1 << 8)
        pos += 2
        return Double(Float16(bitPattern: bits))
    }
}

/// Loads a committed fill bundle (`fill-<region>.bin` + `.json`) and vends
/// per-element cells evaluated at a given instant. `init?` fails on any
/// missing/malformed resource or header — there is no partial-load state.
final class FillField {
    private let bin: [UInt8]
    private let header: FillHeader
    private let idToName: [Int: String]

    /// Loads `<resource>.bin` + `<resource>.json` from the app bundle. Fails
    /// (returns nil) rather than crash when the resource is absent — true
    /// today for `fill-salish` (Task 4/7's bundle hasn't landed yet).
    convenience init?(resource: String = "fill-salish") {
        guard let binURL = Bundle.main.url(forResource: resource, withExtension: "bin"),
              let jsonURL = Bundle.main.url(forResource: resource, withExtension: "json"),
              let bin = try? Data(contentsOf: binURL),
              let json = try? Data(contentsOf: jsonURL)
        else { return nil }
        self.init(bin: bin, headerJSON: json)
    }

    /// Explicit-data init — the seam a test uses to load a fixture bundle
    /// without needing it registered as an app-bundle resource.
    init?(bin: Data, headerJSON: Data) {
        guard let header = try? JSONDecoder().decode(FillHeader.self, from: headerJSON),
              header.formatVersion == 1,
              header.offsets.count == header.elementCount + 1,
              header.offsets.last == bin.count
        else { return nil }
        self.bin = [UInt8](bin)
        self.header = header
        self.idToName = Dictionary(uniqueKeysWithValues: header.constituents.compactMap { key, name in
            Int(key).map { ($0, name) }
        })
    }

    /// Element k's triangle + kept u/v constituents, decoded per this file's
    /// header-comment layout. nil on a malformed chunk (never expected from
    /// a bundle pack.py produced, but decode defensively rather than trap).
    private func element(at k: Int) -> (verts: [CLLocationCoordinate2D], u: [HarmonicConstituent], v: [HarmonicConstituent])? {
        var r = FillByteReader(bytes: bin, pos: header.offsets[k])
        guard r.u8() == 3 else { return nil }
        var verts: [CLLocationCoordinate2D] = []
        verts.reserveCapacity(3)
        for _ in 0..<3 {
            let lon = r.f32()
            let lat = r.f32()
            verts.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        func axis() -> [HarmonicConstituent] {
            let n = r.u8()
            var out: [HarmonicConstituent] = []
            out.reserveCapacity(Int(n))
            for _ in 0..<n {
                let id = r.u8()
                let amplitude = r.f16()
                let phase = r.f16()
                if let name = idToName[Int(id)] {
                    out.append(HarmonicConstituent(name: name, amplitude: amplitude, phase: phase))
                }
            }
            return out
        }
        return (verts, axis(), axis())
    }

    /// A single constituent axis evaluated at `date` — same call shape as
    /// every other station in the app (e.g. CurrentStation.swift's
    /// `cardState`): `speeds(from:to:step:)` snapped to a 1s timeline and
    /// the first (only) sample taken.
    private func evaluate(_ constituents: [HarmonicConstituent], at date: Date) -> Double {
        let station = CurrentStation(constituents: constituents, floodDirection: 0, ebbDirection: 180)
        return station.speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed ?? 0
    }

    /// All shipped cells at `date`, optionally culled to `bbox` (any vertex
    /// inside counts — a cheap over-inclusive filter, fine for a visibility
    /// cull). Bearing is `atan2(u, v)` degrees true, normalized to [0, 360) —
    /// the direction the current sets toward, not the compass heading of the
    /// flow's origin.
    func cells(at date: Date, in bbox: FillBBox? = nil) -> [FillCell] {
        var out: [FillCell] = []
        out.reserveCapacity(header.elementCount)
        for k in 0..<header.elementCount {
            guard let el = element(at: k) else { continue }
            if let bbox, !el.verts.contains(where: { bbox.contains(lat: $0.latitude, lon: $0.longitude) }) {
                continue
            }
            let u = evaluate(el.u, at: date)
            let v = evaluate(el.v, at: date)
            let speed = hypot(u, v)
            let rawBearing = atan2(u, v) * 180 / .pi
            let bearing = (rawBearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            out.append(FillCell(polygon: el.verts, speedKn: speed, bearingDeg: bearing))
        }
        return out
    }
}
