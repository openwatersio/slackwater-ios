// Slackwater — GPL v3. M3 exit check A: fitted predictions vs live IWLS over a
// held-out window, the M0 spike's methodology (60 d @ 15 min fit; 7-day
// validation window 4 weeks after fit end; RMSE on the 15-min grid vs wlp;
// extreme timing vs wlp-hilo, classified against neighbours, matched by kind
// within 180 min). Fit runs in JSCore via the app's committed chs-bundle.js +
// chs-glue.js; prediction runs in TideEngine — exactly the shipping path.
//
//   swift run fit-validation <name> <lat> <lon> [cacheDir]            # tide (wlp)
//   swift run fit-validation --current <name> <lat> <lon> [cacheDir]  # current gate (wcsp1)
//
// Current mode (M47): fetch wcsp1 (speed) + wcdp1 (direction) for 210 d ending
// today 00Z, project onto the CHS flood axis (speed·cos(dir−floodDirection) —
// the chs-constituents pipeline's own projection), fit BOTH the full 210 d and
// the trailing 60 d in JSCore, predict the held-out window (+28..+35 d) with
// TideEngine's CurrentStation (the shipping synthesis), and score slack/extremum
// timing + peak speed against CHS's own published wcp1-events.
//
// Fetched IWLS data is cached under cacheDir (default /tmp/fit-validation) and
// deliberately never written into the repo — it is CHS data, the user's own.
import Foundation
import JavaScriptCore
import TideEngine

let isCurrentMode = CommandLine.arguments.contains("--current")
let args = CommandLine.arguments.filter { $0 != "--current" }
guard args.count >= 4, let lat = Double(args[2]), let lon = Double(args[3]) else {
    print("usage: fit-validation [--current] <name> <lat> <lon> [cacheDir]")
    exit(2)
}
let name = args[1]
let cacheDir = URL(fileURLWithPath: args.count > 4 ? args[4] : "/tmp/fit-validation")
try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

let base = "https://api-iwls.dfo-mpo.gc.ca/api/v1"
let iso = ISO8601DateFormatter()

func cachedGet(_ path: String, key: String) throws -> Data {
    let file = cacheDir.appendingPathComponent(key)
    if let data = try? Data(contentsOf: file) { return data }
    let sem = DispatchSemaphore(value: 0)
    var result: Data?
    var status = 0
    URLSession.shared.dataTask(with: URL(string: base + path)!) { data, resp, _ in
        result = data
        status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        sem.signal()
    }.resume()
    sem.wait()
    guard status == 200, let data = result else { fatalError("IWLS \(status) for \(path)") }
    try data.write(to: file)
    Thread.sleep(forTimeInterval: 2.5)  // polite: same spacing as the app
    return data
}

// --- resolve by position (never name), nearest wlp station within 3 km ---
struct IwlsStation: Decodable {
    struct Series: Decodable { let code: String }
    let id: String, officialName: String, latitude: Double, longitude: Double
    let timeSeries: [Series]
}
func km(_ la1: Double, _ lo1: Double, _ la2: Double, _ lo2: Double) -> Double {
    let d = Double.pi / 180, dLat = (la2 - la1) * d, dLon = (lo2 - lo1) * d
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(la1 * d) * cos(la2 * d) * sin(dLon / 2) * sin(dLon / 2)
    return 12742 * atan2(sqrt(a), sqrt(1 - a))
}
let resolveSeries = isCurrentMode ? "wcsp1" : "wlp"
let list = try JSONDecoder().decode([IwlsStation].self, from: cachedGet("/stations", key: "stations.json"))
let seriesStations = list.filter { st in st.timeSeries.contains { $0.code == resolveSeries } }
let station = seriesStations.min { km(lat, lon, $0.latitude, $0.longitude) < km(lat, lon, $1.latitude, $1.longitude) }!
let distance = km(lat, lon, station.latitude, station.longitude)
guard distance <= 3.0 else { fatalError("no \(resolveSeries) station within 3 km of \(name) (nearest \(station.officialName) at \(distance) km)") }
print("resolved: \(name) -> \(station.officialName) (\(station.id)), \(String(format: "%.2f", distance)) km")

