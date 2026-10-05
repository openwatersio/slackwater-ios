import Foundation
import SlackwaterKit

struct ChsTidePreview: Codable, Sendable {
    struct Sample: Codable, Sendable {
        let time: Date
        let height: Double
    }

    let stationID: String
    let fetchedAt: Date
    let samples: [Sample]

    var coverage: ClosedRange<Date>? {
        guard samples.count >= 2,
              samples.allSatisfy({ $0.height.isFinite && $0.time.timeIntervalSince1970.isFinite }),
              zip(samples, samples.dropFirst()).allSatisfy({
                  let gap = $1.time.timeIntervalSince($0.time)
                  return gap > 0 && gap <= 1800
              }) else { return nil }
        return samples[0].time...samples[samples.count - 1].time
    }

    func height(at time: Date) -> Double? {
        guard coverage?.contains(time) == true else { return nil }
        let i = segment(at: time)
        let a = samples[i], b = samples[i + 1]
        return a.height + (b.height - a.height) * time.timeIntervalSince(a.time) / b.time.timeIntervalSince(a.time)
    }

    func heights(from: Date, to: Date, step: TimeInterval) -> [TidePoint] {
        guard step > 0, let coverage else { return [] }
        let start = max(from, coverage.lowerBound)
        let end = min(to, coverage.upperBound)
        guard start <= end else { return [] }
        var points: [TidePoint] = []
        var time = Date(timeIntervalSince1970: ceil(start.timeIntervalSince1970 / step) * step)
        while time <= end {
            if let height = height(at: time) { points.append(TidePoint(time: time, height: height)) }
            time = time.addingTimeInterval(step)
        }
        return points
    }

    func rates(from: Date, to: Date, step: TimeInterval) -> [TideRatePoint] {
        heights(from: from, to: to, step: step).map { point in
            let i = segment(at: point.time)
            let a = samples[i], b = samples[i + 1]
            return TideRatePoint(time: point.time, rate: (b.height - a.height) / b.time.timeIntervalSince(a.time) * 3600)
        }
    }

    func extremes(from: Date, to: Date) -> [TideExtreme] {
        guard coverage != nil, samples.count >= 3 else { return [] }
        var result: [TideExtreme] = []
        var i = 1
        while i < samples.count - 1 {
            var end = i
            while end + 1 < samples.count, samples[end + 1].height == samples[i].height { end += 1 }
            guard end + 1 < samples.count else { break }
            let before = samples[i].height - samples[i - 1].height
            let after = samples[end + 1].height - samples[end].height
            if before * after < 0 {
                let time = samples[i].time.addingTimeInterval(samples[end].time.timeIntervalSince(samples[i].time) / 2)
                if time >= from && time <= to {
                    result.append(TideExtreme(time: time, height: samples[i].height, kind: before > 0 ? .high : .low))
                }
            }
            i = end + 1
        }
        return result
    }

    private func segment(at time: Date) -> Int {
        var lo = 0, hi = samples.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time { lo = mid } else { hi = mid }
        }
        return lo
    }
}
