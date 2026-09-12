// Slackwater — GPL v3. Detail-view chrome and list state; the palette and formatters live in Palette.swift so the widget can share them.
import Almanac
import SwiftUI
import WidgetKit

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
/// clear once it is past the sun's glow. A real solar eclipse fades too —
/// gate on an Almanac separation once it has one.
func moonGlareOpacity(distance: CGFloat) -> Double {
    let touching = sunDiscRadius + moonGlyphSize / 2
    let clear = sunGlowRadius + moonGlyphSize / 2
    return max(0, min(1, Double((distance - touching) / (clear - touching))))
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

private func mixedHex(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
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

    var paint: SkyPaint { skyPaint(sunAltitude: sun?.altDeg ?? -18) }
    var opacity: Double { skyOpacity(sunAltitude: sun?.altDeg ?? -18) }
    var ink: Color { skyUsesDarkInk(sunAltitude: sun?.altDeg ?? -18) ? SN.navyDeep : .white }
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
                if let altitude = sky.sun?.altDeg {
                    let opacity = starOpacity(sunAltitude: altitude)
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
                    let point = skyPoint(azimuth: moon.azDeg, altitude: moon.altDeg,
                                         latitude: sky.latitude, span: sky.moonSpan,
                                         pad: moonGlyphSize / 2, size: size)
                    let toSun = sky.moonLightAngle
                    let glare = sunPoint.map { hypot($0.x - point.x, $0.y - point.y) } ?? .infinity
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
                        .opacity(moonGlareOpacity(distance: glare))
                    // `waxing: true` lights the +x limb; the rotation aims it.
                    // Keep the umbra screen-stable; its physical entry direction is #304-adjacent work.
                    MoonGlyph(fraction: illumination.fraction, waxing: true, size: moonGlyphSize,
                              umbra: sky.shadow, wash: sky.wash, shadowTilt: .radians(-toSun))
                        .rotationEffect(.radians(toSun))
                        .position(point)
                        .opacity(moonGlareOpacity(distance: glare))
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
    return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
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
func moonPhaseName(phase: Double) -> String {
    let syn = 29.53
    let age = phase * syn
    let waxing = age < syn / 2
    if age < 1.7 || age > syn - 1.7 { return "New Moon" }
    if abs(age - syn / 2) < 1.7 { return "Full Moon" }
    if abs(age - syn / 4) < 1.4 { return "First Quarter" }
    if abs(age - 3 * syn / 4) < 1.4 { return "Last Quarter" }
    let fraction = (1 - cos(2 * .pi * age / syn)) / 2
    if fraction < 0.5 { return waxing ? "Waxing Crescent" : "Waning Crescent" }
    return waxing ? "Waxing Gibbous" : "Waning Gibbous"
}

/// The Moon tile's value line while an eclipse is underway. Presentation, the
/// same way `moonPhaseName` is: Almanac reports a kind, the words are ours.
func eclipseTileText(_ kind: LunarEclipseKind) -> String {
    switch kind {
    case .total: "Total Eclipse"
    case .partial: "Partial Eclipse"
    case .penumbral: "Penumbral Eclipse"
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

/// "Aug 7" — the when-row's date. No weekday and no TODAY/TOMORROW: the
/// scrubber's day headers already carry those, and repeating them here read
/// as "SUN · SUN, AUG 9" the moment you scrubbed (design feedback 2026-08-07).
func monthDay(_ date: Date, _ tz: TimeZone) -> String {
    formatter("MMM d", tz).string(from: date)
}

/// "Sep 10 · 3:42pm" — the lead's when. The date is here because a strip
/// centered on night has both flanking day headers off-screen. Date only, no
/// weekday and no TODAY/TOMORROW, for the reason `monthDay` records.
///
/// The line is centered under the reading, so a one-digit hour would narrow
/// the string and shift every glyph as the scrub crosses 9:59→10:00 — many
/// times in one pan. A figure space — digit-wide under `monospacedDigit` —
/// stands in for the missing digit. The day's digits move too, but once per
/// midnight rather than per pan, so they go unpadded.
func leadWhen(_ date: Date, _ tz: TimeZone) -> String {
    var time = chartTime(date, tz)
    if time.prefix(while: \.isNumber).count == 1 {
        time = "\u{2007}" + time
    }
    return "\(monthDay(date, tz)) · \(time)"
}

/// The schedule's span, as the range bar prints it: `Aug 11 – 17`,
/// `Aug 28 – Sep 3`, `Dec 29 – Jan 4, 2027`.
///
/// The second date is the LAST DAY SHOWN — `anchor + 6` — not the exclusive
/// `scheduleRange` upper bound. The window is rolling rather than a calendar
/// week, so this bar is the only thing on screen that says what span you are
/// looking at; naming a day that is not in the list below it would be the
/// same defect as calling a Tue→Mon window "Week of Aug 9 – 16".
///
/// The month repeats only when it changes, and the year appears only when the
/// range crosses one — a bar that printed "2026" every week would be teaching
/// the user to stop reading it.
func weekRangeLabel(anchor: Date, tz: TimeZone) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let last = cal.date(byAdding: .day, value: Int(Timeline.scheduleDays) - 1, to: anchor)!

    let head = formatter("MMM d", tz).string(from: anchor)

    let sameMonth = cal.isDate(anchor, equalTo: last, toGranularity: .month)
    let sameYear = cal.isDate(anchor, equalTo: last, toGranularity: .year)
    let tailPattern = sameYear ? (sameMonth ? "d" : "MMM d") : "MMM d, yyyy"
    return "\(head) – \(formatter(tailPattern, tz).string(from: last))"
}

/// One Weather-style readout tile (tide + current): eyebrow with the glyph in
/// the far corner, the number, a caption. The glyph colours itself; the value
/// takes `valueColor` — white, or amber for a provisional reading.
enum ReadoutType {
    /// The page's one reading: what sits under the centerline.
    static let lead: Font = .system(size: 44, weight: .medium, design: .rounded)
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
    var value: Text? = nil
    let time: String
    var valueColor: Color = .white
    var timeColor: Color = SN.foam.opacity(0.55)
    @ViewBuilder var eyebrow: () -> Eyebrow

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) { eyebrow() }
                .font(.footnote.weight(.semibold))
            value?.foregroundStyle(valueColor)
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(timeColor)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail-reading")
    }
}

/// The eyebrow's word, in the weight and ink every lead shares.
func leadState(_ text: String, ink: Color = SN.foam) -> Text {
    Text(text).fontWeight(.medium).foregroundStyle(ink.opacity(0.85))
}

/// "Low tide in 28m" while the reading is now; "Low tide 3h 28m later" once
/// the scrub has left it — "in" counts from the reader, "later" from wherever
/// on the strip they are looking.
func commentaryText(_ event: String, at time: Date, from scrub: Date, now: Date) -> String {
    let gap = countdown(from: scrub, to: time)
    return scrubbedAway(scrub, from: now) ? "\(event) \(gap) later" : "\(event) in \(gap)"
}

/// The stop the commentary names and its tap walks to: the water's next stop,
/// or the sun's next rise or set when that comes first. Dark is an event a
/// reader plans around the same way they plan around a slack.
func nextCommentaryStop(_ water: (time: Date, text: String)?,
                        sun days: [TimelineDay],
                        after scrub: Date) -> (time: Date, text: String)? {
    // Strictly after the scrub, so landing on a stop advances to the next.
    let cutoff = scrub.addingTimeInterval(1)
    let sun = days
        .flatMap { [($0.sunrise, "Sunrise"), ($0.sunset, "Sunset")] }
        .compactMap { time, word in time.map { (time: $0, text: word) } }
    return (sun + [water].compactMap { $0 })
        .filter { $0.time > cutoff }
        .min { $0.time < $1.time }
}

/// What comes next, centred on the reading line in the strip's chrome row.
/// Tapping scrubs to it. The strip owns the settle fade for both chrome pills.
struct Commentary: View {
    let text: String?
    /// Set when the text is a warning about the scrub instant — a fast tide —
    /// rather than the next event; the ramp's colour, so the pill explains
    /// the line under it.
    var tint: Color? = nil
    var ink: Color = SN.foam
    let onTap: () -> Void

    var body: some View {
        Group {
            if let text {
                // Glass, not a fill: it floats over the curve and its labels,
                // and has to stay legible over both. The button style owns the
                // glass — interactive glass on the label competes with the
                // button for the tap and drops every other one.
                Button(action: onTap) {
                    Text(text)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(tint ?? ink)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
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
    /// Handed down from the scaffold. Without it — and without a position —
    /// the tile stays inert, which is what the tests and previews get.
    var onJump: ((Date) -> Void)? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// Read HERE, inside the presenting hierarchy where the scaffold set it,
    /// and handed to the sheet as a value — see `MoonDetailSheet.tz`.
    @Environment(\.timeZone) private var tz

    /// Non-nil only when the caller gave both somewhere to go and somewhere to
    /// stand: the sheet needs an `Observer`, and this view is the only thing
    /// between the detail view and it.
    private var sheet: (() -> AnyView)? {
        guard let onJump, let latitude, let longitude else { return nil }
        let tz = tz
        return { AnyView(MoonDetailSheet(at: at, eclipse: eclipse,
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
                ReadoutTile(label: "Moon", caption: "\(Int((moon.fraction * 100).rounded()))% lit",
                            accessibility: "Moon", detail: sheet) {
                    MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 14,
                              umbra: eclipse?.shadow(at: at) ?? 0,
                              wash: eclipse?.wash(at: at) ?? 0)
                } value: {
                    // Words, not a number: "Waning Crescent" has to fit on one
                    // line where "7.6 ft" does, so it sits well below the hero.
                    Text(eclipse.map { eclipseTileText($0.kind) }
                            ?? moonPhaseName(phase: moon.phase))
                        .font(ReadoutType.tileText)
                }
            }
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
            value()
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

// MARK: - The scrub-detail scaffold (tide / current / derived gate / online gate)

private struct DetailTopHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The four scrub details' shared anatomy: header, the caller's lead reading,
/// the strip, the caller's links (summary tiles, tide-at-port), the rolling
/// schedule card, and the bottom slot (footer — or the
/// online gate's honesty card, which is also what shows while `timeline` is
/// nil).
///
/// Return-to-now is the caller's, not the scaffold's: it resets the window's
/// `anchor` as well as the scrub, and only the detail view holds that. The
/// strip takes it directly.
struct ScrubDetailScaffold<Above: View, Card: View, Links: View, Bottom: View>: View {
    let name: String
    let region: String
    let favoriteId: String
    let tz: TimeZone
    let timeline: TimelineData?
    let entries: (TimelineData) -> [ScheduleEntry]
    @Binding var scrubTime: Date
    /// The window's anchor. The scaffold moves it (via the picker) but does not
    /// own it — it lives in the detail view, alongside return-to-now.
    @Binding var anchor: Date
    /// Whether the week-range bar stays up when there is no timeline. The
    /// three constituent-backed details always have somewhere to go; an
    /// online gate with nothing downloaded yet does not — every week the
    /// picker can reach lands on the same honesty card (#172).
    var canPickDate = true
    /// Fired when the picker OPENS, before a date is chosen. Only an online
    /// gate has anything to do here (speculatively fetch the next block); the
    /// other three are constituents and pass a no-op.
    var onPickerOpen: () -> Void = {}
    /// Fired after the anchor moves, with the picked date. The three
    /// `@State`-backed views rebuild here; the online gate re-checks coverage.
    var onPicked: (Date) -> Void = { _ in }
    /// A detail can supply its scrub-time sky without changing the scaffold's
    /// generic signature.
    var topBackdrop: AnyView? = nil
    @State private var topHeight: CGFloat = 0
    @State private var showPicker = false
    /// A shared link's moment (`pendingScrubInstant`), held from this view's
    /// appear until the caller's first timeline lands.
    @State private var linkedInstant: Date?
    /// Between the header and the scrub card (the fast-answer amber card).
    @ViewBuilder var above: () -> Above
    /// Readout + strip (+ any notes), in the caller's order — everything in
    /// the scrub card above its shared tail.
    @ViewBuilder var card: (TimelineData) -> Card
    /// Under the strip, above the schedule (summary tiles, TideAtPortLink).
    /// Handed the same `TimelineData` the card gets, so a consumer reads the
    /// timeline the page is already drawing rather than deriving a second one —
    /// and `jump(to:)`, for the Moon sheet's eclipse rows.
    @ViewBuilder var links: (TimelineData, @escaping (Date) -> Void) -> Links
    /// Below the schedule card; each element gets the standard 14pt top gap.
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        // GeometryReader sits inside the safe area (only the ScrollView below
        // ignores it), so the proxy reads the real top inset for DetailHeader —
        // per device and per iPad split-view pane, live across rotation.
        GeometryReader { geo in
            ScrollView {
                ZStack(alignment: .top) {
                    if let topBackdrop, let timeline {
                        // Down to the plot's floor, so a body's glow reaches
                        // the water; the strip paints the water over it.
                        topBackdrop
                            .frame(maxWidth: .infinity)
                            .frame(height: topHeight + TimelineGeo(data: timeline).bodyBottom)
                    }
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            DetailHeader(name: name, region: region,
                                         favoriteId: favoriteId,
                                         topSafeInset: geo.safeAreaInsets.top,
                                         shareInstant: scrubTime, tz: tz)
                            above()
                        }
                            .background {
                                GeometryReader { top in
                                    Color.clear.preference(key: DetailTopHeightKey.self,
                                                           value: top.size.height)
                                }
                            }
                        if let timeline {
                            scrubCard(timeline)
                            scheduleCard(timeline)
                                .padding(.top, 14)
                        } else if anchor != .distantPast, canPickDate {
                        // #67 item 2: no timeline means the caller is showing its
                        // honesty card below — but the bar (and its picker) need
                        // no timeline, and without them that card is a dead end
                        // with no way back to a covered week — when there IS one
                        // (`canPickDate`). Guarded on anchor:
                        // all four details start at .distantPast (real anchor
                        // arrives in onAppear), and weekRangeLabel force-unwraps
                        // a Calendar.date(byAdding:) against it — the pre-onAppear
                        // frame must render nothing here, as it always has.
                            WeekRangeBar(anchor: anchor, today: todayLocal(tz), tz: tz,
                                         onTap: { showPicker = true })
                                .background(SN.cardFill)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(SN.cardStroke, lineWidth: 0.5))
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        }
                        bottom()
                            .padding(.top, 14)
                        if let item = StationItem.byId[favoriteId] {
                            NearbySection(item: item)
                                .padding(.top, 28)
                        }
                    }
                    .padding(.bottom, 42)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(CanvasBackground())
            .onPreferenceChange(DetailTopHeightKey.self) { topHeight = $0 }
            .environment(\.timeZone, tz)
            .environment(\.openWeekPicker, { showPicker = true })
            .toolbar(.hidden, for: .navigationBar)
            // A shared link's moment (#187). Taken on appear so it reaches only
            // the detail the link opened, but APPLIED once the timeline exists:
            // the caller's own onAppear sets the anchor and builds, and SwiftUI
            // does not promise which onAppear runs first — a scrub set here
            // would be built over. Waiting for the timeline is deterministic,
            // and for an online gate it is also when there is anything to
            // scrub.
            .onAppear {
                if let t = pendingScrubInstant ?? seededScrubInstant {
                    pendingScrubInstant = nil
                    linkedInstant = t
                }
            }
            .onChange(of: timeline == nil) { _, isNil in
                guard !isNil, let t = linkedInstant else { return }
                linkedInstant = nil
                jump(to: t)
            }
            .sheet(isPresented: $showPicker) {
                WeekPickerSheet(anchor: $anchor, tz: tz, onOpen: onPickerOpen, onPick: { picked in
                    // Park the centerline on the picked week when it isn't already
                    // there. The strip does NOT self-correct: `data.x(_:)` and
                    // `data.time(atX:)` are exact inverses, so the programmatic
                    // scroll to `scrubTime` and the scroll callback that reads it
                    // back are a fixed point, and `contentSize` is set once in
                    // `makeUIView` — nothing re-clamps an off-window offset. Left
                    // alone, picking a month out draws a blank strip under a
                    // readout frozen on the first sample, with the return-to-now
                    // button hidden because `scrubTime` is still `live`.
                    //
                    // `Timeline.window` asks the question, not hand-rolled hours:
                    // it is the span the strip actually draws. A pick that lands
                    // on today leaves an in-window `scrubTime` alone, so it stays
                    // live and the return-to-now slot stays correctly empty.
                    //
                    // NOON of the picked day, not its midnight. Midnight is the
                    // window's first instant, so `x(scrubTime) - width/2` is
                    // negative and the strip opens on half a viewport of dead space
                    // before the curve starts — and the readout reads "12:00 AM",
                    // which looks like a boundary artefact rather than a reading.
                    // With the unconditional 48h back-pad, noon has 60h (1080pt) of
                    // data behind it — no pane is that wide, so the park never
                    // opens on dead space (#67 item 1). Calendar noon, not +12h:
                    // a spring-forward day would otherwise open at 13:00.
                    let week = Timeline.window(anchor: picked)
                    if scrubTime < week.start || scrubTime > week.end {
                        scrubTime = noonLocal(picked, tz)
                    }
                    onPicked(picked)
                })
            }
        }
    }

    /// Park the centerline on `t`, moving the window when `t` is not on it.
    ///
    /// Shared by the two things that arrive holding an instant: a shared link
    /// (#187) and the Moon sheet's eclipse rows (#222). The window test is the
    /// picker's rule inverted — move only when the moment isn't already on the
    /// strip, so a jump to later today doesn't open on a week bar reading
    /// "not this week".
    private func jump(to t: Date) {
        scrubTime = t
        let week = Timeline.window(anchor: anchor)
        if t < week.start || t > week.end {
            anchor = dayLocal(t, tz)
            onPicked(anchor)
        }
    }

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full bleed, no chrome: the curve is the hero and the page is its
            // frame. No "‹ swipe to scrub ›" label here, and none is coming
            // back (#58): "scrubber" is audio-editing jargon, and testers who
            // read the label still didn't find the horizontal scroll. The
            // strip's own opening slide-into-place is the affordance now —
            // `TimelineScrubber.centerIfNeeded`.
            card(tl)

            links(tl, jump)
                .padding(.top, 12)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    private func scheduleCard(_ tl: TimelineData) -> some View {
        VStack(spacing: 0) {
            WeekRangeBar(anchor: tl.anchor, today: tl.today, tz: tz, onTap: { showPicker = true })
            Divider().overlay(Color.white.opacity(0.08))
            // Both dates, never one: `anchor` keys the day groups (it is what
            // `days` offsets are relative to), `today` only says Today/Tomorrow.
            // The eclipse row is merged HERE, not in the four detail views:
            // an eclipse belongs to the sky, not to the station, so every kind
            // of detail gets it from one place.
            MultiDaySchedule(entries: (entries(tl) + eclipseEntries(tl)).sorted { $0.time < $1.time },
                             tz: tz, anchor: tl.anchor,
                             today: tl.today, days: tl.days,
                             scrubTime: scrubTime, onTap: { scrubTime = $0 })
        }
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
    }
}

/// The span on screen, and the way to change it.
///
/// It heads the SCHEDULE card rather than sitting in the scrub card: it names
/// the list's range, and putting it in the scrub card would land it below the
/// swipe hint, the readout and the tide-at-port link — much further down the
/// page than "just under the scrubber" suggests — while reopening the
/// 2026-08-03 rule that the `when` row is always last in that card.
struct WeekRangeBar: View {
    let anchor: Date
    let today: Date
    let tz: TimeZone
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.7))
                Text(weekRangeLabel(anchor: anchor, tz: tz))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                if anchor != today {
                    // The bar is the clearest statement on screen that you are
                    // not looking at this week, so it carries the way back.
                    Text("not this week")
                        .font(.caption2)
                        .foregroundStyle(SN.amber)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SN.foam.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("week-range-bar")
        .accessibilityLabel("Showing \(weekRangeLabel(anchor: anchor, tz: tz)). Tap to choose a date.")
    }
}

/// How the strip's day row reaches the picker the range bar owns. An
/// environment closure rather than four more callback parameters: the strip is
/// three views deep in every detail, and none of the layers between it and the
/// scaffold has anything to say about dates.
private struct OpenWeekPickerKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openWeekPicker: () -> Void {
        get { self[OpenWeekPickerKey.self] }
        set { self[OpenWeekPickerKey.self] = newValue }
    }
}

/// A native graphical `DatePicker`, in a sheet.
///
/// Native rather than a hand-rolled month grid: Dynamic Type, VoiceOver, and
/// localization arrive for nothing, and this app adds no dependency it can
/// avoid. Unbounded in both directions — the engine is deterministic, so last
/// Saturday costs exactly what next March costs. Online gates get the SAME
/// unbounded picker rather than a greyed-out range: two classes of station that
/// visibly disagree about how far the future goes would leave the user to work
/// out why, where an honest failure at the moment of asking says it in words.
struct WeekPickerSheet: View {
    @Binding var anchor: Date
    let tz: TimeZone
    let onOpen: () -> Void
    let onPick: (Date) -> Void

    @State private var draft = Date()
    @Environment(\.dismiss) private var dismiss

    /// The one calendar this sheet uses, for both the grid and the commit.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Week starting", selection: $draft,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(SN.go)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("week-picker")
                    // The grid must be drawn in the STATION's zone, because
                    // that is the zone "Show" commits in. A sheet is its own
                    // presentation hierarchy and does not inherit the
                    // detail's `\.timeZone`, so the calendar was laid out in
                    // the DEVICE's day while the commit took `startOfDay` in
                    // the station's: from a device east of the station,
                    // tapping the 8th asked for the 7th, and the week that
                    // came back was the one before the week you pointed at.
                    // Reading a phone in Halifax about Sechelt is exactly the
                    // case, and so is a UTC test runner.
                    .environment(\.timeZone, tz)
                    .environment(\.calendar, calendar)
                Spacer()
            }
            .background(CanvasBackground())
            .navigationTitle("Choose a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        let picked = calendar.startOfDay(for: draft)
                        anchor = picked
                        onPick(picked)
                        dismiss()
                    }
                    .accessibilityIdentifier("week-picker-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            draft = anchor
            // Fire the speculative fetch as the sheet appears, not when a date
            // is chosen: by the time the user has picked, the round trip has
            // had the whole browsing interaction to land.
            onOpen()
        }
    }
}

/// The provenance footer: the not-for-navigation label over the caller's
/// caption line(s).
struct DetailFooter<Note: View>: View {
    @ViewBuilder var note: () -> Note

    var body: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      color: SN.foam.opacity(0.4), tracking: 1.4)
            note()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

/// The collapsed provenance section (#170): where the numbers came from, for
/// the minority who want to know, without any of it intruding on the reader
/// who just wants the next slack. The container is shared; the rows are the
/// caller's, because a current gate wants its set bearings and its reference
/// offsets where a tide wants its datum.
struct StationDetails<Rows: View>: View {
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        DisclosureGroup("Station details") {
            VStack(alignment: .leading, spacing: 10) {
                rows()
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
        .foregroundStyle(SN.foam.opacity(0.7))
        .tint(SN.foam.opacity(0.55))
        .padding(.horizontal, 24)
    }
}

/// One label/value line inside `StationDetails`.
struct StationDetailRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

/// A sentence inside `StationDetails` — the explanations that sit under a row
/// rather than beside a label.
struct StationDetailNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(SN.foam.opacity(0.55))
    }
}

// `ProvisionalBadge` — the ⚠️ disc that used to sit beside the region on a
// provisional card — is gone (#93). One marking per state: the fast answer is
// now `CardStatus.refining`'s strip, which says the word and the tolerance
// instead of leaving the reader to decode a triangle. Its contrast measurement
// (docs/testflight.md) still governs, and CardStatus.tint cites it.

// MARK: - Detail-to-detail navigation

/// Detail views push the paired port's own detail through this, not a
/// NavigationLink: NavigationLink is a Button, and Button press tracking
/// goes dead below the strip in the iPad split detail column while tap
/// gestures keep working (see MultiDaySchedule's row comment).
private struct OpenTideDetailKey: EnvironmentKey {
    static let defaultValue: (TideStationRecord) -> Void = { _ in }
}

extension EnvironmentValues {
    var openTideDetail: (TideStationRecord) -> Void {
        get { self[OpenTideDetailKey.self] }
        set { self[OpenTideDetailKey.self] = newValue }
    }
}

/// Same reasoning as `openTideDetail` above, generalized to any CHS route: a
/// detail or the Downloads sheet pushes a port/gate through this, not a
/// NavigationLink or a Button — NavigationLink is a Button, and Button press
/// tracking goes dead below the strip in the iPad split detail column (same
/// hazard `openTideDetail` avoids). One closure for every CHS push — the
/// online gate's nearest-shipped link and the downloads-row tap both go
/// through this, rather than each carrying its own single-case key.
private struct OpenChsRouteKey: EnvironmentKey {
    static let defaultValue: (ChsRoute) -> Void = { _ in }
}

extension EnvironmentValues {
    var openChsRoute: (ChsRoute) -> Void {
        get { self[OpenChsRouteKey.self] }
        set { self[OpenChsRouteKey.self] = newValue }
    }
}

/// `openTideDetail` generalized to any station kind: the nearby-station
/// discovery link can land on a NOAA current, a CHS port or a gate, and each
/// pushes a different route. Same closure-not-NavigationLink reasoning.
private struct OpenStationItemKey: EnvironmentKey {
    static let defaultValue: (StationItem) -> Void = { _ in }
}

extension EnvironmentValues {
    var openStationItem: (StationItem) -> Void {
        get { self[OpenStationItemKey.self] }
        set { self[OpenStationItemKey.self] = newValue }
    }
}

/// Same reasoning as `openChsRoute` above: the detail-header title (issue #32)
/// and the Nearby map jump straight to the map, focused on the detail's own
/// station at the zoom they pass — not a NavigationLink or Button, same
/// press-tracking hazard in the iPad split detail column.
private struct OpenMapFocusedKey: EnvironmentKey {
    static let defaultValue: (StationItem, Double) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var openMapFocused: (StationItem, Double) -> Void {
        get { self[OpenMapFocusedKey.self] }
        set { self[OpenMapFocusedKey.self] = newValue }
    }
}

/// The quiet branch-affordance row (matching stations, tide at port, nearest
/// gate): leaf caption text after a branch icon. A tap gesture, not a Button —
/// Button press tracking goes dead below the strip in the iPad split detail
/// column (see the environment keys below).
struct BranchLink: View {
    let text: String
    let id: String
    var chevron = true
    let action: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2.weight(.semibold))
            // Mono digits: a branch label can carry a reading (a match count,
            // the nearby link's distance), and numbers hold their width.
            Text(text)
                .monospacedDigit()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(SN.leaf)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }
}