// --- windows: fit 60 d ending today 00Z; validate +28 d .. +35 d ---
struct IwlsSample: Decodable { let eventDate: String; let value: Double }
let dayS = 86_400.0
let today = floor(Date().timeIntervalSince1970 / dayS) * dayS
let fitStart = Date(timeIntervalSince1970: today - 60 * dayS)
let fitEnd = Date(timeIntervalSince1970: today)
let valStart = Date(timeIntervalSince1970: today + 28 * dayS)
let valEnd = Date(timeIntervalSince1970: today + 35 * dayS)

func fetchSeries(_ code: String, _ from: Date, _ to: Date) throws -> [(t: Double, v: Double)] {
    var out: [(Double, Double)] = []
    var t = from
    while t < to {
        let next = min(t.addingTimeInterval(7 * dayS), to)
        let path = "/stations/\(station.id)/data?time-series-code=\(code)" +
            "&from=\(iso.string(from: t))&to=\(iso.string(from: next))"
        let key = "\(station.id)_\(code)_\(Int(t.timeIntervalSince1970)).json"
        let chunk = try JSONDecoder().decode([IwlsSample].self, from: cachedGet(path, key: key))
        for s in chunk {
            guard let d = iso.date(from: s.eventDate) else { continue }
            let ms = d.timeIntervalSince1970 * 1000
            if out.last?.0 != ms { out.append((ms, s.value)) }
        }
        t = next
    }
    return out
}
let quarter = { (s: [(t: Double, v: Double)]) in s.filter { $0.t.truncatingRemainder(dividingBy: 900_000) == 0 } }

