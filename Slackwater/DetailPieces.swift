// Slackwater — GPL v3. The detail views' shared pieces: sky, moon, formatters,
// the lead card and its commentary. SwiftUI and Almanac only, so the watch
// compiles them too (#522).
import Almanac
import SwiftUI

// MARK: - Detail-view shared pieces (tide + current)

struct SkyPaint: Equatable {
    let top: UInt32
    let bottom: UInt32
}

private let skyPaintAnchors: [(altitude: Double, top: UInt32, bottom: UInt32)] = [
    (10, 0x2F7FD4, 0xBDE3FB),
    (0, 0x2B4A7A, 0xF8A15F),
    (-6, 0x17264A, 0x8D4A63),
    (-12, 0x0B1430, 0x2A2A52),
    (-18, 0x04060F, 0x0B1023),
]

func skyPaint(sunAltitude: Double) -> SkyPaint {
    let first = skyPaintAnchors[0]
    if sunAltitude >= first.altitude { return SkyPaint(top: first.top, bottom: first.bottom) }
    for (high, low) in zip(skyPaintAnchors, skyPaintAnchors.dropFirst())
        where sunAltitude > low.altitude {
        let t = (high.altitude - sunAltitude) / (high.altitude - low.altitude)
        return SkyPaint(top: mixedHex(high.top, low.top, t),
                        bottom: mixedHex(high.bottom, low.bottom, t))
    }
    let last = skyPaintAnchors.last!
    return SkyPaint(top: last.top, bottom: last.bottom)
}

// The muted daylight paint never gets bright enough for navy at the lead's position.
func skyUsesDarkInk(sunAltitude _: Double) -> Bool { false }

/// What the chrome floats on: the gradient's lit band composited over the
/// canvas at `skyOpacity`. That band is the brightest ground any pill or lead
/// glyph can land on, so an ink checked against it is legible everywhere in
/// the frame — and it is a sunrise's tan, not the canvas's near-black, which
/// is what the ramp's inks used to assume.
func skyChromeGround(sunAltitude: Double) -> UInt32 {
    mixedHex(SN.canvasHex, skyPaint(sunAltitude: sunAltitude).bottom,
             skyOpacity(sunAltitude: sunAltitude))
}
/// The bodies' sizes, in points. Symbols, many times the true half-degree.
/// The moon's glare fade keys off the sun's glow.
let sunDiscRadius: CGFloat = 8
let sunGlowRadius: CGFloat = 27
let moonGlyphSize: CGFloat = 22
func moonGlowRadius(fraction: Double) -> CGFloat { 12 + CGFloat(fraction) * 20 }
/// The moon fades out inside the sun's glare, as it does in the sky: the
/// bodies are symbols many times their true size, so near every new moon the
/// two would otherwise overlap like an eclipse. `distance` is between their
/// projected centres; the moon is gone by the time the discs would touch and
/// clear once it is past the sun's glow. During a real solar eclipse
/// (`obscuration` > 0, Almanac's covered fraction of the sun's disc) the fade
/// is exactly wrong: the moon is in front of the sun, so it stays at full
/// opacity and draws over it.
func moonGlareOpacity(distance: CGFloat, obscuration: Double = 0) -> Double {
    guard obscuration <= 0 else { return 1 }
    let touching = sunDiscRadius + moonGlyphSize / 2
    let clear = sunGlowRadius + moonGlyphSize / 2
    return max(0, min(1, Double((distance - touching) / (clear - touching))))
}
/// The sun altitude the sky is painted for: the true one, pulled down toward
/// nautical twilight by a solar eclipse's covered fraction. Daylight barely
/// dims until the last tenth of the disc goes, so the pull is quartic — a
/// half-covered sun is still day; totality is a 360° sunset. Every consumer of
/// the paint (gradient, ink, stars) keys off this, so they darken together.
func eclipsedSunAltitude(_ altitude: Double, obscuration: Double) -> Double {
    let totality = -9.0
    guard altitude > totality, obscuration > 0 else { return altitude }
    return altitude + (totality - altitude) * pow(min(obscuration, 1), 4)
}
func starOpacity(sunAltitude: Double) -> Double {
    max(0, min(0.7, (-sunAltitude - 6) / 12 * 0.7))
}
func starTwinkle(index: Int, seconds: TimeInterval, reduceMotion: Bool) -> Double {
    guard !reduceMotion else { return 1 }
    return 0.86 + 0.14 * sin(seconds * (0.55 + Double(index % 5) * 0.08) + Double(index) * 1.7)
}
func skyOpacity(sunAltitude: Double) -> Double {
    1 - max(0, min(1, (sunAltitude + 6) / 6)) * 0.45
}

func mixedHex(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
        let x = Double((a >> shift) & 0xFF)
        let y = Double((b >> shift) & 0xFF)
        return UInt32((x + (y - x) * t).rounded())
    }
    return channel(16) << 16 | channel(8) << 8 | channel(0)
}

/// Where a body crosses the horizon: the azimuths at its last rise at or
/// before a moment and its first set at or after it. By day that is today's
/// pair; by night the pair brackets the night, and the body is off screen.
struct HorizonSpan: Equatable {
    let riseAz: Double
    let setAz: Double
}