/// The one tide affordance on a current/gate detail (split-scrubbers spec
/// §2): navigating to the port's own TideDetailView. No tide numbers here.
struct TideAtPortLink: View {
    let port: TideStationRecord
    @Environment(\.openTideDetail) private var openTide

    var body: some View {
        BranchLink(text: "Tide at \(port.name)", id: "tide-at-port") { openTide(port) }
    }
}

/// The cross-series discovery affordance: the nearest station of the other
/// series, offered by proximity alone. The distance is in the label because
/// nearness is the whole claim — unlike `TideAtPortLink`, nothing curated
/// says this station governs or matches this water.
struct NearbyStationLink: View {
    let item: StationItem
    let km: Double
    @Environment(\.openStationItem) private var open

    var body: some View {
        let currents = item.series == .current
        BranchLink(text: "\(currents ? "Currents" : "Tide") at \(item.name) · \(formatNm(km))",
                   id: currents ? "nearby-currents" : "nearby-tide") { open(item) }
    }
}

/// The persisted Tides/Currents pick. Standard defaults, not the App Group:
/// no widget reads it.
let seriesFilterKey = "slackwater.seriesFilter"

/// The Tides/Currents narrowing — three quiet capsules over one persisted
/// filter, shared by Near Me, search and every detail's Nearby. Tapping the
/// active one is a second way back to All, for a thumb already on it.
struct SeriesFilterChips: View {
    @AppStorage(seriesFilterKey) private var filter: StationSeries?