// The app's exact JS artifacts (shared by both modes).
let resources = URL(fileURLWithPath: #filePath) // tools/FitValidation/Sources/fit-validation/main.swift
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Slackwater/Resources")

// MARK: - Current-gate mode (M47)

/// The bar, set before scoring. Slack is the safety quantity — a gate is
/// transited AT slack — so it gets the tightest numbers: median ≤ 15 min and
/// worst ≤ 30 min vs CHS's own published events, tighter than the engine's
/// ±20-min maxima bar (chs-online-design §6a: unvalidated fitted slack times
/// are "wrong water under a trusted name"). Extremum timing median ≤ 20 min
/// (the engine's established maxima bar, = chs-constituents' "medium" tier),
/// peak-speed median error ≤ 0.5 kn (the number a skipper reads off the peak),
/// every observed slack matched within 180 min (an unmatched slack is a worse
/// error than any it could report), and no reversed flood axis (wrongSign ≥ 60%
/// of extrema — systematic disagreement, chs-constituents' quarantine test).
let SLACK_MEDIAN_MAX = 15.0, SLACK_WORST_MAX = 30.0
let EXTREMA_MEDIAN_MAX = 20.0, SPEED_MEDIAN_MAX = 0.5
/// Observed extrema weaker than this are skipped for timing/speed scoring
/// (chs-constituents `significant`): the "peak" of a 0.3 kn drift is noise.
let SIGNIFICANT_KN = 0.75
/// Same-kind events further apart than this are different cycles, not a match.
let MATCH_WINDOW_MIN = 180.0

let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

struct IwlsEvent: Decodable { let eventDate: String; let qualifier: String; let value: Double }
struct StationMeta: Decodable { let floodDirection: Double?; let ebbDirection: Double? }
struct FitOut: Decodable {
    struct Con: Decodable { let name: String; let amplitude: Double; let phase: Double }
    let fitMs: Double
    let offset: Double
    let rms: Double
    let constituents: [Con]
    let unseparable: [String]
}

func med(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func runCurrentValidation() throws -> Int32 {
    // Flood/ebb axis from CHS metadata — required to project wcsp1/wcdp1 into
    // a signed along-channel velocity. No axis, no fit.
    let meta = try JSONDecoder().decode(StationMeta.self,
        from: cachedGet("/stations/\(station.id)/metadata", key: "\(station.id)_metadata.json"))
    guard let flood = meta.floodDirection, let ebb = meta.ebbDirection else {
        print("FAIL-FOR-FITTING: \(name) — IWLS metadata has no flood/ebb axis")
        return 3
    }

    // 210 d of wcsp1+wcdp1 ending today 00Z; the 60 d fit is the trailing slice
    // of the same series (one fetch, two windows).
    let fitStart210 = Date(timeIntervalSince1970: today - 210 * dayS)
    let fitEnd = Date(timeIntervalSince1970: today)
    let speeds = try fetchSeries("wcsp1", fitStart210, fitEnd)
    let dirs = try fetchSeries("wcdp1", fitStart210, fitEnd)
    let dirAt = Dictionary(dirs.map { ($0.t, $0.v) }, uniquingKeysWith: { a, _ in a })
    let d2r = Double.pi / 180
    // ponytail: projection = chs-constituents fetchProjectedSeries, one line.
    let projected: [(t: Double, v: Double)] = speeds.compactMap { s in
        guard let dir = dirAt[s.t] else { return nil }
        return (s.t, s.v * cos((dir - flood) * d2r))
    }
    let cut60 = (today - 60 * dayS) * 1000
    let projected60 = projected.filter { $0.t >= cut60 }
    print("samples: \(projected.count) @ 210 d (\(projected60.count) in trailing 60 d), axis flood \(Int(flood))° / ebb \(Int(ebb))°")

    // Held-out CHS events, +28..+35 d (exactly one 7-day request).
    let evData = try cachedGet(
        "/stations/\(station.id)/data?time-series-code=wcp1-events" +
        "&from=\(iso.string(from: valStart))&to=\(iso.string(from: valEnd))",
        key: "\(station.id)_wcp1-events_\(Int(valStart.timeIntervalSince1970)).json")
    let rawEvents = try JSONDecoder().decode([IwlsEvent].self, from: evData)
    struct Obs { let time: Date; let kind: CurrentEventKind; let speed: Double }
    let observed: [Obs] = rawEvents.compactMap { e in
        guard let t = iso.date(from: e.eventDate) ?? isoFrac.date(from: e.eventDate) else { return nil }
        switch e.qualifier {
        case "SLACK": return Obs(time: t, kind: .slack, speed: 0)
        case "EXTREMA_FLOOD": return Obs(time: t, kind: .maxFlood, speed: e.value)
        case "EXTREMA_EBB": return Obs(time: t, kind: .maxEbb, speed: -e.value)
        default: return nil
        }
    }
    guard !observed.isEmpty else {
        print("FAIL-FOR-FITTING: \(name) — IWLS serves no wcp1-events for the validation window")
        return 3
    }

    // The app's exact JS artifacts, same as the tide path.
    let ctx = JSContext()!
    var jsErr: String?
    ctx.exceptionHandler = { _, exc in jsErr = exc?.toString() }
    ctx.evaluateScript("var console = {log:function(){},warn:function(){},error:function(){},info:function(){},debug:function(){}};")
    for file in ["chs-bundle.js", "chs-glue.js"] {
        ctx.evaluateScript(try String(contentsOf: resources.appendingPathComponent(file), encoding: .utf8))
        if let e = jsErr { fatalError("\(file): \(e)") }
    }

    let reportsDir = cacheDir.appendingPathComponent("reports")
    try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
    let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")

    var exitCode: Int32 = 1
    for (label, samples) in [("210d", projected), ("60d", projected60)] {
        let samplesJson = "[" + samples.map { "{\"t\":\($0.t),\"v\":\($0.v)}" }.joined(separator: ",") + "]"
        // Node-control parity: the exact bytes handed to JSCore.
        try samplesJson.write(to: reportsDir.appendingPathComponent("\(slug)-\(label)-samples.json"),
                              atomically: true, encoding: .utf8)
        jsErr = nil
        guard let out = ctx.objectForKeyedSubscript("fitTides")?.call(withArguments: [samplesJson]), jsErr == nil else {
            fatalError("fitTides threw: \(jsErr ?? "?")")
        }
        let fit = try JSONDecoder().decode(FitOut.self, from: Data(out.toString()!.utf8))
        try out.toString()!.write(to: reportsDir.appendingPathComponent("\(slug)-\(label)-fit.json"),
                                  atomically: true, encoding: .utf8)

        let engine = CurrentStation(
            constituents: fit.constituents.map { HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) },
            floodDirection: flood, ebbDirection: ebb, offset: fit.offset)
        let predicted = engine.events(from: valStart.addingTimeInterval(-dayS / 2),
                                      to: valEnd.addingTimeInterval(dayS / 2))

        var slackDeltas: [Double] = [], extremaDeltas: [Double] = [], speedErrs: [Double] = []
        var slackUnmatched = 0, wrongSign = 0, extremaTotal = 0
        for obs in observed {
            if obs.kind == .slack {
                let best = predicted.filter { $0.kind == .slack }
                    .map { abs($0.time.timeIntervalSince(obs.time)) / 60 }.min() ?? .infinity
                if best <= MATCH_WINDOW_MIN { slackDeltas.append(best) } else { slackUnmatched += 1 }
            } else {
                extremaTotal += 1
                // Direction: sign of the modelled velocity at CHS's own extremum
                // instant — the only sound flip test (chs-constituents validate.ts).
                let v = engine.speeds(from: obs.time, to: obs.time.addingTimeInterval(60), step: 60).first?.speed ?? 0
                if (obs.kind == .maxFlood && v < 0) || (obs.kind == .maxEbb && v > 0) { wrongSign += 1 }
                guard abs(obs.speed) >= SIGNIFICANT_KN else { continue }
                var best: (dt: Double, speed: Double)?
                for p in predicted where p.kind == obs.kind {
                    let dt = abs(p.time.timeIntervalSince(obs.time)) / 60
                    if best == nil || dt < best!.dt { best = (dt, p.speed) }
                }
                if let b = best, b.dt <= MATCH_WINDOW_MIN {
                    extremaDeltas.append(b.dt)
                    speedErrs.append(abs(b.speed - obs.speed))
                }
            }
        }

        let slackMed = med(slackDeltas), slackMax = slackDeltas.max()
        let extMed = med(extremaDeltas), extMax = extremaDeltas.max()
        let speedMed = med(speedErrs), speedMax = speedErrs.max()
        let flipped = extremaTotal > 0 && Double(wrongSign) / Double(extremaTotal) >= 0.6
        let pass = slackUnmatched == 0 && !flipped
            && (slackMed ?? .infinity) <= SLACK_MEDIAN_MAX && (slackMax ?? .infinity) <= SLACK_WORST_MAX
            && (extMed ?? .infinity) <= EXTREMA_MEDIAN_MAX && (speedMed ?? .infinity) <= SPEED_MEDIAN_MAX

        let fmt = { (x: Double?) in x.map { String(format: "%.1f", $0) } ?? "-" }
        print("""
        == \(name) [\(label)] rms \(String(format: "%.2f", fit.rms)) kn, \(fit.constituents.count) constituents, unseparable [\(fit.unseparable.joined(separator: " "))]
           slack    median \(fmt(slackMed)) / max \(fmt(slackMax)) min  (\(slackDeltas.count) matched, \(slackUnmatched) unmatched)
           extrema  median \(fmt(extMed)) / max \(fmt(extMax)) min  (\(extremaDeltas.count)/\(extremaTotal) scored)
           speed    median \(fmt(speedMed)) / max \(fmt(speedMax)) kn, wrong-sign \(wrongSign)/\(extremaTotal)
           \(pass ? "PASS" : "FAIL")
        """)

        let report: [String: Any] = [
            "gate": name, "window": label, "iwlsId": station.id, "iwlsName": station.officialName,
            "resolvedKm": distance, "floodDirection": flood, "ebbDirection": ebb,
            "samples": samples.count, "rmsKn": fit.rms, "offset": fit.offset,
            "unseparable": fit.unseparable,
            "valStart": iso.string(from: valStart), "valEnd": iso.string(from: valEnd),
            "slackMedianMin": slackMed ?? -1, "slackMaxMin": slackMax ?? -1,
            "slackMatched": slackDeltas.count, "slackUnmatched": slackUnmatched,
            "extremaMedianMin": extMed ?? -1, "extremaMaxMin": extMax ?? -1,
            "extremaScored": extremaDeltas.count, "extremaTotal": extremaTotal,
            "speedMedianKn": speedMed ?? -1, "speedMaxKn": speedMax ?? -1,
            "wrongSign": wrongSign, "pass": pass,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: reportsDir.appendingPathComponent("\(slug)-\(label)-report.json"))
        if label == "210d" && pass { exitCode = 0 }
    }
    return exitCode
}

// Tide mode continues below; current mode does everything above and exits.
if isCurrentMode {
    exit(try runCurrentValidation())
}

let fitSamples = quarter(try fetchSeries("wlp", fitStart, fitEnd))
let valSamples = quarter(try fetchSeries("wlp", valStart, valEnd))
let hilo = try fetchSeries("wlp-hilo", valStart, valEnd)
print("fit: \(fitSamples.count) pts (60 d @ 15 min), val: \(valSamples.count) pts, hilo: \(hilo.count) events")

// --- fit with the app's exact JS artifacts ---
let ctx = JSContext()!
var jsError: String?
ctx.exceptionHandler = { _, exc in jsError = exc?.toString() }
ctx.evaluateScript("var console = {log:function(){},warn:function(){},error:function(){},info:function(){},debug:function(){}};")
for file in ["chs-bundle.js", "chs-glue.js"] {
    ctx.evaluateScript(try String(contentsOf: resources.appendingPathComponent(file), encoding: .utf8))
    if let e = jsError { fatalError("\(file): \(e)") }
}
let samplesJson = "[" + fitSamples.map { "{\"t\":\($0.t),\"v\":\($0.v)}" }.joined(separator: ",") + "]"
let t0 = DispatchTime.now()
guard let out = ctx.objectForKeyedSubscript("fitTides")?.call(withArguments: [samplesJson]), jsError == nil else {
    fatalError("fitTides threw: \(jsError ?? "?")")
}
let wallMs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
struct Fit: Decodable {
    struct Con: Decodable { let name: String; let amplitude: Double; let phase: Double }
    let fitMs: Double, offset: Double, rms: Double
    let constituents: [Con], unseparable: [String]
}
let fit = try JSONDecoder().decode(Fit.self, from: Data(out.toString()!.utf8))
print("fit: \(fit.constituents.count) constituents, rms \(String(format: "%.1f", fit.rms * 100)) cm, " +
      "offset \(String(format: "%.3f", fit.offset)) m, \(Int(fit.fitMs)) ms JS (\(Int(wallMs)) ms wall), " +
      "unseparable: \(fit.unseparable.joined(separator: ", "))")

// --- predict with TideEngine (the app's shipping path) and score ---
let engine = Station(constituents: fit.constituents.map { HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) },
                     offset: fit.offset)