/// The sky as a window whose side edges are the horizon. A body's own
/// rise-to-set azimuths (`span`) stretch across the width, so it rises at the
/// RIGHT edge and sets at the left wherever those azimuths fall — the horizon
/// is a circle, and a rectangle's edges can only be it by fitting each body's
/// arc to the frame. Altitude has its own fixed scale, `skyAltitudeScale`:
/// azimuth stretches per day and altitude does not, so a winter noon sits
/// well under a summer one and the sun and moon at one altitude share a
/// height. Mirrored from a sky chart —
/// east on the right, in either hemisphere — because the strip's time axis
/// runs left → right, so as time advances the curve pans right → left under
/// the fixed centerline and a body sweeps with the curve it drives.
/// (openwaters.io/sky keeps the chart convention; this page's frame is the
/// timeline, not a compass.)
///
/// `pad` is the body's disc radius: at the horizon the disc has just cleared
/// the edge, and its glow spills in from off screen as it rises. A wider pad
/// would cost daylight — the sun covers about 36pt an hour here, so padding
/// by the glow instead had it leaving an hour before sunset under a blue
/// sky. With no span the window is the whole 360°.
let skyAltitudeScale: CGFloat = 3   // points per degree of altitude
/// How far the horizon sits inside the plot box, so the curve's peaks rise in
/// front of the lowest stars. Small: a body 5° up is back above the box, and
/// a high peak never covers a rising sun.
let skyHorizonOverlap: CGFloat = 16
/// Haze: stars brighten from the horizon up into the zenith's clear air,
/// and the field runs on a little below the horizon so it trails off in the
/// plot's water instead of starting on a line.
func starHazeOpacity(altitude: Double) -> Double { max(0, min(1, (altitude + 10) / 50)) }
func skyPoint(azimuth: Double, altitude: Double, latitude: Double,
              span: HorizonSpan? = nil, pad: CGFloat = 0, size: CGSize) -> CGPoint {
    let center = latitude >= 0 ? 180.0 : 0.0
    // Degrees from the meridian, negative toward the rising side.
    func signed(_ az: Double) -> Double {
        let s = (az - center + 540).truncatingRemainder(dividingBy: 360) - 180
        return latitude >= 0 ? s : -s
    }
    var rise = -180.0, set = 180.0
    if let span, signed(span.riseAz) < signed(span.setAz) {
        rise = signed(span.riseAz)
        set = signed(span.setAz)
    }
    let pointsPerDegree = (size.width + 2 * pad) / CGFloat(set - rise)
    return CGPoint(x: size.width + pad - CGFloat(signed(azimuth) - rise) * pointsPerDegree,
                   y: size.height - CGFloat(altitude) * skyAltitudeScale)
}

/// A fixed star: J2000 right ascension and declination in degrees, and
/// visual magnitude.
struct Star { let ra: Double; let dec: Double; let mag: Double }