    var body: some View {
        HStack(spacing: 6) {
            chip("All", nil)
            chip("Tides", .tide)
            chip("Currents", .current)
        }
    }

    private func chip(_ label: String, _ series: StationSeries?) -> some View {
        let selected = filter == series
        // A tap gesture, not a Button: Nearby puts these below the strip,
        // where Button press tracking goes dead in the iPad split detail column.
        return Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(selected ? SN.leaf : SN.foam.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(selected ? .regular.tint(SN.leaf.opacity(0.25)).interactive()
                                  : .regular.interactive(), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { filter = selected ? nil : series }
            .accessibilityLabel("Show \(label.lowercased())")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("series-filter-\(label.lowercased())")
    }
}

// MARK: - Recently viewed stations (prototype "Recent" list, Bryan's Recents)

/// Most-recent-first, capped at 6 (prototype addRecent slice(0,6)), persisted
/// in UserDefaults. Recorded by the detail views on appear.
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()
    private static let key = AppGroup.recentsKey

    @Published private(set) var ids: [String]

    /// Armed by the regular-width auto-selection (M52) with the id of exactly
    /// the detail it opens. The pane opening itself is not the user viewing a
    /// station, and counting it would evict a real entry from the 6-slot
    /// history on every single launch. Scoped to the id — an unfitted CHS
    /// station's waiting view records nothing at all, so a bare flag would
    /// survive it and swallow the next genuinely opened station (#3). Any
    /// record attempt disarms it.
    var skipNextRecordID: String?

    private init() {
        // UI-test hook, like -resetGate: a clean no-recents first run.
        if CommandLine.arguments.contains("-resetRecents") {
            AppGroup.defaults.removeObject(forKey: Self.key)
        }
        ids = AppGroup.defaults.stringArray(forKey: Self.key) ?? []
    }

    func record(_ id: String) {
        let skip = id == skipNextRecordID
        skipNextRecordID = nil
        if skip { return }
        var next = ids.filter { $0 != id }
        next.insert(id, at: 0)
        next = Array(next.prefix(6))
        ids = next
        AppGroup.defaults.set(next, forKey: Self.key)
    }

    /// Swipe "Remove" on a Recents row (current-detail spec §9: true deletion).
    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        AppGroup.defaults.set(ids, forKey: Self.key)
    }

