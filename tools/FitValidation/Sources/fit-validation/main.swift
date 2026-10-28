// Slackwater — GPL v3. File-input validation for the fill and patch pipelines.
// Fits use tools/chs-reference's frozen JavaScript oracle. Shipping CHS gate
// validation lives in the engine and chs-current-validation results repository.
import Foundation
import JavaScriptCore
import SlackwaterKit

func flagValue(_ flag: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

guard CommandLine.arguments.contains("--samples"), !CommandLine.arguments.contains("--current") else {
    print("usage: fit-validation --samples <file> --events <file> --flood <deg> --ebb <deg> --label <slug>")
    exit(2)
}
let cacheDir = URL(fileURLWithPath: "/tmp/fit-validation")
try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
let iso = ISO8601DateFormatter()
let dayS = 86_400.0

// The JavaScript reference artifacts (shared by current and file modes).
let resources = URL(fileURLWithPath: #filePath) // tools/FitValidation/Sources/fit-validation/main.swift
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("tools/chs-reference")

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
struct FitOut: Decodable {
    struct Con: Decodable { let name: String; let amplitude: Double; let phase: Double }
    let fitMs: Double
    let offset: Double
    let rms: Double
    let constituents: [Con]
    let unseparable: [String]
}
struct Obs { let time: Date; let kind: CurrentEventKind; let speed: Double }

/// IwlsEvent -> Obs, shared by live IWLS fetch and file-input mode (both
/// decode the same wcp1-events shape).
@MainActor
func toObservations(_ rawEvents: [IwlsEvent]) -> [Obs] {
    rawEvents.compactMap { e in
        guard let t = iso.date(from: e.eventDate) ?? isoFrac.date(from: e.eventDate) else { return nil }
        switch e.qualifier {
        case "SLACK": return Obs(time: t, kind: .slack, speed: 0)
        case "EXTREMA_FLOOD": return Obs(time: t, kind: .maxFlood, speed: e.value)
        case "EXTREMA_EBB": return Obs(time: t, kind: .maxEbb, speed: -e.value)
        default: return nil
        }
    }
}

func med(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// File-input mode (Task 5): samples + events come from disk instead of IWLS.
/// Joins the shared fit/score path in runFit() below — same JSCore fit, same
/// CurrentStation prediction, same scoring bars, byte-identical for the same
/// sample bytes. Validation window is the events file's own span, never Date().
@MainActor
func runFileMode() throws -> Int32 {
    guard let samplesPath = flagValue("--samples"),
          let eventsPath = flagValue("--events"),
          let flood = flagValue("--flood").flatMap({ Double($0) }),
          let ebb = flagValue("--ebb").flatMap({ Double($0) }),
          let label = flagValue("--label")
    else {
        print("usage: fit-validation --samples <file> --events <file> --flood <deg> --ebb <deg> --label <slug>")
        exit(2)
    }

    struct FileSample: Decodable { let t: Double; let v: Double }
    let decoded = try JSONDecoder().decode([FileSample].self,
        from: Data(contentsOf: URL(fileURLWithPath: samplesPath)))
    let projected: [(t: Double, v: Double)] = decoded.map { ($0.t, $0.v) }
    // chs-glue.js documents fitTides' contract as epoch-ms ("t: epoch-ms" —
    // tools/chs-reference/chs-glue.js:4), and the file pipelines hand ms. File-mode does NOT convert units —
    // it decodes t literally, matching what the parity check requires (replaying
    // an already-ms samples file must stay byte-identical). The trailing-60d
    // cutoff still needs to know which unit it's looking at, so it disambiguates
    // by magnitude: any real calendar date is ~1e9 in epoch-seconds and ~1e12 in
    // epoch-ms, and those ranges never overlap.
    let maxT = projected.map { $0.t }.max() ?? 0
    let dayLen = maxT > 1e11 ? 86_400_000.0 : 86_400.0
    let projected60 = projected.filter { $0.t >= maxT - 60 * dayLen }

    let rawEvents = try JSONDecoder().decode([IwlsEvent].self,
        from: Data(contentsOf: URL(fileURLWithPath: eventsPath)))
    let observed = toObservations(rawEvents)
    guard !observed.isEmpty else {
        print("FAIL-FOR-FITTING: \(label) — events file has no usable events")
        return 3
    }
    let dates = observed.map { $0.time }.sorted()
    let valStart = dates.first!, valEnd = dates.last!

    print("samples: \(projected.count) from file (\(projected60.count) in trailing 60 d), axis flood \(Int(flood))° / ebb \(Int(ebb))°")
    return try runFit(name: label, flood: flood, ebb: ebb,
                       projected: projected, projected60: projected60, observed: observed,
                       valStart: valStart, valEnd: valEnd,
                       stationId: "file", stationName: label, resolvedKm: -1)
}

/// File-input fit, prediction and scoring path for the fill and patch pipelines.
@MainActor
func runFit(name: String, flood: Double, ebb: Double,
            projected: [(t: Double, v: Double)], projected60: [(t: Double, v: Double)],
            observed: [Obs], valStart: Date, valEnd: Date,
            stationId: String, stationName: String, resolvedKm: Double) throws -> Int32 {
    // The JavaScript reference artifacts, same as the tide path.
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
            "gate": name, "window": label, "iwlsId": stationId, "iwlsName": stationName,
            "resolvedKm": resolvedKm, "floodDirection": flood, "ebbDirection": ebb,
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

exit(try runFileMode())
