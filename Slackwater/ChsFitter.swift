// Slackwater — GPL v3. Native fitting for tides and projected currents.
import Foundation
import SlackwaterKit

struct ChsFitResult: Decodable {
    let fitMs: Double
    let offset: Double
    let rms: Double
    let constituents: [Con]
}

struct ChsFitter {
    /// The engine's shared CHS tide recipe.
    static let tideBasis = ChsTideFit.basis
    static let currentBasis = ChsCurrentFit.basis

    func fit(samples: [ChsSample], basis: [String]) async throws -> ChsFitResult {
        try Task.checkCancellation()
        let start = ContinuousClock.now
        do {
            let result = try SlackwaterKit.fit(samples: samples.map {
                HarmonicSample(time: Date(timeIntervalSince1970: $0.t / 1000), value: $0.v)
            }, constituents: basis)
            try Task.checkCancellation()
            let elapsed = start.duration(to: .now).components
            return ChsFitResult(
                fitMs: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
                offset: result.offset, rms: result.rms,
                constituents: result.constituents.map {
                    Con(name: $0.name, amplitude: $0.amplitude, phase: $0.phase)
                })
        } catch {
            if error is CancellationError { throw error }
            throw ChsError.permanent("Harmonic fit failed: \(error)")
        }
    }
}
