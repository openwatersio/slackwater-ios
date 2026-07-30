// Slackwater — GPL v3. M3 exit check A: fitted predictions vs live IWLS over a
// held-out window, the M0 spike's methodology (60 d @ 15 min fit; 7-day
// validation window 4 weeks after fit end; RMSE on the 15-min grid vs wlp;
// extreme timing vs wlp-hilo, classified against neighbours, matched by kind
// within 180 min). Fit runs in JSCore via the app's committed chs-bundle.js +
// chs-glue.js; prediction runs in TideEngine — exactly the shipping path.
//
//   swift run fit-validation <name> <lat> <lon> [cacheDir]
//
// Fetched IWLS data is cached under cacheDir (default /tmp/fit-validation) and
// deliberately never written into the repo — it is CHS data, the user's own.
import Foundation
import JavaScriptCore
import TideEngine

let args = CommandLine.arguments
guard args.count >= 4, let lat = Double(args[2]), let lon = Double(args[3]) else {
    print("usage: fit-validation <name> <lat> <lon> [cacheDir]")
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
let list = try JSONDecoder().decode([IwlsStation].self, from: cachedGet("/stations", key: "stations.json"))
let wlpStations = list.filter { $0.timeSeries.contains { $0.code == "wlp" } }
let station = wlpStations.min { km(lat, lon, $0.latitude, $0.longitude) < km(lat, lon, $1.latitude, $1.longitude) }!
let distance = km(lat, lon, station.latitude, station.longitude)
guard distance <= 3.0 else { fatalError("no wlp station within 3 km of \(name) (nearest \(station.officialName) at \(distance) km)") }
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
let fitSamples = quarter(try fetchSeries("wlp", fitStart, fitEnd))
let valSamples = quarter(try fetchSeries("wlp", valStart, valEnd))
let hilo = try fetchSeries("wlp-hilo", valStart, valEnd)
print("fit: \(fitSamples.count) pts (60 d @ 15 min), val: \(valSamples.count) pts, hilo: \(hilo.count) events")

// --- fit with the app's exact JS artifacts ---
let resources = URL(fileURLWithPath: #filePath) // tools/FitValidation/Sources/fit-validation/main.swift
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Slackwater/Resources")
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