/// Every star brighter than magnitude 3.5, brightest first — enough for the
/// constellations to read without a dust of faint points. `stars.json` is
/// `[ra, dec, mag]` rows cut from d3-celestial's Yale Bright Star Catalog.
let brightStars: [Star] = {
    guard let url = Bundle.main.url(forResource: "stars", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let rows = try? JSONDecoder().decode([[Double]].self, from: data) else { return [] }
    return rows.compactMap { $0.count == 3 ? Star(ra: $0[0], dec: $0[1], mag: $0[2]) : nil }
}()

struct SkyState {
    let latitude: Double
    /// The scrub time this state was built for — what the eclipse is read at.
    let time: Date
    let sun: AltAz?
    let sunSpan: HorizonSpan?
    let moon: AltAz?
    let moonSpan: HorizonSpan?
    let illumination: MoonIllumination?
    /// Every catalog star Almanac could place, with where it stands: built
    /// once per scrub frame here so the twinkle redraws don't recompute it.
    let stars: [(star: Star, at: AltAz)]
    /// The eclipse underway at `time`, if any. Chosen from an array the
    /// timeline already built: this initialiser runs on EVERY scrub frame, and
    /// an eclipse search here would cost orders of magnitude more than the
    /// position lookups below — the same reason the horizon spans read their
    /// rise and set times from `days` rather than searching for them.
    let eclipse: WindowEclipse?
    /// Fraction of the sun's disc the moon covers right now, 0 outside a solar
    /// eclipse. Almanac's `solarObscuration` is a position lookup, not a
    /// search, so it is cheap enough for every scrub frame. Geometric only: a
    /// covered sun below the horizon is clipped like any other.
    let obscuration: Double

    /// `days` is the strip's own day chrome. Both bodies' horizon spans take
    /// their rise and set times from there rather than searching here: this
    /// initialiser runs on every scrub frame, and an Almanac event search
    /// costs two orders of magnitude more than a position lookup (~0.6 ms
    /// against ~0.005 ms). Empty days (an online gate still fetching) means
    /// no spans, and `skyPoint` shows the whole 360°.
    ///
    /// `eclipses` arrives the same way and for the same reason: already found,
    /// by the timeline build, because searching for one here would be far more
    /// expensive than either.
    init(time: Date, latitude: Double, longitude: Double, days: [TimelineDay] = [],
         eclipses: [WindowEclipse] = []) {
        self.latitude = latitude
        self.time = time
        eclipse = eclipses.first { $0.underway(at: time) }
        let observer = try? Observer(latitudeDeg: latitude, longitudeDeg: longitude)
        sun = observer.flatMap { try? sunAltAz(time, observer: $0) }
        stars = observer.map { o in
            brightStars.compactMap { s in
                (try? starAltAz(raDeg: s.ra, decDeg: s.dec, at: time, observer: o)).map { (star: s, at: $0) }
            }
        } ?? []
        moon = observer.flatMap { try? moonAltAz(time, observer: $0) }
        illumination = try? moonIllumination(time)
        obscuration = observer.flatMap { try? solarObscuration(at: time, observer: $0) } ?? 0
        sunSpan = observer.flatMap { obs in
            Self.span(rises: days.compactMap(\.sunrise), sets: days.compactMap(\.sunset),
                      at: time) { try sunAltAz($0, observer: obs) }
        }
        moonSpan = observer.flatMap { obs in
            Self.span(rises: days.compactMap(\.moonrise), sets: days.compactMap(\.moonset),
                      at: time) { try moonAltAz($0, observer: obs) }
        }
    }

    private static func span(rises: [Date], sets: [Date], at time: Date,
                             altAz: (Date) throws -> AltAz) -> HorizonSpan? {
        guard let rise = rises.last(where: { $0 <= time }),
              let set = sets.first(where: { $0 >= time }),
              let riseAz = try? altAz(rise).azDeg,
              let setAz = try? altAz(set).azDeg else { return nil }
        return HorizonSpan(riseAz: riseAz, setAz: setAz)
    }

    /// Fraction of the moon's diameter in the umbra right now, 0 when clear.
    var shadow: Double { eclipse?.shadow(at: time) ?? 0 }
    /// Penumbral shading right now — what a penumbral eclipse has instead.
    var wash: Double { eclipse?.wash(at: time) ?? 0 }

    var moonLightAngle: Double {
        guard let sun, let moon else { return 0 }
        let sunAlt = sun.altDeg * .pi / 180, moonAlt = moon.altDeg * .pi / 180
        let deltaAz = (sun.azDeg - moon.azDeg) * .pi / 180
        // The sun's tangent direction at the moon stays continuous across the screen's azimuth seam.
        let horizontal = cos(sunAlt) * sin(deltaAz) * (latitude >= 0 ? -1.0 : 1.0)
        let vertical = sin(sunAlt) * cos(moonAlt) - cos(sunAlt) * sin(moonAlt) * cos(deltaAz)
        return atan2(-vertical, horizontal)
    }

    /// The altitude the sky is lit for — the sun's, darkened by any eclipse.
    var litAltitude: Double { eclipsedSunAltitude(sun?.altDeg ?? -18, obscuration: obscuration) }
    var paint: SkyPaint { skyPaint(sunAltitude: litAltitude) }
    var opacity: Double { skyOpacity(sunAltitude: litAltitude) }
    var ink: Color { skyUsesDarkInk(sunAltitude: litAltitude) ? SN.navyDeep : .white }
    /// The ground the chrome's coloured inks are lifted against.
    var chromeGround: UInt32 { skyChromeGround(sunAltitude: litAltitude) }
}

struct SkyBackdrop: View {
    let sky: SkyState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let paint = sky.paint
            // The horizon is `plotDepth` above the bottom, less the overlap:
            // the frame runs on to the plot's floor so a body's glow can
            // reach the water.
            let size = CGSize(width: proxy.size.width,
                              height: proxy.size.height - TimelineGeo.plotDepth + skyHorizonOverlap)
            let horizonStop = size.height / proxy.size.height
            ZStack {
                LinearGradient(stops: [.init(color: Color(hex: paint.top), location: 0),
                                       .init(color: Color(hex: paint.bottom), location: horizonStop),
                                       .init(color: Color(hex: paint.bottom), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(sky.opacity)
                if sky.sun != nil {
                    let opacity = starOpacity(sunAltitude: sky.litAltitude)
                    TimelineView(.animation(minimumInterval: 0.125,
                                            paused: opacity == 0 || reduceMotion)) { timeline in
                        let seconds = timeline.date.timeIntervalSinceReferenceDate
                        // The stars share the sun's frame (`skyPoint` with
                        // its span), so the field slides with the bodies as
                        // the scrubber moves. Off-frame and set stars cost
                        // nothing: the canvas clips them.
                        Canvas { context, _ in
                            for (i, placed) in sky.stars.enumerated() {
                                let haze = starHazeOpacity(altitude: placed.at.altDeg)
                                guard haze > 0 else { continue }
                                let point = skyPoint(azimuth: placed.at.azDeg, altitude: placed.at.altDeg,
                                                     latitude: sky.latitude, span: sky.sunSpan, size: size)
                                let radius = max(0.5, 1.6 - 0.3 * CGFloat(placed.star.mag))
                                let twinkle = starTwinkle(index: i, seconds: seconds,
                                                          reduceMotion: reduceMotion)
                                context.fill(Path(ellipseIn: CGRect(x: point.x - radius,
                                                                   y: point.y - radius,
                                                                   width: radius * 2,
                                                                   height: radius * 2)),
                                             with: .color(.white.opacity(
                                                opacity * twinkle * haze)))
                            }
                        }
                    }
                }
                // Below the horizon a body is past an edge; the clip hides it.
                let sunPoint = sky.sun.map {
                    skyPoint(azimuth: $0.azDeg, altitude: $0.altDeg, latitude: sky.latitude,
                             span: sky.sunSpan, pad: sunDiscRadius, size: size)
                }
                if let point = sunPoint {
                    Circle().fill(SN.sun.opacity(0.24)).blur(radius: 12)
                        .frame(width: sunGlowRadius * 2, height: sunGlowRadius * 2).position(point)
                    Circle().fill(SN.sun)
                        .frame(width: sunDiscRadius * 2, height: sunDiscRadius * 2).position(point)
                }
                if let moon = sky.moon, let illumination = sky.illumination {
                    let glowRadius = moonGlowRadius(fraction: illumination.fraction)
                    let truePoint = skyPoint(azimuth: moon.azDeg, altitude: moon.altDeg,
                                             latitude: sky.latitude, span: sky.moonSpan,
                                             pad: moonGlyphSize / 2, size: size)
                    // The symbols are many times the true half-degree, so the
                    // real separation is under a point and any partial would
                    // read as total. In an eclipse the moon sits off the sun by
                    // the covered fraction instead: touching at first contact,
                    // concentric at totality, along its true bearing.
                    let point = sunPoint.map { sun -> CGPoint in
                        guard sky.obscuration > 0 else { return truePoint }
                        let dx = truePoint.x - sun.x, dy = truePoint.y - sun.y, len = hypot(dx, dy)
                        let d = (sunDiscRadius + moonGlyphSize / 2) * (1 - sky.obscuration)
                        return len > 0 ? CGPoint(x: sun.x + dx / len * d, y: sun.y + dy / len * d)
                                       : CGPoint(x: sun.x + d, y: sun.y)
                    } ?? truePoint
                    let toSun = sky.moonLightAngle
                    let glare = moonGlareOpacity(
                        distance: sunPoint.map { hypot($0.x - point.x, $0.y - point.y) } ?? .infinity,
                        obscuration: sky.obscuration)
                    // A new moon's glyph is mostly clear; in front of the sun it
                    // needs a body. The silhouette is the night sky's own black.
                    if sky.obscuration > 0 {
                        Circle().fill(Color(hex: 0x04060F))
                            .frame(width: moonGlyphSize - 2, height: moonGlyphSize - 2).position(point)
                    }
                    // An eclipsed moon dims and warms, and the sky goes quiet
                    // with it: two changes to the one gradient, not a second
                    // element on top of it. The umbra is copper, not black.
                    let eclipsed = sky.eclipse?.underway(at: sky.time) ?? false
                    let dim = 1 - 0.75 * sky.shadow - 0.25 * sky.wash
                    let core: UInt32 = eclipsed ? 0xE8B08C : 0xE6EEFF
                    let halo: UInt32 = eclipsed ? 0xD79A78 : 0xCFE0FF
                    Circle()
                        .fill(RadialGradient(
                            stops: [
                                .init(color: Color(hex: core,
                                                   opacity: 0.95 * (0.1 + illumination.fraction * 0.66) * dim),
                                      location: 0),
                                .init(color: Color(hex: halo,
                                                   opacity: 0.28 * (0.1 + illumination.fraction * 0.66) * dim),
                                      location: 0.45),
                                .init(color: Color(hex: halo, opacity: 0), location: 1),
                            ], center: .center, startRadius: 0, endRadius: glowRadius))
                        .frame(width: glowRadius * 2, height: glowRadius * 2)
                        .position(x: point.x + 4 * cos(toSun), y: point.y + 4 * sin(toSun))
                        .opacity(glare)
                    // `waxing: true` lights the +x limb; the rotation aims it.
                    // Keep the umbra screen-stable; its physical entry direction is #304-adjacent work.
                    MoonGlyph(fraction: illumination.fraction, waxing: true, size: moonGlyphSize,
                              umbra: sky.shadow, wash: sky.wash, shadowTilt: .radians(-toSun))
                        .rotationEffect(.radians(toSun))
                        .position(point)
                        .opacity(glare)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// "42m" / "2h 14m" until `target`, floored at zero.
func countdown(from: Date, to target: Date) -> String {
    let minutes = max(Int(target.timeIntervalSince(from) / 60), 0)
    return minutes < 60
        ? String(localized: "\(minutes)m", comment: "Compact countdown in minutes; 'm' is invariant notation.")
        : String(localized: "\(minutes / 60)h \(minutes % 60)m", comment: "Compact countdown in hours and minutes; 'h' and 'm' are invariant notation.")
}

/// The lit region of a disc of radius `r`, lit from +x. The terminator is
/// the ellipse the lit hemisphere's edge projects to, with half-width
/// r·cos(phase angle): the near half-disc plus that ellipse when gibbous,
/// minus it when crescent. Almanac's `fraction` is (1 + cos i) / 2, so the
/// cosine is 2·fraction − 1 and no angle is needed.
func moonLitPath(fraction: Double, radius r: CGFloat) -> Path {
    let c = CGFloat(2 * fraction - 1)
    let disc = Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
    let near = disc.intersection(Path(CGRect(x: 0, y: -r, width: r, height: 2 * r)))
    let terminator = Path(ellipseIn: CGRect(x: -r * abs(c), y: -r, width: 2 * r * abs(c), height: 2 * r))
    return c >= 0 ? near.union(terminator) : near.subtracting(terminator)
}

/// The umbral shadow's offset for a disc of radius `r`: tangent at zero
/// coverage (2r), concentric once the moon is covered. `coverage` is a
/// fraction of the moon's DIAMETER — what Almanac's `magUmbral` means — and
/// runs above 1 for a total eclipse, where the disc is clamped: there is
/// nowhere further to slide.
///
/// The shadow is an equal-radius disc sliding across, which is the same shape
/// the phase used before #306 replaced it with a real terminator
/// (`moonLitPath`). It stays a disc deliberately: Earth's umbra at the moon's
/// distance really is a circle roughly 2.6 times the moon's diameter, so a
/// straight-edged terminator would be the wrong curve here.
func moonUmbraShift(coverage: Double, radius: CGFloat) -> CGFloat {
    (1 - CGFloat(min(max(coverage, 0), 1))) * 2 * radius
}

/// Phase → name, the prototype's moonName buckets (age thresholds 1.7 d for
/// new/full, 1.4 d for the quarters, over the 29.53 d synodic month).
/// Presentation, not astronomy: Almanac reports `phase`, and where the names
/// change hands is this app's call.
private enum MoonPhaseKind {
    case new, waxingCrescent, firstQuarter, waxingGibbous
    case full, waningGibbous, lastQuarter, waningCrescent
}

private func moonPhaseKind(phase: Double) -> MoonPhaseKind {
    let syn = 29.53
    let age = phase * syn
    let waxing = age < syn / 2
    if age < 1.7 || age > syn - 1.7 { return .new }
    if abs(age - syn / 2) < 1.7 { return .full }
    if abs(age - syn / 4) < 1.4 { return .firstQuarter }
    if abs(age - 3 * syn / 4) < 1.4 { return .lastQuarter }
    let fraction = (1 - cos(2 * .pi * age / syn)) / 2
    if fraction < 0.5 {
        return waxing ? .waxingCrescent : .waningCrescent
    }
    return waxing ? .waxingGibbous : .waningGibbous
}

func moonPhaseName(phase: Double) -> String {
    switch moonPhaseKind(phase: phase) {
    case .new: String(localized: "New Moon", comment: "Moon phase name.")
    case .waxingCrescent: String(localized: "Waxing Crescent", comment: "Moon phase name.")
    case .firstQuarter: String(localized: "First Quarter", comment: "Moon phase name.")
    case .waxingGibbous: String(localized: "Waxing Gibbous", comment: "Moon phase name.")
    case .full: String(localized: "Full Moon", comment: "Moon phase name.")
    case .waningGibbous: String(localized: "Waning Gibbous", comment: "Moon phase name.")
    case .lastQuarter: String(localized: "Last Quarter", comment: "Moon phase name.")
    case .waningCrescent: String(localized: "Waning Crescent", comment: "Moon phase name.")
    }
}

/// The Moon tile's value line while an eclipse is underway. Presentation, the
/// same way `moonPhaseName` is: Almanac reports a kind, the words are ours.
func eclipseTileText(_ kind: LunarEclipseKind) -> String {
    switch kind {
    case .total: String(localized: "Total Eclipse", comment: "Lunar eclipse name.")
    case .partial: String(localized: "Partial Eclipse", comment: "Lunar eclipse name.")
    case .penumbral: String(localized: "Penumbral Eclipse", comment: "Lunar eclipse name.")
    }
}

func solarEclipseTileText(_: SolarEclipseKind) -> String {
    String(localized: "Solar Eclipse", comment: "Solar eclipse name shown in a compact tile.")
}

func solarEclipseName(_ kind: SolarEclipseKind) -> String {
    switch kind {
    case .partial: String(localized: "Partial Solar Eclipse", comment: "Solar eclipse name.")
    case .annular: String(localized: "Annular Solar Eclipse", comment: "Solar eclipse name.")
    case .total: String(localized: "Total Solar Eclipse", comment: "Solar eclipse name.")
    }
}

/// The one-line gloss under the phase name in the Moon sheet. "Penumbral" is a
/// term of art and reads as one; "gibbous" and "first quarter" are terms of art
/// that do NOT, which is worse — the sheet prints them as if everyone knows.
///
/// Keyed on the displayed name rather than re-deriving anything, so
/// `moonPhaseName` stays the only place the age thresholds live and this
/// covers eclipse titles with the same switch. `SkyBackdropTests` pins the
/// names, and pins that every one of them has a line here.
func moonPhaseBlurb(_ name: String) -> String {
    if name == String(localized: "New Moon", comment: "Moon phase name.") { return String(localized: "Between us and the sun, so its lit side faces away.", comment: "Plain-language explanation of a new moon.") }
    if name == String(localized: "Waxing Crescent", comment: "Moon phase name.") { return String(localized: "A sliver, growing a little fuller each night.", comment: "Plain-language explanation of a waxing crescent moon.") }
    if name == String(localized: "First Quarter", comment: "Moon phase name.") { return String(localized: "Half lit — a quarter of the way through the cycle.", comment: "Plain-language explanation of a first-quarter moon.") }
    if name == String(localized: "Waxing Gibbous", comment: "Moon phase name.") { return String(localized: "More than half lit, filling toward full.", comment: "Plain-language explanation of a waxing gibbous moon.") }
    if name == String(localized: "Full Moon", comment: "Moon phase name.") { return String(localized: "Opposite the sun, with the whole face we see lit.", comment: "Plain-language explanation of a full moon.") }
    if name == String(localized: "Waning Gibbous", comment: "Moon phase name.") { return String(localized: "Past full: more than half lit, and shrinking.", comment: "Plain-language explanation of a waning gibbous moon.") }
    if name == String(localized: "Last Quarter", comment: "Moon phase name.") { return String(localized: "Half lit again, three quarters through the cycle.", comment: "Plain-language explanation of a last-quarter moon.") }
    if name == String(localized: "Waning Crescent", comment: "Moon phase name.") { return String(localized: "A thinning sliver, a few nights from new.", comment: "Plain-language explanation of a waning crescent moon.") }
    if name == String(localized: "Penumbral Eclipse", comment: "Lunar eclipse name.") { return String(localized: "In Earth's faint outer shadow — a dimming, not a bite.", comment: "Plain-language explanation of a penumbral lunar eclipse.") }
    if name == String(localized: "Partial Eclipse", comment: "Lunar eclipse name.") { return String(localized: "Part of the moon crossing Earth's dark inner shadow.", comment: "Plain-language explanation of a partial lunar eclipse.") }
    if name == String(localized: "Total Eclipse", comment: "Lunar eclipse name.") { return String(localized: "Fully inside Earth's shadow, reddened by Earth's sunsets.", comment: "Plain-language explanation of a total lunar eclipse.") }
    if name == String(localized: "Solar Eclipse", comment: "Solar eclipse name shown in a compact tile.") { return String(localized: "The new moon crossing the sun as seen from here.", comment: "Plain-language explanation of a solar eclipse.") }
    return ""
}

/// Lunar geometry describes a tendency in tidal range, not a local height prediction.
enum MoonTideKind {
    case perigeanSpring, apogeanSpring, perigeanNeap, apogeanNeap
    case perigean, apogean, spring, neap
}

func moonTideKind(phase: Double, at: Date, perigee: Date?, apogee: Date?) -> MoonTideKind? {
    enum RangeKind { case spring, neap }
    let range: RangeKind? = switch moonPhaseKind(phase: phase) {
    case .new, .full: .spring
    case .firstQuarter, .lastQuarter: .neap
    default: nil
    }
    // Coastal tides can lag the astronomical event by a day or two.
    if let perigee, abs(perigee.timeIntervalSince(at)) <= 2 * 86_400 {
        return switch range {
        case .spring: .perigeanSpring
        case .neap: .perigeanNeap
        case nil: .perigean
        }
    }
    if let apogee, abs(apogee.timeIntervalSince(at)) <= 2 * 86_400 {
        return switch range {
        case .spring: .apogeanSpring
        case .neap: .apogeanNeap
        case nil: .apogean
        }
    }
    return switch range {
    case .spring: .spring
    case .neap: .neap
    case nil: nil
    }
}

func moonTideLabel(phase: Double, at: Date, perigee: Date?, apogee: Date?) -> String? {
    switch moonTideKind(phase: phase, at: at, perigee: perigee, apogee: apogee) {
    case .perigeanSpring: String(localized: "Perigean spring tide", comment: "Astronomical tidal-range tendency near lunar perigee.")
    case .apogeanSpring: String(localized: "Apogean spring tide", comment: "Astronomical tidal-range tendency near lunar apogee.")
    case .perigeanNeap: String(localized: "Perigean neap tide", comment: "Astronomical tidal-range tendency near lunar perigee.")
    case .apogeanNeap: String(localized: "Apogean neap tide", comment: "Astronomical tidal-range tendency near lunar apogee.")
    case .perigean: String(localized: "Perigean tide", comment: "Astronomical tidal-range tendency near lunar perigee.")
    case .apogean: String(localized: "Apogean tide", comment: "Astronomical tidal-range tendency near lunar apogee.")
    case .spring: String(localized: "Spring tide", comment: "Astronomical tidal-range tendency around a new or full moon.")
    case .neap: String(localized: "Neap tide", comment: "Astronomical tidal-range tendency around a quarter moon.")
    case nil: nil
    }
}

/// The moon glyph: the lit region over a dark disc that stays
/// semi-transparent to show the sky. Lit on the right while waxing, the
/// northern convention; the sky passes `waxing: true` and rotates toward the sun.
///
/// `umbra` and `wash` add the eclipse on top of all that, and only on top:
/// at zero the glyph is exactly what it draws for every other night.
struct MoonGlyph: View {
    let fraction: Double
    let waxing: Bool
    var size: CGFloat = 20
    /// Fraction of the moon's diameter inside the umbra — `WindowEclipse.shadow(at:)`.
    /// Zero draws exactly what this glyph has always drawn.
    var umbra: Double = 0
    /// Penumbral shading, 0…1 — `WindowEclipse.wash(at:)`. The whole disc
    /// warms and dims, which for a penumbral eclipse is the ONLY mark there
    /// is: it has no umbral contact, so `umbra` stays 0 throughout.
    var wash: Double = 0
    /// Rotation applied to the SHADOW alone. The sky dome rotates the whole
    /// glyph to aim the lit limb at the sun; the umbra must not follow it,
    /// because an eclipse happens at the anti-solar point. Zero everywhere
    /// else, where nothing rotates the glyph at all.
    var shadowTilt: Angle = .zero

    var body: some View {
        let r = size / 2 - 1
        ZStack {
            Circle().fill(SN.moonLimb.opacity(0.18))
            moonLitPath(fraction: fraction, radius: r).offsetBy(dx: r, dy: r)
                .fill(SN.foam)
                .scaleEffect(x: waxing ? 1 : -1)
            if wash > 0 || umbra > 0 {
                // The eclipse sits OVER the lit region, not inside it: the
                // penumbra dims whatever the phase left lit, and the umbra is a
                // deeper shadow inside the penumbra rather than a separate
                // event. Clipped to the disc, so neither escapes the moon.
                ZStack {
                    if wash > 0 {
                        Circle().fill(SN.umbra.opacity(0.42 * min(max(wash, 0), 1)))
                    }
                    if umbra > 0 {
                        Circle().fill(SN.umbra)
                            .offset(x: moonUmbraShift(coverage: umbra, radius: r))
                    }
                }
                .rotationEffect(shadowTilt)
                .clipShape(Circle())
            }
        }
        .frame(width: 2 * r, height: 2 * r)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SolarEclipseGlyph: View {
    let obscuration: Double
    var size: CGFloat = 20

    var body: some View {
        let r = size / 2 - 1
        ZStack {
            Circle().fill(SN.sun)
            // ponytail: equal-disc overlap; carry apparent radii if this mark becomes quantitative.
            Circle().fill(Color(hex: 0x04060F))
                .offset(x: moonUmbraShift(coverage: obscuration, radius: r))
        }
        .frame(width: 2 * r, height: 2 * r)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Aug 7" — the when-row's date. No weekday and no TODAY/TOMORROW: the
/// scrubber's day headers already carry those, and repeating them here read
/// as "SUN · SUN, AUG 9" the moment you scrubbed (design feedback 2026-08-07).
func monthDay(_ date: Date, _ tz: TimeZone,
              locale: Locale = .autoupdatingCurrent) -> String {
    localizedFormatter("MMMd", tz, locale: locale).string(from: date)
}

func monthDayYear(_ date: Date, _ tz: TimeZone,
                  locale: Locale = .autoupdatingCurrent) -> String {
    localizedFormatter("yMMMd", tz, locale: locale).string(from: date)
}

/// The lead's localized date and clock. The date remains visible when a strip
/// centered on night has both flanking day headers off-screen.
///
/// The line is centered under the reading, so a one-digit hour would narrow
/// the string and shift every glyph as the scrub crosses 9:59→10:00 — many
/// times in one pan. A figure space — digit-wide under `monospacedDigit` —
/// stands in for the missing digit. The day's digits move too, but once per
/// midnight rather than per pan, so they go unpadded.
func leadWhen(_ date: Date, _ tz: TimeZone,
              locale: Locale = .autoupdatingCurrent) -> String {
    var time = chartTime(date, tz, locale: locale)
    if let digit = time.firstIndex(where: \.isNumber),
       time[digit...].prefix(while: \.isNumber).count == 1 {
        time.insert("\u{2007}", at: digit)
    }
    return "\(monthDay(date, tz, locale: locale)) · \(time)"
}

/// The localized range bar names the last day shown and omits the year only
/// when both ends fall in today's year.
func weekRangeLabel(anchor: Date, today: Date, tz: TimeZone,
                    locale: Locale = .autoupdatingCurrent) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let last = cal.date(byAdding: .day, value: Int(Timeline.scheduleDays) - 1, to: anchor)!

    let sameYear = cal.isDate(anchor, equalTo: last, toGranularity: .year)
        && cal.isDate(anchor, equalTo: today, toGranularity: .year)
    let formatter = DateIntervalFormatter()
    formatter.locale = locale
    formatter.timeZone = tz
    formatter.dateTemplate = sameYear ? "MMMd" : "yMMMd"
    return formatter.string(from: anchor, to: last)
}

/// One Weather-style readout tile (tide + current): eyebrow with the glyph in
/// the far corner, the number, a caption. The glyph colours itself; the value
/// takes `valueColor` — white, or amber for a provisional reading.
enum ReadoutType {
    /// The page's one reading: what sits under the centerline. 44 at the
    /// default text size; `LeadCard` scales it with the large title.
    static func lead(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded) }
    static let leadUnit: Font = .title2.weight(.light)
    /// A tile's value.
    static let hero: Font = .system(.title2, design: .rounded).weight(.medium)
    /// A tile whose value is words rather than a reading.
    static let tileText: Font = .system(.body, design: .rounded).weight(.medium)
    static let unit: Font = .title3.weight(.light)
}

/// The hero: the reading under the centerline, which runs up into it. The
/// eyebrow — the state and its glyph — leads, the value is the only large
/// thing, and the time sits alone beneath it on the centerline.
///
/// `value` is optional because a derived gate predicts no speed: its lead is
/// the eyebrow over the time, with the big line left out rather than filled
/// with a placeholder number.
struct LeadCard<Eyebrow: View>: View {
    var value: String? = nil
    var unit: String? = nil
    let time: String
    var valueColor: Color = .white
    var timeColor: Color = SN.foam.opacity(0.55)
    @ViewBuilder var eyebrow: () -> Eyebrow
    @ScaledMetric(relativeTo: .largeTitle) private var leadSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) { eyebrow() }
                .font(.footnote.weight(.semibold))
            if let value {
                (Text(value).font(ReadoutType.lead(leadSize).monospacedDigit())
                    + Text(unit.map { " \($0)" } ?? "").font(ReadoutType.leadUnit))
                    .foregroundStyle(valueColor)
            }
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(timeColor)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail-reading")
        .accessibilityValue(time.replacingOccurrences(of: "\u{2007}", with: ""))
    }
}

/// The eyebrow's word, in the weight and ink every lead shares.
func leadState(_ text: String, ink: Color = SN.foam) -> Text {
    Text(text).fontWeight(.medium).foregroundStyle(ink.opacity(0.85))
}

struct CommentaryStop: Equatable {
    let time: Date
    let label: String
    var spokenLabel: String? = nil
    var systemImage: String? = nil
}

struct CommentaryContent: Equatable {
    let label: String
    var duration: String? = nil
    var systemImage: String? = nil
    let accessibilityLabel: String
}

func commentaryEventStop(_ label: String, at time: Date,
                         prefix: String = "") -> CommentaryStop {
    let visible: String
    let spoken: String
    let systemImage: String
    switch label {
    case "Sunrise": (visible, spoken, systemImage) = (String(localized: "Sunrise", comment: "Next-event label."), String(localized: "Sunrise", comment: "VoiceOver next-event label."), "sunrise")
    case "Sunset": (visible, spoken, systemImage) = (String(localized: "Sunset", comment: "Next-event label."), String(localized: "Sunset", comment: "VoiceOver next-event label."), "sunset")
    case "Slack": (visible, spoken, systemImage) = (String(localized: "Slack", comment: "Current event: water is near zero speed."), String(localized: "Slack current", comment: "VoiceOver current-event label."), "arrow.right.and.line.vertical.and.arrow.left")
    case "Flood": (visible, spoken, systemImage) = (String(localized: "Flood", comment: "Flood-current event label."), String(localized: "Flood current", comment: "VoiceOver current-event label."), "arrow.forward")
    case "Ebb": (visible, spoken, systemImage) = (String(localized: "Ebb", comment: "Ebb-current event label."), String(localized: "Ebb current", comment: "VoiceOver current-event label."), "arrow.backward")
    case "Max flood": (visible, spoken, systemImage) = (String(localized: "Max flood", comment: "Maximum flood-current event label."), String(localized: "Maximum flood current", comment: "VoiceOver current-event label."), "arrow.forward")
    case "Max ebb": (visible, spoken, systemImage) = (String(localized: "Max ebb", comment: "Maximum ebb-current event label."), String(localized: "Maximum ebb current", comment: "VoiceOver current-event label."), "arrow.backward")
    default: return CommentaryStop(time: time, label: prefix + label)
    }
    return CommentaryStop(time: time, label: prefix + visible,
                          spokenLabel: prefix + spoken,
                          systemImage: systemImage)
}

func commentaryContent(_ stop: CommentaryStop, from scrub: Date,
                       locale: Locale = .autoupdatingCurrent) -> CommentaryContent {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = locale
    formatter.calendar = calendar

    let duration = countdown(from: scrub, to: stop.time)
    let spokenDuration = formatter.string(from: max(0, stop.time.timeIntervalSince(scrub))) ?? duration
    return CommentaryContent(label: stop.label, duration: duration,
                             systemImage: stop.systemImage,
                             accessibilityLabel: String(localized: "\(stop.spokenLabel ?? stop.label) in \(spokenDuration)", comment: "VoiceOver label for the next tide, current, or sun event. Values are the event and a localized duration."))
}

/// The stop the commentary names and its tap walks to: the water's next stop,
/// or the sun's next rise or set when that comes first. Dark is an event a
/// reader plans around the same way they plan around a slack.
func nextCommentaryStop(_ water: CommentaryStop?,
                        sun days: [TimelineDay],
                        after scrub: Date) -> CommentaryStop? {
    // Strictly after the scrub, so landing on a stop advances to the next.
    let cutoff = scrub.addingTimeInterval(1)
    let sun = days
        .flatMap { [($0.sunrise, "Sunrise"), ($0.sunset, "Sunset")] }
        .compactMap { time, word in time.map { commentaryEventStop(word, at: $0) } }
    return (sun + [water].compactMap { $0 })
        .filter { $0.time > cutoff }
        .min { $0.time < $1.time }
}

/// What comes next, centred on the reading line in the strip's chrome row.
/// Tapping scrubs to it. The strip owns the settle fade for both chrome pills.
struct Commentary: View {
    let content: CommentaryContent?
    /// Set when the text is a warning about the scrub instant — a fast tide —
    /// rather than the next event; the ramp's colour, so the pill explains
    /// the line under it.
    var tint: Color? = nil
    var ink: Color = SN.foam
    let onTap: () -> Void

    var body: some View {
        Group {
            if let content {
                // Glass, not a fill: it floats over the curve and its labels,
                // and has to stay legible over both. The button style owns the
                // glass — interactive glass on the label competes with the
                // button for the tap and drops every other one.
                Button(action: onTap) {
                    HStack(spacing: 4) {
                        Text(content.label)
                        if let systemImage = content.systemImage {
                            Image(systemName: systemImage)
                                .accessibilityHidden(true)
                        }
                        if let duration = content.duration {
                            Text(duration)
                        }
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint ?? ink)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                // The visible capsule stays compact; the semantic target is
                // the platform's 44 points (spec § 15).
                .frame(height: Timeline.pillTarget)
                // `.ignore`, not `.combine`: a combined element keeps the
                // button's own frame, so the 44-point row would not be the
                // target.
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Activate", onTap)
                .accessibilityLabel(content.accessibilityLabel)
                .accessibilityIdentifier("commentary")
            }
        }
    }
}

/// Between the strip and the schedule: the one number this station kind has
/// to add beside the moon that drives it. `primary` is the caller's — a tide's
/// swing ("Range"), a current's next maximum ("Next max"); a derived gate has
/// no number at all and passes nil, leaving the moon on its own.
struct SummaryTiles: View {
    var primary: (label: String, value: String, caption: String)? = nil
    /// The illumination the SKY already computed, rather than a second lookup
    /// per frame for the same instant (#299).
    let moon: MoonIllumination?
    /// The scrub time itself: the sheet searches from it, and the eclipse's
    /// shadow is read at it. `moon` cannot supply this — it is a phase, not a
    /// moment.
    let at: Date
    /// The eclipse underway at `at`, from the timeline: it renames the value
    /// line and shadows the glyph.
    var eclipse: WindowEclipse? = nil
    var solarEclipse: WindowSolarEclipse? = nil
    var solarObscuration: Double = 0
    /// Handed down from the scaffold. Without it — and without a position —
    /// the tile stays inert, which is what the tests and previews get.
    var onJump: ((Date) -> Void)? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// Read HERE, inside the presenting hierarchy where the scaffold set it,
    /// and handed to the sheet as a value — see `MoonDetailSheet.tz`.
    @Environment(\.timeZone) private var tz
    @State private var apsides: (day: Date, perigee: Date?, apogee: Date?)?

    /// Non-nil only when the caller gave both somewhere to go and somewhere to
    /// stand: the sheet needs an `Observer`, and this view is the only thing
    /// between the detail view and it.
    private var sheet: (() -> AnyView)? {
        guard let onJump, let latitude, let longitude else { return nil }
        let tz = tz
        return { AnyView(MoonDetailSheet(at: at, eclipse: eclipse,
                                         solarEclipse: solarEclipse,
                                         solarObscuration: solarObscuration,
                                         latitude: latitude, longitude: longitude,
                                         tz: tz, onJump: onJump)) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let primary {
                ReadoutTile(label: primary.label, caption: primary.caption,
                            accessibility: primary.label) {
                    EmptyView()
                } value: {
                    Text(primary.value).font(ReadoutType.hero.monospacedDigit())
                }
            }
            // Almanac throws only outside 1950–2101; the tile drops rather
            // than the row, so a primary reading still stands on its own.
            if let moon {
                let day = dayLocal(at, tz)
                let dates = apsides?.day == day ? apsides : nil
                ReadoutTile(label: String(localized: "Moon", comment: "Moon summary tile label."), caption: moonTideLabel(
                    phase: moon.phase, at: at, perigee: dates?.perigee, apogee: dates?.apogee)
                    ?? String(localized: "\(Int((moon.fraction * 100).rounded()))% lit", comment: "Moon illumination percentage. The integer is a percentage."),
                            accessibility: String(localized: "Moon", comment: "VoiceOver moon summary label."), detail: sheet) {
                    if solarEclipse != nil {
                        SolarEclipseGlyph(obscuration: solarObscuration, size: 14)
                    } else {
                        MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 14,
                                  umbra: eclipse?.shadow(at: at) ?? 0,
                                  wash: eclipse?.wash(at: at) ?? 0)
                    }
                } value: {
                    // Words, not a number: "Waning Crescent" has to fit on one
                    // line where "7.6 ft" does, so it sits well below the hero.
                    Text(solarEclipse.map { solarEclipseTileText($0.kind) }
                            ?? eclipse.map { eclipseTileText($0.kind) }
                            ?? moonPhaseName(phase: moon.phase))
                        .font(ReadoutType.tileText)
                }
            }
        }
        .task(id: dayLocal(at, tz)) {
            guard moon != nil else { return }
            let day = dayLocal(at, tz)
            let dates = await Task.detached(priority: .utility) { moonApsides(around: day) }.value
            apsides = (day, dates.perigee, dates.apogee)
        }
    }
}

struct ReadoutTile<Glyph: View, Value: View>: View {
    let label: String
    let caption: String
    var valueColor: Color = .white
    var captionColor: Color = SN.foam.opacity(0.55)
    /// Spoken for the eyebrow row, glyph included; the tile then reads as one
    /// element, this, the value and the caption in order.
    let accessibility: String
    /// A tile with somewhere to go: a chevron, a tap, and a sheet. Only the
    /// Moon tile has one so far — `Range` and `Next max` stay inert until they
    /// have something to say that the tile itself doesn't already.
    var detail: (() -> AnyView)? = nil
    @ViewBuilder var glyph: () -> Glyph
    @ViewBuilder var value: () -> Value
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel(text: label, color: SN.foam.opacity(0.55))
                if detail != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SN.foam.opacity(0.4))
                }
                Spacer()
                HStack(spacing: 4) { glyph() }
                    .font(.caption.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibility)
            ZStack(alignment: .leading) {
                Text(verbatim: "0").font(ReadoutType.hero).hidden()
                value()
            }
            .foregroundStyle(valueColor)
            Text(caption)
                .font(.caption.monospacedDigit())
                .foregroundStyle(captionColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(detail != nil ? .isButton : [])
        .contentShape(Rectangle())
        // A tap gesture, not a Button: Button press tracking goes dead in the
        // iPad split layout's detail column, the same reason MultiDaySchedule's
        // rows use one.
        .onTapGesture { if detail != nil { showDetail = true } }
        .sheet(isPresented: $showDetail) { detail?() }
    }
}
