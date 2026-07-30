// Slackwater — GPL v3. Design tokens from the prototype design system
// (prototype/_ds/_ds_bundle.css): sn- palette, Fraunces/Geist/Geist Mono type
// roles, per-station gradient trios, and the web app's unit formatting.
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum SN {
    static let navyDeep = Color(hex: 0x00183C)
    static let canvas = Color(hex: 0x05122A)      // list canvas
    static let canvasGlow = Color(hex: 0x0A2140)  // radial glow at top of list
    static let page = Color(hex: 0x00121F)        // 1b Modular detail page
    static let leaf = Color(hex: 0x88B868)
    static let steel = Color(hex: 0x5888A8)
    static let sky = Color(hex: 0xC0D8E4)
    static let foam = Color(hex: 0xE4F0E4)
    static let paper = Color(hex: 0xFCFCFC)
    static let rising = leaf                       // web --rising
    static let falling = Color(hex: 0x7FB4D8)      // web --falling
    static let cardStroke = leaf.opacity(0.16)
    static let cardFill = Color.white.opacity(0.05)
}

extension Font {
    static func fraunces(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold: .custom("Fraunces-SemiBold", size: size)
        case .medium: .custom("Fraunces-Medium", size: size)
        default: .custom("Fraunces-Regular", size: size)
        }
    }
    static func geist(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold: .custom("Geist-SemiBold", size: size)
        case .medium: .custom("Geist-Medium", size: size)
        default: .custom("Geist-Regular", size: size)
        }
    }
    static func geistMono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        weight == .medium || weight == .semibold
            ? .custom("GeistMono-Medium", size: size)
            : .custom("GeistMono-Regular", size: size)
    }
}

/// The Geist Mono uppercase section-label role from the prototype.
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 11
    var color: Color = SN.leaf
    var tracking: CGFloat = 1.6
    var body: some View {
        Text(text.uppercased())
            .font(.geistMono(size, .medium))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - Per-station sky gradients (variant 1a list cards)

/// The prototype's hand-tuned gradient trios (prototype/NearMe.dc.html DATA()).
/// Assignment is a stable hash of the station id — deterministic, no semantics.
private let gradientTrios: [(UInt32, UInt32, UInt32)] = [
    (0x88B0CC, 0x3A6D98, 0x184870), (0x3A6D98, 0x184870, 0x083058),
    (0x9AC0B0, 0x4A8F78, 0x184860), (0x78A8B8, 0x2F7088, 0x0D3A58),
    (0x184870, 0x0D3358, 0x00183C), (0x88B0CC, 0x4A7BA0, 0x20486A),
    (0xA8C4D4, 0x5888A8, 0x28587C), (0x7098B8, 0x2F6390, 0x153F66),
    (0x88AECB, 0x3D6F9A, 0x1A4A70), (0x8AB8A0, 0x3D8068, 0x154A44),
    (0x96BCD2, 0x4E84A8, 0x265678), (0x7FA6C6, 0x356690, 0x184568),
]

func stationGradient(id: String) -> LinearGradient {
    // Friday Harbor keeps the prototype's teal trio; the rest hash into the family.
    let index = id == TideStationRecord.fridayHarborID
        ? 2
        : Int(id.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) } % UInt64(gradientTrios.count))
    let (a, b, c) = gradientTrios[index]
    // CSS linear-gradient(150deg, a, b 55%, c)
    return LinearGradient(
        stops: [.init(color: Color(hex: a), location: 0),
                .init(color: Color(hex: b), location: 0.55),
                .init(color: Color(hex: c), location: 1)],
        startPoint: UnitPoint(x: 0.15, y: 0), endPoint: UnitPoint(x: 0.85, y: 1))
}

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

// MARK: - Station-local time formatting

private var formatterCache: [String: DateFormatter] = [:]

private func formatter(_ pattern: String, _ tz: TimeZone) -> DateFormatter {
    let key = pattern + tz.identifier
    if let cached = formatterCache[key] { return cached }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz
    f.dateFormat = pattern
    formatterCache[key] = f
    return f
}

/// "1:42 PM" — the card/readout style (web cardTime, en-US).
func cardTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("h:mm a", tz).string(from: date)
}

/// "14:05" — the chart/table style (web en-CA 24h).
func clockTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("HH:mm", tz).string(from: date)
}

/// "Wed, Jul 30" — the schedule date line.
func dayLine(_ date: Date, _ tz: TimeZone) -> String {
    formatter("EEE, MMM d", tz).string(from: date)
}

func weekdayName(_ date: Date, _ tz: TimeZone) -> String {
    formatter("EEEE", tz).string(from: date)
}