let predicted = engine.heights(from: Date(timeIntervalSince1970: valStart.timeIntervalSince1970),
                               to: valEnd, step: 900)
var predByMs: [Double: Double] = [:]
for p in predicted { predByMs[p.time.timeIntervalSince1970 * 1000] = p.height }
var n = 0, sq = 0.0, maxAbs = 0.0
for s in valSamples {
    guard let pred = predByMs[s.t] else { continue }
    let e = (pred - s.v) * 100
    n += 1; sq += e * e; maxAbs = max(maxAbs, abs(e))
}
let rmse = (sq / Double(n)).squareRoot()

// Extreme timing vs wlp-hilo (no high/low qualifier — classify vs neighbours).
let extremes = engine.extremes(from: Date(timeIntervalSince1970: valStart.timeIntervalSince1970 - dayS),
                               to: valEnd.addingTimeInterval(dayS))
var timings: [Double] = [], heightErrs: [Double] = []
var matched = 0
for i in hilo.indices {
    let prev = i > 0 ? hilo[i - 1].v : -.infinity
    let next = i < hilo.count - 1 ? hilo[i + 1].v : -.infinity
    let isHigh = hilo[i].v > prev || hilo[i].v > next
    var best: (dt: Double, h: Double)?
    for e in extremes where (e.kind == .high) == isHigh {
        let dt = abs(e.time.timeIntervalSince1970 * 1000 - hilo[i].t) / 60_000
        if best == nil || dt < best!.dt { best = (dt, e.height) }
    }
    if let b = best, b.dt < 180 {
        matched += 1
        timings.append(b.dt)
        heightErrs.append(abs(b.h - hilo[i].v) * 100)
    }
}
timings.sort()
print(String(format: """
    == %@ vs live IWLS, held-out %@ .. %@ ==
    RMSE          %.2f cm   (n=%d)
    max abs       %.1f cm
    extremes      %d/%d matched, timing median %.0f min / max %.0f min, mean height err %.1f cm
    """, name, iso.string(from: valStart), iso.string(from: valEnd),
    rmse, n, maxAbs, matched, hilo.count,
    timings.isEmpty ? -1 : timings[timings.count / 2], timings.last ?? -1,
    heightErrs.isEmpty ? -1 : heightErrs.reduce(0, +) / Double(heightErrs.count)))

// Tolerance: the spike's Victoria benchmark was 6.44 cm RMSE / 11 min median.
// Gate at RMSE <= 10 cm and median extreme timing <= 20 min.
let pass = rmse <= 10 && !timings.isEmpty && timings[timings.count / 2] <= 20
print(pass ? "PASS" : "FAIL")
exit(pass ? 0 : 1)
