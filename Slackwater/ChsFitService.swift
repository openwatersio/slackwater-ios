// Slackwater — GPL v3. First-run connected fetch → fit → stored model for the
// Canadian Salish tide ports (milestones spec M3). No region UX — Salish
// auto-fits in the background; each station lands as its fit completes.
//
// The M0 spike's carry-forwards, honoured here:
//   - JSContext.exceptionHandler is set (JS errors are silent without it)
//   - no fetch inside JSCore — IWLS via URLSession, JSON strings + epoch-ms bridge
//   - BASIS + SA/SSA constituent list (in chs-glue.js)
//   - wlp is 1-min native → decimated to 15-min before bridging; 7-day request
//     cap; queries by resolved Mongo id, never station code
import Foundation
import JavaScriptCore

/// Where a CHS station stands. Stored models load synchronously at init, so a
/// previously fitted station is `.fitted` before the first frame — offline.
enum ChsState {
    case pending      // no model, not currently fitting (no network yet / failed)
    case fitting
    case fitted(TideStationRecord)
}

@MainActor
final class ChsFitService: ObservableObject {
    static let shared = ChsFitService()

    @Published private(set) var states: [String: ChsState] = [:]

    /// True once launched with `-networkKillSwitch` (UI tests' honest
    /// airplane-mode stand-in: every IWLS request throws before the socket).
    let networkDisabled = CommandLine.arguments.contains("-networkKillSwitch")

    private var started = false

    private init() {
        ChsModelStore.resetIfRequested()
        for info in ChsStationInfo.all {
            if let model = ChsModelStore.load(info.id) {
                states[info.id] = .fitted(info.record(with: model))
            } else {
                states[info.id] = .pending
            }
        }
    }

    func state(_ id: String) -> ChsState { states[id] ?? .pending }

    /// Fit every pending station, Victoria first (home water lands fastest).
    /// Partial failure is fine: whatever fit is stored; the rest stay pending
    /// and retry on the next connected launch.
    func fitPendingIfNeeded() {
        guard !started, !networkDisabled else { return }
        started = true
        let pending = ChsStationInfo.all
            .filter { if case .fitted = state($0.id) { return false } else { return true } }
            .sorted { ($0.id == ChsStationInfo.victoriaID ? 0 : 1, $0.name) < ($1.id == ChsStationInfo.victoriaID ? 0 : 1, $1.name) }
        guard !pending.isEmpty else { return }

        Task.detached(priority: .utility) {
            let fetcher = IwlsFetcher()
            let fitter = ChsFitter()
            guard let list = try? await fetcher.stationList() else { return }  // offline: stay pending
            for info in pending {
                await MainActor.run { self.states[info.id] = .fitting }
                do {
                    let model = try await Self.fit(info, list: list, fetcher: fetcher, fitter: fitter)
                    try ChsModelStore.save(model)
                    await MainActor.run { self.states[info.id] = .fitted(info.record(with: model)) }
                } catch {
                    // ponytail: no retry ladder — next connected launch retries.
                    await MainActor.run { self.states[info.id] = .pending }
                }
            }
        }
    }

    /// 60 d @ 15 min ending yesterday — the window the M0 spike validated.
    private static func fit(_ info: ChsStationInfo, list: [IwlsStation],
                            fetcher: IwlsFetcher, fitter: ChsFitter) async throws -> ChsFittedModel {
        let station = try resolve(info, in: list)
        let end = Calendar(identifier: .gregorian).startOfDay(for: .now)
        let start = end.addingTimeInterval(-60 * 86_400)
        let samples = try await fetcher.wlp(stationID: station.id, from: start, to: end)
        let fit = try await fitter.fit(samples: samples)
        print("CHS fit \(info.id): \(samples.count) samples, \(Int(fit.fitMs)) ms (interpreted, no JIT), rms \(String(format: "%.1f", fit.rms * 100)) cm")
        return ChsFittedModel(
            stationID: info.id, iwlsID: station.id, iwlsName: station.officialName,
            fittedAt: .now, fitStartMs: start.timeIntervalSince1970 * 1000,
            fitEndMs: end.timeIntervalSince1970 * 1000,
            offset: fit.offset, rms: fit.rms,
            constituents: fit.constituents.map { .init(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) })
    }

    /// Position is the match key, never name (web chs/resolve.ts): nearest wlp
    /// station within tolerance, else throw — a silent mis-bind would put the
    /// wrong water under a trusted name.
    static let resolveToleranceKm = 3.0

    static func resolve(_ info: ChsStationInfo, in list: [IwlsStation]) throws -> IwlsStation {
        let candidates = list.filter { $0.timeSeries.contains { $0.code == "wlp" } }
        guard let best = candidates.min(by: {
            distanceKm(info.latitude, info.longitude, $0.latitude, $0.longitude) <
            distanceKm(info.latitude, info.longitude, $1.latitude, $1.longitude)
        }) else { throw ChsError.noStations }
        let km = distanceKm(info.latitude, info.longitude, best.latitude, best.longitude)
        guard km <= resolveToleranceKm else { throw ChsError.noStationWithinTolerance(info.name, best.officialName, km) }
        return best
    }
}

