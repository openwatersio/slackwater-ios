// Slackwater — GPL v3. Unit formatting shared by the app and the widget
// extension (mirrors slackwater-web src/units.ts): imperial/metric height,
// knots/km-h/m-s speed, and the AppStorage keys both read — App-Group backed
// so a setting changed in the app is visible to the widget's next timeline
// build (see AppGroup.migrateIfNeeded).
import Foundation

// MARK: - Units (mirrors slackwater-web src/units.ts)

let unitsKey = "slackwater.units"  // "imperial" | "metric", same values as the web

/// Regional defaults stay unsaved so an arriving cloud preference can replace them.
func heightUnits(defaults: UserDefaults = AppGroup.defaults,
                 locale: Locale = .autoupdatingCurrent) -> String {
    defaults.string(forKey: unitsKey) ?? (locale.region?.identifier == "US" ? "imperial" : "metric")
}

func toFeet(_ metres: Double) -> Double { metres * 3.28084 }

/// Strip a negative zero, which appears whenever a tide sits just below datum.
private func unsign(_ n: Double) -> Double { abs(n) < 0.05 ? abs(n) : n }

private func decimal(_ value: Double, places: Int, locale: Locale) -> String {
    value.formatted(.number.locale(locale).grouping(.never)
        .rounded(rule: .toNearestOrAwayFromZero).precision(.fractionLength(places)))
}

func formatHeight(_ metres: Double, imperial: Bool,
                  locale: Locale = .autoupdatingCurrent) -> String {
    imperial ? decimal(unsign(toFeet(metres)), places: 1, locale: locale)
             : decimal(unsign(metres), places: 2, locale: locale)
}

func heightUnit(imperial: Bool) -> String { imperial ? "ft" : "m" }

// Current speed (web units.ts SpeedUnit): "kn" | "kmh" | "ms", same key/values.
let speedUnitKey = "slackwater.speedUnit"

func toKmh(_ knots: Double) -> Double { knots * 1.852 }
func toMs(_ knots: Double) -> Double { knots * 0.514444 }

/// Web formatSpeed: convert, strip a near-zero sign, one decimal.
func formatSpeed(_ knots: Double, unit: String,
                 locale: Locale = .autoupdatingCurrent) -> String {
    let v = unit == "kmh" ? toKmh(knots) : unit == "ms" ? toMs(knots) : knots
    return decimal(abs(v) < 0.05 ? abs(v) : v, places: 1, locale: locale)
}

func speedUnitLabel(_ unit: String) -> String {
    unit == "kmh" ? "km/h" : unit == "ms" ? "m/s" : "kn"
}

/// A printed unit as VoiceOver should say it: "kn" is read as a word.
func spokenUnit(_ label: String) -> String {
    switch label {
    case "kn": String(localized: "knots", comment: "Spoken expansion of the printed nautical speed unit 'kn'.")
    case "km/h": String(localized: "kilometres per hour", comment: "Spoken metric speed unit.")
    case "m/s": String(localized: "metres per second", comment: "Spoken metric speed unit.")
    case "ft": String(localized: "feet", comment: "Spoken imperial height unit.")
    case "m": String(localized: "metres", comment: "Spoken metric height unit.")
    default: label
    }
}

// MARK: - Distance formatting (prototype NearMe.dc.html semantics)

/// "1.2 nm" / "14 nm" — the prototype's fmtDist.
func formatNm(_ km: Double, locale: Locale = .autoupdatingCurrent) -> String {
    let nm = km / 1.852
    return String(localized: "\(decimal(nm, places: nm < 10 ? 1 : 0, locale: locale)) nm",
                  comment: "Distance in nautical miles. The value is a locale-formatted number and 'nm' is nautical notation.")
}
