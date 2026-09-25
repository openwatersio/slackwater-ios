// Slackwater — GPL v3. Native fitting for tides and projected currents.
import Foundation
import Neaps

struct ChsFitResult: Decodable {
    let fitMs: Double
    let offset: Double
    let rms: Double
    let constituents: [Con]
}

struct ChsFitter {
    // SA/SSA absorb Z0 in a 60-day fit and worsen held-out heights.
    // Preserve the validated basis for both provisional and full fits.
    static let basis = [
        "M2", "S2", "N2", "K2", "K1", "O1", "P1", "Q1",
        "M4", "MS4", "MN4", "2N2", "MU2", "NU2", "L2", "T2",
        "J1", "MM", "MSF", "MF", "M6", "S4", "M3",
    ]

    func fit(samples: [ChsSample]) async throws -> ChsFitResult {
        let start = ContinuousClock.now
        do {
            let result = try Neaps.fit(samples: samples.map {
                HarmonicSample(time: Date(timeIntervalSince1970: $0.t / 1000), value: $0.v)
            }, constituents: Self.basis)
            let elapsed = start.duration(to: .now).components
            return ChsFitResult(
                fitMs: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
                offset: result.offset, rms: result.rms,
                constituents: result.constituents.map {
                    Con(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
                })
        } catch {
            throw ChsError.permanent("Harmonic fit failed: \(error)")
        }
    }
}