enum ChsError: Error {
    case networkDisabled
    case noStations
    case noStationWithinTolerance(String, String, Double)
    case badResponse(Int)
    case jsError(String)
}

// MARK: - IWLS client (Swift/URLSession — never JSCore)

struct IwlsStation: Decodable {
    struct Series: Decodable { let code: String }
    let id: String
    let officialName: String
    let latitude: Double
    let longitude: Double
    let timeSeries: [Series]
}

struct IwlsSample: Decodable { let eventDate: String; let value: Double }

/// A decimated sample as bridged to JS: epoch-ms + metres.
struct ChsSample: Encodable { let t: Double; let v: Double }

/// Polite serial IWLS client: one request at a time, 2.5 s apart (~24/min,
/// safely under the documented 3/s and 30/min caps), 7-day chunks.
final class IwlsFetcher {
    static let base = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
    private let killSwitch = CommandLine.arguments.contains("-networkKillSwitch")
    private var lastRequest = Date.distantPast

    private func get(_ path: String) async throws -> Data {
        guard !killSwitch else { throw ChsError.networkDisabled }
        let wait = 2.5 - Date.now.timeIntervalSince(lastRequest)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        lastRequest = .now
        let (data, response) = try await URLSession.shared.data(from: URL(string: Self.base + path)!)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ChsError.badResponse(code) }
        return data
    }

    func stationList() async throws -> [IwlsStation] {
        try JSONDecoder().decode([IwlsStation].self, from: try await get("/stations"))
    }

    /// wlp for [from, to), 7-day chunks, decimated from 1-min to 15-min.
    func wlp(stationID: String, from: Date, to: Date) async throws -> [ChsSample] {
        let iso = ISO8601DateFormatter()
        var out: [ChsSample] = []
        var t = from
        while t < to {
            let next = min(t.addingTimeInterval(7 * 86_400), to)
            let path = "/stations/\(stationID)/data?time-series-code=wlp" +
                "&from=\(iso.string(from: t))&to=\(iso.string(from: next))"
            let chunk = try JSONDecoder().decode([IwlsSample].self, from: try await get(path))
            for s in chunk {
                guard let date = iso.date(from: s.eventDate) else { continue }
                let ms = date.timeIntervalSince1970 * 1000
                // 1-min native → keep the 15-min grid; chunk edges can repeat a point.
                if ms.truncatingRemainder(dividingBy: 900_000) == 0, out.last?.t != ms {
                    out.append(ChsSample(t: ms, v: s.value))
                }
            }
            t = next
        }
        return out
    }
}

// MARK: - JSCore fitter

struct ChsFitResult: Decodable {
    struct Con: Decodable { let name: String; let amplitude: Double; let phase: Double }
    let fitMs: Double
    let offset: Double
    let rms: Double
    let constituents: [Con]
    let unseparable: [String]
}

/// Runs chs-bundle.js + chs-glue.js in JavaScriptCore, off the main thread.
/// One context, reused across stations within a fit run.
final class ChsFitter {
    private var context: JSContext?
    private var jsError: String?

    private func makeContext() throws -> JSContext {
        if let context { return context }
        let ctx = JSContext()!
        ctx.exceptionHandler = { [weak self] _, exc in self?.jsError = exc?.toString() }
        // JSCore has no console; shim it so a stray log can't crash the fit.
        ctx.evaluateScript("var console = {log:function(){},warn:function(){},error:function(){},info:function(){},debug:function(){}};")
        for name in ["chs-bundle", "chs-glue"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js") else {
                throw ChsError.jsError("\(name).js missing from bundle")
            }
            ctx.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            if let e = jsError { throw ChsError.jsError("\(name).js: \(e)") }
        }
        context = ctx
        return ctx
    }

    func fit(samples: [ChsSample]) async throws -> ChsFitResult {
        let json = String(data: try JSONEncoder().encode(samples), encoding: .utf8)!
        let ctx = try makeContext()
        jsError = nil
        guard let out = ctx.objectForKeyedSubscript("fitTides")?.call(withArguments: [json]),
              jsError == nil, let str = out.toString() else {
            throw ChsError.jsError(jsError ?? "fitTides returned nothing")
        }
        return try JSONDecoder().decode(ChsFitResult.self, from: Data(str.utf8))
    }
}

// MARK: - Geo

func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6371.0, d = Double.pi / 180
    let dLat = (lat2 - lat1) * d, dLon = (lon2 - lon1) * d
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * d) * cos(lat2 * d) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * atan2(sqrt(a), sqrt(1 - a))
}
