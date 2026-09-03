// Slackwater — GPL v3. Design tokens from the prototype design system
// (prototype/_ds/_ds_bundle.css): sn- palette, Fraunces/Geist/Geist Mono type
// roles, and the web app's unit formatting. The per-station gradient trios
// this once carried are gone (M53 layout A) — cards take a flat SN.cardFill.
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A pale tint of `hex`, blended toward white — for small text on a
    /// near-black chart, where plain `.opacity()` just reads as dim rather
    /// than pale. Takes the hex, not a Color, so callers stay one edit away
    /// from the base token instead of a second hand-picked literal.
    static func hex(_ hex: UInt32, lightenedBy t: Double) -> Color {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return Color(red: (r + (255 - r) * t) / 255,
                     green: (g + (255 - g) * t) / 255,
                     blue: (b + (255 - b) * t) / 255)
    }
}

enum SN {
    static let navyDeep = Color(hex: 0x00183C)
    static let canvas = Color(hex: 0x05122A)
    static let canvasGlow = Color(hex: 0x0A2140)  // radial glow at top of a screen
    static let leaf = Color(hex: 0x88B868)
    static let steelHex: UInt32 = 0x5888A8
    static let steel = Color(hex: steelHex)
    static let foamHex: UInt32 = 0xE4F0E4
    static let foam = Color(hex: foamHex)
    static let paper = Color(hex: 0xFCFCFC)
    // Direction is one signed diverging axis (colourblind-safe amber/blue);
    // green means only slack — never colour anything by station kind.
    // Raw hexes too: MapLibre style dicts hold strings, so MapStyleBuilder
    // formats these into "#rrggbb" rather than hand-maintaining a second
    // palette.
    static let floodHex: UInt32 = 0x4A9FD8
    static let ebbHex: UInt32 = 0xE8A33D
    static let goHex: UInt32 = 0x88B868
    static let flood = Color(hex: floodHex)
    static let ebb = Color(hex: ebbHex)
    static let go = Color(hex: goHex)
    static let rising = flood
    static let falling = ebb
    /// Pale flood/ebb for small chart text on near-black — derived from the
    /// same hex so retargeting a token keeps its label in lockstep.
    static let floodLabel = Color.hex(floodHex, lightenedBy: 0.6)
    static let ebbLabel = Color.hex(ebbHex, lightenedBy: 0.6)
    /// The station-card curve's palette (Neaps dark mode, packages/react
    /// styles.css) — full saturation for the card's hero element, unlike
    /// flood/floodLabel, which are muted to sit inside the timeline strip.
    static let graphLine = Color(hex: 0x38BDF8)  // sky-400
    static let graphHigh = Color(hex: 0x2DD4BF)  // teal-400
    static let graphLow = Color(hex: 0xFBBF24)   // amber-400
    static let cardStroke = leaf.opacity(0.16)
    static let cardFill = Color.white.opacity(0.05)
    static let night = Color(hex: 0x00101F)        // prototype night band
    static let sun = Color(hex: 0xF0C860)          // prototype sun dot
    /// Attention, never alarm: deliberately red-leaning so it cannot be
    /// misread as `ebb`. Same value the web app uses. (The retired literal is
    /// not spelled here — `testNoSourceFileSpellsARetiredColour` bans it.)
    static let amber = Color(hex: 0xEF6F4A)
    static let sunrise = Color(hex: 0xF0D890)      // prototype "☀ Rise" pill
    static let sunset = Color(hex: 0xC8A86A)       // prototype "☀ Set" pill
    static let shadow = Color(hex: 0x001432)       // every drop shadow; sites pick the opacity
    static let moonLimb = Color(hex: 0x00122C, opacity: 0.92)  // the moon's dark limb, glyph and strip
    // The gate screen's pin tile (prototype gradient), top-leading to bottom-trailing.
    static let gateTile = [Color(hex: 0x3A6D98), Color(hex: 0x184870), Color(hex: 0x083058)]

    // MARK: - Speed magnitude (#97)

    /// The shared speed scale: yellow at the comfort threshold, orange beyond
    /// it, red at the fast end. It deliberately never enters green: green is
    /// reserved for a usable Slack window.
    static let speedRampStops: [(t: Double, hex: UInt32)] = [
        (0.0, 0xF5C96B), (1.0 / 3.0, 0xF5C96B),
        (2.0 / 3.0, 0xE8763C), (1.0, 0xC93A32),
    ]

    /// The ramp sampled at `t`, clamped to 0...1. Piecewise-linear in sRGB:
    /// the stops sit close enough together that a perceptual space buys
    /// nothing a reader could see.
    static func speedRGB(_ t: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(max(t, 0), 1)
        let stops = speedRampStops
        let channels = { (hex: UInt32) -> (Double, Double, Double) in
            (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
        }
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            guard t >= a.t, t <= b.t else { continue }
            let f = b.t == a.t ? 0 : (t - a.t) / (b.t - a.t)
            let lo = channels(a.hex)
            let hi = channels(b.hex)
            return (lo.0 + (hi.0 - lo.0) * f, lo.1 + (hi.1 - lo.1) * f, lo.2 + (hi.2 - lo.2) * f)
        }
        let (r, g, b) = channels(stops[stops.count - 1].hex)
        return (r, g, b)
    }

