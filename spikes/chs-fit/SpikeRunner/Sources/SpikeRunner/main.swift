// M0 CHS fit spike: run the chs-constituents IIFE bundle inside JavaScriptCore
// (same engine as iOS), fit Victoria Harbour from cached IWLS wlp, predict the
// validation window, compare against cached IWLS. Mirrors control.mjs exactly.
import Foundation
import JavaScriptCore

struct Point: Codable { let t: Double; let v: Double }
struct Extreme: Codable { let t: Double; let v: Double; let kind: String }
struct Pair: Codable { let constituents: [String]; let requiredDays: Int }
struct SpikeOut: Codable {
    let fitMs: Double
    let offset: Double
    let rms: Double
    let nConstituents: Int
    let unseparable: [Pair]
    let predictions: [Point]
    let extremes: [Extreme]
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)

func load(_ name: String) throws -> String {
    try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
}

let context = JSContext()!
var jsError: String?
context.exceptionHandler = { _, exc in jsError = exc?.toString() }

// JSCore has no console; the bundle shouldn't need one, but shim it so a stray
// log can't crash the spike.
let noop: @convention(block) (String) -> Void = { _ in }
context.evaluateScript("var console = {};")
for level in ["log", "warn", "error", "info", "debug"] {
    context.objectForKeyedSubscript("console")?.setObject(noop, forKeyedSubscript: level as NSString)
}

context.evaluateScript(try load("../chs-bundle.js"))
if let e = jsError { fatalError("bundle load failed: \(e)") }
context.evaluateScript(try load("../glue.js"))
if let e = jsError { fatalError("glue load failed: \(e)") }

// argv[2]: alternate fit-window file (e.g. the 210-day series)
let fitFile = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "../fit-window.json"
let fitJson = try load(fitFile)
let valData = try JSONDecoder().decode([Point].self, from: Data(try load("../validation-window.json").utf8))
let hilo = try JSONDecoder().decode([Point].self, from: Data(try load("../validation-hilo.json").utf8))

let wallStart = DispatchTime.now()
let run = context.objectForKeyedSubscript("runSpike")!
let resultJS = run.call(withArguments: [fitJson, valData.first!.t, valData.last!.t, 900])
if let e = jsError { fatalError("runSpike threw: \(e)") }
let wallMs = Double(DispatchTime.now().uptimeNanoseconds - wallStart.uptimeNanoseconds) / 1e6

let out = try JSONDecoder().decode(SpikeOut.self, from: Data(resultJS!.toString().utf8))

// --- metrics, identical to control.mjs ---
var predByT: [Double: Double] = [:]
for p in out.predictions { predByT[p.t] = p.v }
var n = 0, sq = 0.0, maxAbs = 0.0
for p in valData {
    guard let pred = predByT[p.t] else { continue }
    let e = (pred - p.v) * 100
    n += 1; sq += e * e; maxAbs = max(maxAbs, abs(e))
}
let rmse = (sq / Double(n)).squareRoot()

var timings: [Double] = []
var heightErrs: [Double] = []
var matched = 0
for i in hilo.indices {
    let prev = i > 0 ? hilo[i - 1] : nil
    let next = i < hilo.count - 1 ? hilo[i + 1] : nil
    let isHigh = (prev.map { hilo[i].v > $0.v } ?? false) || (next.map { hilo[i].v > $0.v } ?? false)
    let kind = isHigh ? "high" : "low"
    var best: (dt: Double, e: Extreme)?
    for e in out.extremes where e.kind == kind {
        let dt = abs(e.t - hilo[i].t) / 60000
        if best == nil || dt < best!.dt { best = (dt, e) }
    }
    if let b = best, b.dt < 180 {
        matched += 1
        timings.append(b.dt)
        heightErrs.append(abs(b.e.v - hilo[i].v) * 100)
    }
}
timings.sort()
let median = timings[timings.count / 2]

let report: [String: Any] = [
    "engine": "JavaScriptCore (macOS — same engine as iOS)",
    "fitMsInsideJS": out.fitMs,
    "wallMsFitPlusPredict": (wallMs * 10).rounded() / 10,
    "rmsFitM": out.rms,
    "nConstituents": out.nConstituents,
    "unseparablePairs": out.unseparable.count,
    "comparedPoints": n,
    "rmseCm": (rmse * 100).rounded() / 100,
    "maxAbsCm": (maxAbs * 100).rounded() / 100,
    "extremes": [
        "matched": matched, "of": hilo.count,
        "medianTimingMin": (median * 10).rounded() / 10,
        "maxTimingMin": (timings.last! * 10).rounded() / 10,
        "meanHeightErrCm": ((heightErrs.reduce(0, +) / Double(heightErrs.count)) * 100).rounded() / 100,
    ],
]
let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(data: json, encoding: .utf8)!)
try json.write(to: dir.appendingPathComponent("../jscore-report.json"))