    var items: [StationItem] { ids.compactMap { StationItem.byId[$0] } }

    /// The most recently opened station, which is the best guess at where the
    /// user is when Core Location has told us nothing.
    var lastOpened: StationItem? { items.first }
}

// MARK: - Favorites (current-detail spec §9; prototype TidesApp savedIds)

/// Starred stations, in star order, persisted on the device and in iCloud (#134).
///
/// Storage only: `ids`, `contains`, `toggle`, `forget` and `replace` are what
/// they were before the cloud existed. The App Group copy stays this device's
/// own truth — it is what the widget reads (`WidgetStationLoader
/// .defaultStationID`) and what a device without iCloud falls back to — while
/// `FavoritesCloud` carries the same list between devices.
///
/// ponytail: RecentsStore keeps the same shape and stays device-local on
/// purpose. Recents are a record of what you did on *this* device; favourites
/// are the list you curated. Sync them if that ever stops being true.
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()
    private static let key = AppGroup.favoritesKey
    /// Set once this device's list has been written out as per-station cloud
    /// keys. Until then the cloud has never heard of these stars and must be
    /// merged with rather than adopted — adopting an empty cloud is exactly
    /// how an upgrading user loses the six gates they starred.
    private static let migratedKey = "slackwater.favorites.cloudMigrated"

    @Published private(set) var ids: [String]

    private init() {
        // UI-test hook, like -resetRecents: a clean no-favorites run.
        if CommandLine.arguments.contains("-resetFavorites") {
            AppGroup.defaults.removeObject(forKey: Self.key)
        }
        // UI-test hook: `-seedFavorites a,b` starts the run with exactly those
        // ids starred. The only way to exercise a favorite whose station has
        // left the bundle (issue #91) — by construction the app can't star one,
        // and the interesting state is a device that starred it releases ago.
        if let i = CommandLine.arguments.firstIndex(of: "-seedFavorites"),
           i + 1 < CommandLine.arguments.count {
            AppGroup.defaults.set(
                CommandLine.arguments[i + 1].split(separator: ",").map(String.init), forKey: Self.key)
        }
        ids = AppGroup.defaults.stringArray(forKey: Self.key) ?? []

        // Nil under both kinds of test, so those hooks stay device-local
        // (FavoritesCloud.store).
        guard let cloud = FavoritesCloud.store else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] note in self?.cloudChanged(note, cloud) }
        cloud.synchronize()
        adopt(cloud)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if let i = ids.firstIndex(of: id) {
            ids.remove(at: i)
            unstar(id)
            // Spec §9: unfavoriting re-files to Recents, never data loss.
            RecentsStore.shared.record(id)
        } else {
            ids.append(id)
            star(id)
        }
        persist()
        // A widget's default station is "first favorite" (WidgetStationLoader
        // .defaultStationID) — starring/unstarring can change what an
        // unconfigured widget shows, so its timeline must not wait for the
        // next half-hourly tick (H1).
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// True removal, for a station that has left the bundle (issue #91).
    /// Not `toggle`: that re-files to Recents (spec §9), and a station that no
    /// longer exists is the one thing Recents cannot show.
    func forget(_ id: String) {
        guard ids.contains(id) else { return }
        ids.removeAll { $0 == id }
        unstar(id)
        persist()
    }

    /// Swap a removed station for the replacement the user picked, in place —
    /// favorites render in the order they were starred, and the replacement
    /// inherits the dead one's slot rather than jumping to the end.
    func replace(_ old: String, with new: String) {
        guard let i = ids.firstIndex(of: old) else { return }
        ids.remove(at: i)
        let inserted = !ids.contains(new)
        if inserted { ids.insert(new, at: i) }
        // The replacement inherits the dead station's *stamp* as well as its
        // slot, or the next device to sync would sort it to the end.
        let stamp = FavoritesCloud.store?.double(forKey: FavoritesCloud.prefix + old) ?? 0
        unstar(old)
        if inserted { star(new, at: stamp > 0 ? stamp : nil) }
        persist()
    }

    // MARK: - iCloud (see FavoritesCloud)

    private func persist() { AppGroup.defaults.set(ids, forKey: Self.key) }

    private func star(_ id: String, at stamp: Double? = nil) {
        FavoritesCloud.store?.set(stamp ?? Date().timeIntervalSince1970,
                                  forKey: FavoritesCloud.prefix + id)
    }

    private func unstar(_ id: String) {
        FavoritesCloud.store?.removeObject(forKey: FavoritesCloud.prefix + id)
    }

    private func cloudChanged(_ note: Notification, _ cloud: NSUbiquitousKeyValueStore) {
        // Signing in or out of iCloud hands us a different store, usually an
        // empty one. Adopting that erases a list the user can still see on this
        // device, so treat the new account as never-migrated and let this
        // device's stars seed it instead.
        if note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            == NSUbiquitousKeyValueStoreAccountChange {
            AppGroup.defaults.set(false, forKey: Self.migratedKey)
        }
        adopt(cloud)
    }

    /// Reconcile with the cloud. Everything that can lose a star lives in
    /// `FavoritesCloud.reconcile`, which is a pure function; this is its I/O.
    private func adopt(_ cloud: NSUbiquitousKeyValueStore) {
        let migrated = AppGroup.defaults.bool(forKey: Self.migratedKey)
        let (next, writes) = FavoritesCloud.reconcile(
            local: ids,
            cloud: FavoritesCloud.stamps(cloud.dictionaryRepresentation),
            migrated: migrated,
            now: Date().timeIntervalSince1970)
        for (id, stamp) in writes { cloud.set(stamp, forKey: FavoritesCloud.prefix + id) }
        if !migrated { AppGroup.defaults.set(true, forKey: Self.migratedKey) }
        guard next != ids else { return }
        ids = next
        persist()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// The one dedupe rule: each station renders in at most one group —
/// My Location > Favorites > Near Me > Recents (Bryan's M4.5 order: Recents at
/// the very bottom is the floor — a station both nearby and recent shows under
/// Near Me; Recents holds only stations not already shown above). Persisted
/// stores are untouched; exclusion is render-time only, so a station reappears
/// when it stops being the hero / a favorite / nearby.
struct ListGroups {
    let favorites: [String]
    let nearMe: [String]
    let recents: [String]

    init(heroIds: [String], favoriteIds: [String], recentIds: [String],
         rankedIds: [String], nearCount: Int) {
        favorites = favoriteIds.filter { !heroIds.contains($0) }
        var shown = Set(favorites)
        shown.formUnion(heroIds)
        nearMe = Array(rankedIds.filter { !shown.contains($0) }.prefix(nearCount))
        shown.formUnion(nearMe)
        recents = recentIds.filter { !shown.contains($0) }
    }
}

// MARK: - One entry per place (M50)

/// Same-named stations are one place answered by several stations. NOAA alone
/// ships 19 collided names in the bundle — three "Point Wilson", four "The
/// Narrows", two "Discovery Island" — and in a distance-ranked list they
/// render as identical cards stacked on each other, distinguishable only by
/// the distance pill.
///
/// So a name renders once, as its nearest station, and the rest stay one tap
/// away behind the matching-station chooser: the list-side application of the
/// web's multi-match chooser (slackwater-web `src/StationChooser.tsx`,
/// web-client-design § "the multi-match chooser" — "where more than one
/// station plausibly serves a place, say so rather than silently picking").
///
/// Favorites are deliberately *not* collapsed: a starred station is an
/// explicit pick, and quietly swapping it for a nearer namesake would override
/// a choice the user made on purpose.
struct StationGroups {
    /// Name -> every station carrying it, nearest first.
    private let byName: [String: [StationItem]]
    /// Any station id -> the id that actually renders for its name.
    private let canonical: [String: String]
    /// `collapse(ranked ids)`, done once here rather than per render: the
    /// list re-evaluates on every fit-queue transition, and mapping 3,600
    /// ids through a Set each time to find four is what #232 measured.
    let shownIds: [String]

    /// `ranked` is the catalog sorted nearest-first, so the first station of a
    /// name is the nearest one — the one shown.
    init(ranked: [StationItem]) {
        var byName: [String: [StationItem]] = [:]
        for item in ranked { byName[item.name, default: []].append(item) }
        self.byName = byName
        let canonical = Dictionary(ranked.map { ($0.id, byName[$0.name]?.first?.id ?? $0.id) },
                                   uniquingKeysWith: { first, _ in first })
        self.canonical = canonical
        var seen = Set<String>()
        shownIds = ranked.map { canonical[$0.id] ?? $0.id }.filter { seen.insert($0).inserted }
    }

    /// What renders in place of `id` — itself, unless a nearer station shares its name.
    func shown(_ id: String) -> String { canonical[id] ?? id }

    /// Collapse ids to what renders: one per name, input order kept.
    func collapse(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map(shown).filter { seen.insert($0).inserted }
    }

    /// Every station sharing this one's name, nearest first — the chooser's rows.
    func matches(_ item: StationItem) -> [StationItem] { byName[item.name] ?? [item] }
}

// MARK: - The distance-ranked catalog, memoised (M53)

/// The list ranks the whole catalog by distance and builds `StationGroups`
/// over it — and it does that inside `body`, which SwiftUI re-evaluates on
/// every fit that lands, every favourite toggle, every unit switch. At 41
/// bundled stations nobody could measure it. At 3,125 it is a 3,125-element
/// sort plus two dictionary builds, tens of times a second.
///
/// So it is computed once per FIX, not once per render. The key is the fix
/// rounded to ~100 m — finer than the list can show, coarser than GPS jitter,
/// so a boat at anchor pays for this exactly once.
@MainActor
enum RankedStations {
    private static var key = ""
    private static var ranked: [StationItem] = []
    private static var groups = StationGroups(ranked: [])

    static func near(lat: Double, lon: Double) -> (ranked: [StationItem], groups: StationGroups) {
        let k = "\(Int((lat * 1000).rounded())),\(Int((lon * 1000).rounded()))"
        if k != key {
            key = k
            ranked = StationItem.rankedByDistance(StationItem.all, lat: lat, lon: lon)
            groups = StationGroups(ranked: ranked)
        }
        return (ranked, groups)
    }
}
