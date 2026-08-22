// Slackwater — GPL v3. Unit formatting shared by the app and the widget
// extension (mirrors slackwater-web src/units.ts): imperial/metric height,
// knots/km-h/m-s speed, and the AppStorage keys both read — App-Group backed
// so a setting changed in the app is visible to the widget's next timeline
// build (see AppGroup.migrateIfNeeded).
import Foundation

// MARK: - Units (mirrors slackwater-web src/units.ts)

let unitsKey = "slackwater.units"  // "imperial" | "metric", same values as the web

func toFeet(_ metres: Double) -> Double { metres * 3.28084 }

/// Strip a negative zero, which appears whenever a tide sits just below datum.
private func unsign(_ n: Double) -> Double { abs(n) < 0.05 ? abs(n) : n }

func formatHeight(_ metres: Double, imperial: Bool) -> String {
    imperial ? String(format: "%.1f", unsign(toFeet(metres)))
             : String(format: "%.2f", unsign(metres))
}

func heightUnit(imperial: Bool) -> String { imperial ? "ft" : "m" }

// Current speed (web units.ts SpeedUnit): "kn" | "kmh" | "ms", same key/values.
let speedUnitKey = "slackwater.speedUnit"

func toKmh(_ knots: Double) -> Double { knots * 1.852 }
func toMs(_ knots: Double) -> Double { knots * 0.514444 }

/// Web formatSpeed: convert, strip a near-zero sign, one decimal.
func formatSpeed(_ knots: Double, unit: String) -> String {
    let v = unit == "kmh" ? toKmh(knots) : unit == "ms" ? toMs(knots) : knots
    return String(format: "%.1f", abs(v) < 0.05 ? abs(v) : v)
}

func speedUnitLabel(_ unit: String) -> String {
    unit == "kmh" ? "km/h" : unit == "ms" ? "m/s" : "kn"
}
