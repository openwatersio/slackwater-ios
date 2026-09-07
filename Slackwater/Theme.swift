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
func moonGlowRadius(fraction: Double) -> CGFloat { 12 + CGFloat(fraction) * 20 }
/// The moon fades out inside the sun's glare, as it does in the sky: the
/// bodies are symbols many times their true size, so near every new moon the
/// two would otherwise overlap like an eclipse. `distance` is between their
/// projected centres; the moon is gone by the time the discs would touch and
/// clear once it is past the sun's glow. A real solar eclipse fades too —
/// gate on an Almanac separation once it has one.
func moonGlareOpacity(distance: CGFloat) -> Double {
    max(0, min(1, Double((distance - 20) / 24)))
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
/// `pad` is the body's glow radius: at the horizon its centre sits `pad`
/// beyond the edge, so nothing of it shows until it has risen. With no span
/// the window is the whole 360°.
let skyAltitudeScale: CGFloat = 3   // points per degree of altitude
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

private func starPoint(_ index: Int, size: CGSize) -> CGPoint {
    let x = Double((index * 37 + 11) % 97) / 96
    let y = Double((index * 53 + 7) % 89) / 88
    return CGPoint(x: size.width * x, y: size.height * CGFloat(y) * 0.82)
}

struct SkyState {
    let latitude: Double
    let sun: AltAz?
    let sunSpan: HorizonSpan?
    let moon: AltAz?
    let moonSpan: HorizonSpan?
    let illumination: MoonIllumination?

    /// `days` is the strip's own day chrome. Both bodies' horizon spans take
    /// their rise and set times from there rather than searching here: this
    /// initialiser runs on every scrub frame, and an Almanac event search
    /// costs two orders of magnitude more than a position lookup (~0.6 ms
    /// against ~0.005 ms). Empty days (an online gate still fetching) means
    /// no spans, and `skyPoint` shows the whole 360°.
    init(time: Date, latitude: Double, longitude: Double, days: [TimelineDay] = []) {
        self.latitude = latitude
        let observer = try? Observer(latitudeDeg: latitude, longitudeDeg: longitude)
        sun = observer.flatMap { try? sunAltAz(time, observer: $0) }
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

    var paint: SkyPaint { skyPaint(sunAltitude: sun?.altDeg ?? -18) }
    var opacity: Double { skyOpacity(sunAltitude: sun?.altDeg ?? -18) }
    var horizon: Color { Color(hex: paint.bottom).opacity(opacity) }
    var ink: Color { skyUsesDarkInk(sunAltitude: sun?.altDeg ?? -18) ? SN.navyDeep : .white }
}

struct SkyBackdrop: View {
    let sky: SkyState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let paint = sky.paint
            ZStack {
                LinearGradient(colors: [Color(hex: paint.top), Color(hex: paint.bottom)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(sky.opacity)
                if let altitude = sky.sun?.altDeg {
                    let opacity = starOpacity(sunAltitude: altitude)
                    TimelineView(.animation(minimumInterval: 0.125,
                                            paused: opacity == 0 || reduceMotion)) { timeline in
                        let seconds = timeline.date.timeIntervalSinceReferenceDate
                        Canvas { context, size in
                            for i in 0..<24 {
                                let point = starPoint(i, size: size)
                                let radius: CGFloat = i.isMultiple(of: 5) ? 1.15 : 0.7
                                let twinkle = starTwinkle(index: i, seconds: seconds,
                                                          reduceMotion: reduceMotion)
                                context.fill(Path(ellipseIn: CGRect(x: point.x - radius,
                                                                   y: point.y - radius,
                                                                   width: radius * 2,
                                                                   height: radius * 2)),
                                             with: .color(.white.opacity(opacity * twinkle)))
                            }
                        }
                    }
                }
                // Below the horizon a body is past an edge; the clip hides it.
                let sunPoint = sky.sun.map {
                    skyPoint(azimuth: $0.azDeg, altitude: $0.altDeg, latitude: sky.latitude,
                             span: sky.sunSpan, pad: 27, size: proxy.size)
                }
                if let point = sunPoint {
                    Circle().fill(SN.sun.opacity(0.24)).blur(radius: 12)
                        .frame(width: 54, height: 54).position(point)
                    Circle().fill(SN.sun)
                        .frame(width: 16, height: 16).position(point)
                }
                if let moon = sky.moon, let illumination = sky.illumination {
                    let glowRadius = moonGlowRadius(fraction: illumination.fraction)
                    let point = skyPoint(azimuth: moon.azDeg, altitude: moon.altDeg,
                                         latitude: sky.latitude, span: sky.moonSpan,
                                         pad: glowRadius, size: proxy.size)
                    // The lit limb faces the sun on screen, above the horizon
                    // or not; the glow leans the same way.
                    let toSun = sunPoint.map { atan2($0.y - point.y, $0.x - point.x) } ?? 0
                    let glare = sunPoint.map { hypot($0.x - point.x, $0.y - point.y) } ?? .infinity
                    Circle()
                        .fill(RadialGradient(
                            stops: [
                                .init(color: Color(hex: 0xE6EEFF,
                                                   opacity: 0.95 * (0.1 + illumination.fraction * 0.66)),
                                      location: 0),
                                .init(color: Color(hex: 0xCFE0FF,
                                                   opacity: 0.28 * (0.1 + illumination.fraction * 0.66)),
                                      location: 0.45),
                                .init(color: Color(hex: 0xCFE0FF, opacity: 0), location: 1),
                            ], center: .center, startRadius: 0, endRadius: glowRadius))
                        .frame(width: glowRadius * 2, height: glowRadius * 2)
                        .position(x: point.x + 4 * cos(toSun), y: point.y + 4 * sin(toSun))
                        .opacity(moonGlareOpacity(distance: glare))
                    // `waxing: true` lights the +x limb; the rotation aims it.
                    MoonGlyph(fraction: illumination.fraction, waxing: true, size: 22)
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

/// The moon glyph: the lit region over a dark disc that stays
/// semi-transparent to show the sky. Lit on the right while waxing, the
/// northern convention; the sky passes `waxing: true` and rotates toward the sun.
struct MoonGlyph: View {
    let fraction: Double
    let waxing: Bool
    var size: CGFloat = 20

    var body: some View {
        let r = size / 2 - 1
        ZStack {
            Circle().fill(SN.moonLimb.opacity(0.18))
            moonLitPath(fraction: fraction, radius: r).offsetBy(dx: r, dy: r)
                .fill(SN.foam)
                .scaleEffect(x: waxing ? 1 : -1)
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

/// What comes next, centred on the reading line in the strip's chrome row.
/// Tapping scrubs to it. It fades while the strip is moving and returns once
/// the scrub has rested, so it never flickers through the events a fling
/// passes.
struct Commentary: View {
    let text: String?
    /// Set when the text is a warning about the scrub instant — a fast tide —
    /// rather than the next event; the ramp's colour, so the pill explains
    /// the line under it.
    var tint: Color? = nil
    let scrubTime: Date
    var ink: Color = SN.foam
    let onTap: () -> Void
    @State private var settled = false

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
        .opacity(settled ? 1 : 0)
        .allowsHitTesting(settled)
        .animation(.easeInOut(duration: 0.2), value: settled)
        .task(id: scrubTime) {
            // Rest = no scrub change for this long. A cancelled sleep is a
            // scrub still in motion, not a rest.
            settled = false
            guard (try? await Task.sleep(for: .milliseconds(450))) != nil else { return }
            settled = true
        }
    }
}

/// Between the strip and the schedule: the one number this station kind has
/// to add beside the moon that drives it. `primary` is the caller's — a tide's
/// swing ("Range"), a current's next maximum ("Next max"); a derived gate has
/// no number at all and passes nil, leaving the moon on its own.
struct SummaryTiles: View {
    var primary: (label: String, value: String, caption: String)? = nil
    let at: Date

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
            if let moon = try? moonIllumination(at) {
                ReadoutTile(label: "Moon", caption: "\(Int((moon.fraction * 100).rounded()))% lit",
                            accessibility: "Moon") {
                    MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 14)
                } value: {
                    // Words, not a number: "Waning Crescent" has to fit on one
                    // line where "7.6 ft" does, so it sits well below the hero.
                    Text(moonPhaseName(phase: moon.phase))
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
    @ViewBuilder var glyph: () -> Glyph
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel(text: label, color: SN.foam.opacity(0.55))
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
    /// timeline the page is already drawing rather than deriving a second one.
    @ViewBuilder var links: (TimelineData) -> Links
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
                        topBackdrop
                            .frame(maxWidth: .infinity)
                            .frame(height: topHeight + TimelineGeo(data: timeline).bodyTop)
                    }
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            DetailHeader(name: name, region: region,
                                         favoriteId: favoriteId,
                                         topSafeInset: geo.safeAreaInsets.top)
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
                    }
                    .padding(.bottom, 42)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(CanvasBackground())
            .onPreferenceChange(DetailTopHeightKey.self) { topHeight = $0 }
            .environment(\.timeZone, tz)
            .toolbar(.hidden, for: .navigationBar)
            // A shared link's moment (#187). Taken on appear so it reaches only
            // the detail the link opened, but APPLIED once the timeline exists:
            // the caller's own onAppear sets the anchor and builds, and SwiftUI
            // does not promise which onAppear runs first — a scrub set here
            // would be built over. Waiting for the timeline is deterministic,
            // and for an online gate it is also when there is anything to
            // scrub.
            .onAppear {
                if let t = pendingScrubInstant {
                    pendingScrubInstant = nil
                    linkedInstant = t
                }
            }
            .onChange(of: timeline == nil) { _, isNil in
                guard !isNil, let t = linkedInstant else { return }
                linkedInstant = nil
                scrubTime = t
                // The picker's rule, inverted: move the window only when the
                // moment isn't already on the strip, so a link to later today
                // doesn't open on a week bar reading "not this week".
                let week = Timeline.window(anchor: anchor)
                if t < week.start || t > week.end {
                    anchor = dayLocal(t, tz)
                    onPicked(anchor)
                }
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

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full bleed, no chrome: the curve is the hero and the page is its
            // frame. No "‹ swipe to scrub ›" label here, and none is coming
            // back (#58): "scrubber" is audio-editing jargon, and testers who
            // read the label still didn't find the horizontal scroll. The
            // strip's own opening slide-into-place is the affordance now —
            // `TimelineScrubber.centerIfNeeded`.
            card(tl)

            links(tl)
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
            MultiDaySchedule(entries: entries(tl), tz: tz, anchor: tl.anchor,
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Week starting", selection: $draft,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(SN.go)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("week-picker")
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
                        var cal = Calendar(identifier: .gregorian)
                        cal.timeZone = tz
                        let picked = cal.startOfDay(for: draft)
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

/// Same reasoning as `openChsRoute` above: the detail-header title (issue #32)
/// jumps straight to the map, focused on the detail's own station — not a
/// NavigationLink or Button, same press-tracking hazard in the iPad split
/// detail column.
private struct OpenMapFocusedKey: EnvironmentKey {
    static let defaultValue: (StationItem) -> Void = { _ in }
}

extension EnvironmentValues {
    var openMapFocused: (StationItem) -> Void {
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
            Text(text)
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

    init(heroId: String?, favoriteIds: [String], recentIds: [String],
         rankedIds: [String], nearCount: Int) {
        favorites = favoriteIds.filter { $0 != heroId }
        var shown = Set(favorites)
        if let heroId { shown.insert(heroId) }
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
            ranked = StationItem.all.sorted {
                $0.km(fromLat: lat, lon: lon) < $1.km(fromLat: lat, lon: lon)
            }
            groups = StationGroups(ranked: ranked)
        }
        return (ranked, groups)
    }
}