    static func speedColour(_ t: Double) -> Color {
        let c = speedRGB(t)
        return Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255)
    }

    /// Ink for a label drawn ON the ramp fill — whichever of white or `canvas`
    /// has more contrast against it. Chosen from the ramp position rather
    /// than from how far the label sits off the zero line: the curve's shape
    /// stays auto-fitted, so a quiet station puts a label deep inside a dark
    /// fill just as a violent one puts one inside a bright fill.
    static func speedInk(_ t: Double) -> Color {
        let c = speedRGB(t)
        let lin = { (v: Double) -> Double in
            let s = v / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let l = 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        // `canvas` is 0x05122A — relative luminance 0.00632, so 0.05632 is its
        // contrast denominator. The crossover lands at t ≈ 0.90, where both
        // inks measure ≈4.3:1; that is the ramp's worst point and it clears
        // WCAG's 3:1 for the 14pt semibold mark this styles.
        return (1.05 / (l + 0.05)) >= ((l + 0.05) / 0.05632) ? .white : canvas
    }
}

/// The curve as the station cards draw it, shared with the detail strip so
/// the page a card opens into is the same drawing at larger scale. Every knob
/// both surfaces read lives here; a value only one of them uses stays local.
enum CurveStyle {
    static let lineWidth: CGFloat = 2.5
    /// The line left of now, and the labels of moments already passed.
    static let pastLineOpacity = 0.35
    static let pastLabelFade = 0.45
    /// Extreme and window-start dots; the now dot is its own size.
    static let dotRadius: CGFloat = 2.5
    static let nowDotDiameter: CGFloat = 7
    /// The background-punched ring beyond a dot's or run's edge.
    static let haloGap: CGFloat = 2.5
    /// The area gradient at full intensity, and the tide fill's floor.
    static let fillOpacity = 0.5
    static let tideFillFloor = 0.05
    /// The dotted datum/zero reference line.
    static let referenceLineOpacity = 0.35
    static let referenceLineDash: [CGFloat] = [1, 3]
    /// The reading hangs off a turn or peak toward the plot middle: the
    /// value this far from the dot, the pointer glyph under it. Both tracks
    /// read these, so tuning one cannot silently unpair the other.
    static let hangOffset: CGFloat = 23
    static let hangValueRise: CGFloat = 7
    static let hangGlyphDrop: CGFloat = 8
    static let hangValueFontSize: CGFloat = 14
    static let hangGlyphFontSize: CGFloat = 12
}

/// The one full-screen background: canvas navy with the prototype's radial
/// glow falling from the top. Use it for whole screens; flat `SN.canvas` is
/// for toolbars, pills and scrims that sit on it.
struct CanvasBackground: View {
    var body: some View {
        RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                       startRadius: 0, endRadius: 500)
            .ignoresSafeArea()
    }
}

/// The uppercase mono section-label role. Sizes 9/10/11 used to be passed per
/// call site; under Dynamic Type they all collapse to `.caption2` and scale
/// with the reader's setting instead.
struct MonoLabel: View {
    let text: String
    var color: Color = SN.leaf
    var tracking: CGFloat = 1.6
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.monospaced().weight(.medium))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - App clock

/// Real time, or shifted by `-nowOffsetDays N` (read via UserDefaults'
/// argument domain) — the UI-test hook behind the M3 airplane-mode
/// day-after check (relaunch offline "tomorrow").
private let appNowOffset: TimeInterval =
    UserDefaults.standard.double(forKey: "nowOffsetDays") * 86_400

func appNow() -> Date { Date.now.addingTimeInterval(appNowOffset) }

/// Today's local midnight in `tz`, on the app clock. The anchor every detail
/// view starts on, and the `today` half of every `Timeline.window` call.
func todayLocal(_ tz: TimeZone) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.startOfDay(for: appNow())
}

// MARK: - Station-local time formatting

/// NSCache, not a Dictionary: thread-safe (Canvas draws can run off-main) and
/// bounded. DateFormatter itself is thread-safe for formatting since iOS 7.
private let formatterCache = NSCache<NSString, DateFormatter>()

func formatter(_ pattern: String, _ tz: TimeZone) -> DateFormatter {
    let key = (pattern + tz.identifier) as NSString
    if let cached = formatterCache.object(forKey: key) { return cached }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz
    f.dateFormat = pattern
    formatterCache.setObject(f, forKey: key)
    return f
}

/// "1:42 PM" — the card/readout style (web cardTime, en-US).
func cardTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("h:mm a", tz).string(from: date)
}

/// "14:05" — the chart/table style (web en-CA 24h). Zero-padded, and that
/// padding is load-bearing in `MultiDaySchedule`: the times there are a
/// left-aligned monospaced COLUMN, and "7:03" would hang a character left of
/// "12:53" all the way down the list.
func clockTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("HH:mm", tz).string(from: date)
}

/// "4:22pm" — the strip's clock. Twelve-hour, lowercase, no space and no
/// periods: " p.m." labels were mostly meridiem and collided because of it.
/// `MultiDaySchedule` stays on 24h `clockTime` — its column needs the pad.
func chartTime(_ date: Date, _ tz: TimeZone) -> String {
    formatter("h:mma", tz).string(from: date).lowercased()
}

/// "Wed" — the strip's non-relative day label.
func shortWeekday(_ date: Date, _ tz: TimeZone) -> String {
    formatter("EEE", tz).string(from: date)
}

/// The web's CompassArrow: ↑ rotated to a true bearing, "sets this way".
struct CompassArrow: View {
    let deg: Double
    var body: some View {
        // The SF Symbol, not the "↑" text glyph: a text arrow at the same
        // point size renders visibly smaller than its symbol neighbours.
        Image(systemName: "arrow.up").rotationEffect(.degrees(deg))
    }
}
