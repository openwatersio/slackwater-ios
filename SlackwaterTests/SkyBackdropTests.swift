// Slackwater — GPL v3.
import CoreGraphics
import Almanac
import XCTest
@testable import Slackwater

final class SkyBackdropTests: XCTestCase {
    func testBodiesMoveContinuouslyAcrossRiseAndSet() throws {
        let observer = try Observer(latitudeDeg: 48.4237, longitudeDeg: -123.3027)
        let f = ISO8601DateFormatter()
        let start = try XCTUnwrap(f.date(from: "2032-04-23T07:00:00Z"))
        let end = try XCTUnwrap(f.date(from: "2032-04-29T07:00:00Z"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        var days: [TimelineDay] = []
        var day = start
        while day < end {
            let next = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: day))
            let sun = try sunEvents(from: day, to: next, observer: observer)
            let moon = try moonEvents(from: day, to: next, observer: observer)
            days.append(TimelineDay(offset: days.count, start: day,
                                    sunrise: sun.first { $0.kind == .rise }?.time,
                                    sunset: sun.first { $0.kind == .set }?.time,
                                    moonrise: moon.first { $0.kind == .rise }?.time,
                                    moonset: moon.first { $0.kind == .set }?.time))
            day = next
        }
        for day in days.dropFirst().dropLast() {
            for event in [day.sunrise, day.sunset, day.moonrise, day.moonset].compactMap({ $0 }) {
                let before = SkyState(time: event.addingTimeInterval(-1), latitude: 48.4237,
                                      longitude: -123.3027, days: days)
                let after = SkyState(time: event.addingTimeInterval(1), latitude: 48.4237,
                                     longitude: -123.3027, days: days)
                for (a, b, spanA, spanB, pad) in [
                    (before.sun, after.sun, before.sunSpan, after.sunSpan, sunDiscRadius),
                    (before.moon, after.moon, before.moonSpan, after.moonSpan, moonGlyphSize / 2)
                ] {
                    let a = try XCTUnwrap(a), b = try XCTUnwrap(b)
                    let size = CGSize(width: 402, height: 240)
                    let p = skyBodyPoint(azimuth: a.azDeg, altitude: a.altDeg, latitude: 48.4237,
                                         span: spanA, pad: pad, size: size)
                    let q = skyBodyPoint(azimuth: b.azDeg, altitude: b.altDeg, latitude: 48.4237,
                                         span: spanB, pad: pad, size: size)
                    XCTAssertLessThan(hypot(p.x - q.x, p.y - q.y), 1, f.string(from: event))
                }
            }
        }
    }

    func testSolarEclipseDrawsTheMoonOverTheSunAndDarkensTheSky() throws {
        // 2017-08-21 from Victoria BC: about nine tenths of the sun covered at 17:21 UTC.
        let peak = try XCTUnwrap(ISO8601DateFormatter().date(from: "2017-08-21T17:21:00Z"))
        let sky = SkyState(time: peak, latitude: 48.4284, longitude: -123.3656)
        let sunAlt = try XCTUnwrap(sky.sun?.altDeg)
        XCTAssertGreaterThan(sky.obscuration, 0.85)
        XCTAssertLessThan(sky.obscuration, 0.95)
        XCTAssertGreaterThan(sunAlt, 30)
        // The sky darkens with the covered fraction; a partial keeps daylight's paint family.
        XCTAssertLessThan(sky.litAltitude, sunAlt)
        XCTAssertGreaterThan(sky.litAltitude, -9)
        XCTAssertNotEqual(sky.paint, skyPaint(sunAltitude: sunAlt))
        // An hour later the discs are apart again and nothing is darkened.
        let after = SkyState(time: peak.addingTimeInterval(2 * 3600), latitude: 48.4284, longitude: -123.3656)
        XCTAssertEqual(after.obscuration, 0)
        XCTAssertEqual(after.litAltitude, try XCTUnwrap(after.sun?.altDeg))
        // The glare fade is overridden while the moon is in front of the sun.
        XCTAssertEqual(moonGlareOpacity(distance: 0, obscuration: 0.01), 1)
        XCTAssertEqual(moonGlareOpacity(distance: 0, obscuration: 0), 0)
        // Totality reaches nautical twilight; a half-covered sun barely moves; below it, nothing moves.
        XCTAssertEqual(eclipsedSunAltitude(40, obscuration: 1), -9)
        XCTAssertGreaterThan(eclipsedSunAltitude(40, obscuration: 0.5), 36)
        XCTAssertEqual(eclipsedSunAltitude(-12, obscuration: 1), -12)
        XCTAssertEqual(eclipsedSunAltitude(40, obscuration: 0), 40)
    }

    func testMoonShadingStaysContinuousAcrossMidnightSunWrap() throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-02T07:44:00Z"))
        var previous = SkyState(time: start, latitude: 48.424, longitude: -123.371)
        var crossedSeam = false
        for minute in 1...55 {
            let sky = SkyState(time: start.addingTimeInterval(Double(minute) * 60),
                               latitude: 48.424, longitude: -123.371)
            let sun = try XCTUnwrap(sky.sun), previousSun = try XCTUnwrap(previous.sun)
            crossedSeam = crossedSeam || abs(sun.azDeg - previousSun.azDeg) > 180
            let delta = sky.moonLightAngle - previous.moonLightAngle
            XCTAssertLessThan(abs(atan2(sin(delta), cos(delta))), .pi / 180,
                              "Shading jumped at minute \(minute)")
            previous = sky
        }
        XCTAssertTrue(crossedSeam, "The regression must cross the offscreen sun's azimuth seam")
    }

    func testEveryScrubDetailUsesTheSkyBackdrop() throws {
        for file in ["Slackwater/TideDetailView.swift", "Slackwater/CurrentDetailView.swift",
                     "Slackwater/OnlineGateDetailView.swift", "Slackwater/DerivedGateDetailView.swift"] {
            XCTAssertTrue(try repoSource(file).contains("topBackdrop: AnyView(SkyBackdrop(sky: sky))"), file)
        }
    }

    func testSkyStatePlacesEveryCatalogStarWithAlmanac() throws {
        // Sky math lives in Almanac now; the app only carries the catalog.
        let time = ISO8601DateFormatter().date(from: "2026-03-20T20:00:00Z")!
        let lat = 48.4, lon = -123.4
        let sky = SkyState(time: time, latitude: lat, longitude: lon)
        // Sirius leads the catalog, and every row is placed.
        XCTAssertEqual(brightStars.count, 288)
        XCTAssertEqual(brightStars.first?.mag, -1.44)
        XCTAssertEqual(sky.stars.count, brightStars.count)
        // Polaris stands at the latitude, due north, whatever the hour.
        let polaris = try XCTUnwrap(sky.stars.first { $0.star.dec > 89 }).at
        XCTAssertEqual(polaris.altDeg, lat, accuracy: 1)
        XCTAssertTrue(polaris.azDeg < 2 || polaris.azDeg > 358, "\(polaris.azDeg)")
    }

    func testSkyProjectionAndPaletteMatchTheAlmanacDome() {
        XCTAssertEqual(skyPaint(sunAltitude: 10),
                       SkyPaint(top: 0x2F7FD4, bottom: 0xBDE3FB))
        XCTAssertEqual(skyPaint(sunAltitude: -18),
                       SkyPaint(top: 0x04060F, bottom: 0x0B1023))
        XCTAssertEqual(skyPaint(sunAltitude: -9),
                       SkyPaint(top: 0x111D3D, bottom: 0x5C3A5B))
        XCTAssertFalse(skyUsesDarkInk(sunAltitude: 10))
        XCTAssertFalse(skyUsesDarkInk(sunAltitude: 0))
        XCTAssertFalse(skyUsesDarkInk(sunAltitude: -3))
        XCTAssertFalse(skyUsesDarkInk(sunAltitude: -6))
        XCTAssertEqual(moonGlowRadius(fraction: 0), 12)
        XCTAssertEqual(moonGlowRadius(fraction: 1), 32)
        // Inside the sun's glare the moon fades: gone where the discs would
        // touch, clear once past the glow.
        let touching = sunDiscRadius + moonGlyphSize / 2, clear = sunGlowRadius + moonGlyphSize / 2
        XCTAssertEqual(moonGlareOpacity(distance: touching), 0)
        XCTAssertEqual(moonGlareOpacity(distance: (touching + clear) / 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(moonGlareOpacity(distance: clear), 1)
        XCTAssertEqual(starOpacity(sunAltitude: 0), 0)
        XCTAssertEqual(starOpacity(sunAltitude: -12), 0.35, accuracy: 0.001)
        XCTAssertEqual(starOpacity(sunAltitude: -18), 0.7)
        XCTAssertEqual(starHazeOpacity(altitude: -10), 0)
        XCTAssertEqual(starHazeOpacity(altitude: 15), 0.5)
        XCTAssertEqual(starHazeOpacity(altitude: 40), 1)
        XCTAssertEqual(starTwinkle(index: 3, seconds: 10, reduceMotion: true), 1)
        XCTAssertGreaterThanOrEqual(starTwinkle(index: 3, seconds: 10, reduceMotion: false), 0.72)
        XCTAssertLessThanOrEqual(starTwinkle(index: 3, seconds: 10, reduceMotion: false), 1)
        XCTAssertNotEqual(starTwinkle(index: 3, seconds: 10, reduceMotion: false),
                          starTwinkle(index: 3, seconds: 11, reduceMotion: false))
        XCTAssertEqual(skyOpacity(sunAltitude: 0), 0.55)
        XCTAssertEqual(skyOpacity(sunAltitude: -6), 1)

        let size = CGSize(width: 400, height: 160)
        // No span: the whole 360° across the width, altitude at its fixed
        // scale, and the horizon on the bottom edge.
        XCTAssertEqual(skyPoint(azimuth: 180, altitude: 0, latitude: 48, size: size),
                       CGPoint(x: 200, y: 160))
        XCTAssertEqual(skyPoint(azimuth: 180, altitude: 30, latitude: 48, size: size),
                       CGPoint(x: 200, y: 160 - 30 * skyAltitudeScale))
        // East on the RIGHT — mirrored from a sky chart. Time advances to
        // the right on the strip, so the curve pans right to left under the
        // fixed centerline and the bodies sweep with it. In either hemisphere.
        XCTAssertEqual(skyPoint(azimuth: 90, altitude: 0, latitude: 48, size: size),
                       CGPoint(x: 300, y: 160))
        XCTAssertEqual(skyPoint(azimuth: 90, altitude: 0, latitude: -48, size: size),
                       CGPoint(x: 300, y: 160))

        // A span makes the side edges the horizon: the centre sits `pad`
        // past the edge at rise and set, and the meridian stays centred.
        // Altitude keeps its fixed scale whatever the span.
        let span = HorizonSpan(riseAz: 120, setAz: 240)
        XCTAssertEqual(skyPoint(azimuth: 120, altitude: 0, latitude: 48, span: span, pad: 20, size: size),
                       CGPoint(x: 420, y: 160))
        XCTAssertEqual(skyPoint(azimuth: 240, altitude: 0, latitude: 48, span: span, pad: 20, size: size),
                       CGPoint(x: -20, y: 160))
        let noon = skyPoint(azimuth: 180, altitude: 30, latitude: 48, span: span, pad: 20, size: size)
        XCTAssertEqual(noon.x, 200, accuracy: 0.001)
        XCTAssertEqual(noon.y, 160 - 30 * skyAltitudeScale, accuracy: 0.001)

        // An arc that culminates north of the zenith faces north, still east
        // on the right: Singapore's June sun rises at 66°, crosses through
        // north, and sets at 294°.
        let north = HorizonSpan(riseAz: 66, setAz: 294, facesSouth: false)
        XCTAssertEqual(skyPoint(azimuth: 66, altitude: 0, latitude: 1.3, span: north, pad: 20, size: size).x,
                       420, accuracy: 0.001)
        XCTAssertEqual(skyPoint(azimuth: 294, altitude: 0, latitude: 1.3, span: north, pad: 20, size: size).x,
                       -20, accuracy: 0.001)
        XCTAssertEqual(skyPoint(azimuth: 0, altitude: 60, latitude: 1.3, span: north, pad: 20, size: size).x,
                       200, accuracy: 0.001)
        XCTAssertGreaterThan(skyPoint(azimuth: 30, altitude: 50, latitude: 1.3, span: north, size: size).x, 200)

        // A body is held in frame once it is up: `pad` past the edge at the
        // horizon, half `pad` inside at 5°, and twice `pad` inside from 10°.
        // The stars are not.
        func body(_ az: Double, _ alt: Double) -> CGFloat {
            skyBodyPoint(azimuth: az, altitude: alt, latitude: 48, span: span, pad: 20, size: size).x
        }
        XCTAssertEqual(body(120, 0), 420, accuracy: 0.001)
        XCTAssertEqual(body(120, 5), 390, accuracy: 0.001)
        XCTAssertEqual(body(120, 30), 360, accuracy: 0.001)
        XCTAssertEqual(body(240, 30), 40, accuracy: 0.001)
        XCTAssertEqual(body(180, 30), 200, accuracy: 0.001)
        XCTAssertEqual(body(100, -5), skyPoint(azimuth: 100, altitude: -5, latitude: 48, span: span,
                                               pad: 20, size: size).x, "below the horizon it runs on")
        XCTAssertEqual(skyBodyPoint(azimuth: 0, altitude: 30, latitude: 48, span: nil, pad: 20, size: size).x,
                       skyPoint(azimuth: 0, altitude: 30, latitude: 48, pad: 20, size: size).x,
                       "with no span the edges are not the horizon")
        let round = HorizonSpan(riseAz: 120, setAz: 240, circumpolar: true)
        XCTAssertEqual(skyBodyPoint(azimuth: 60, altitude: 30, latitude: 48, span: round, pad: 20, size: size).x,
                       skyPoint(azimuth: 60, altitude: 30, latitude: 48, span: round, pad: 20, size: size).x,
                       "a circumpolar arc runs off the frame")
    }

    /// Station-local days from `start`, built the way `TimelineStrip.dayChrome`
    /// builds them: each day's first rise and first set.
    private func localDays(_ observer: Observer, zone: String, from start: String,
                           count: Int) throws -> [TimelineDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        var day = cal.startOfDay(for: try XCTUnwrap(ISO8601DateFormatter().date(from: start)))
        var days: [TimelineDay] = []
        for offset in 0..<count {
            let next = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: day))
            let sun = try sunEvents(from: day, to: next, observer: observer)
            let moon = try moonEvents(from: day, to: next, observer: observer)
            days.append(TimelineDay(offset: offset, start: day,
                                    sunrise: sun.first { $0.kind == .rise }?.time,
                                    sunset: sun.first { $0.kind == .set }?.time,
                                    moonrise: moon.first { $0.kind == .rise }?.time,
                                    moonset: moon.first { $0.kind == .set }?.time))
            day = next
        }
        return days
    }

    /// In the tropics the sun and moon also cross the meridian on the poleward
    /// side of the zenith, and climb so steeply that azimuth barely moves for
    /// hours. Across a June and a December month, both ways round for the sun
    /// and every few days both ways for the moon: each frame faces the side
    /// the body is seen to culminate on, the culmination is mid-frame, and no
    /// body moves right while it is up. Victoria, Sydney and Aasiaat keep the
    /// one side they always had, Aasiaat through the moon's days-long arcs.
    func testFramesFaceTheSideEachArcCulminatesOn() throws {
        let f = ISO8601DateFormatter()
        let size = CGSize(width: 402, height: 240)
        let sites: [(name: String, lat: Double, lon: Double, zone: String, sides: Set<Bool>)] = [
            ("Singapore", 1.2644, 103.8222, "Asia/Singapore", [true, false]),
            ("Honolulu", 21.3067, -157.8670, "Pacific/Honolulu", [true, false]),
            ("Key West", 24.5557, -81.8079, "America/New_York", [true, false]),
            ("Darwin", -12.4706, 130.8458, "Australia/Darwin", [true, false]),
            ("Victoria", 48.4284, -123.3656, "America/Vancouver", [true]),
            ("Sydney", -33.8688, 151.2093, "Australia/Sydney", [false]),
            ("Aasiaat", 68.7098, -52.8699, "America/Nuuk", [true]),
        ]
        for site in sites {
            let observer = try Observer(latitudeDeg: site.lat, longitudeDeg: site.lon)
            var faced: [String: Set<Bool>] = [:]
            // One high moon each way round, for the limb check below.
            var limbs: [Bool: (time: Date, days: [TimelineDay])] = [:]
            for month in ["2026-06-01T12:00:00Z", "2026-12-01T12:00:00Z"] {
                let days = try localDays(observer, zone: site.zone, from: month, count: 30)
                let bodies: [(name: String, pad: CGFloat, rises: [Date], sets: [Date],
                              altAz: (Date) throws -> AltAz, dec: (Date) throws -> Double)] = [
                    ("sun", sunDiscRadius, days.compactMap(\.sunrise), days.compactMap(\.sunset),
                     { try sunAltAz($0, observer: observer) }, { try sunPosition($0).decDeg }),
                    ("moon", moonGlyphSize / 2, days.compactMap(\.moonrise), days.compactMap(\.moonset),
                     { try moonAltAz($0, observer: observer) }, { try moonPosition($0).decDeg }),
                ]
                for body in bodies {
                    var last: (span: HorizonSpan, x: CGFloat)?
                    // Inner days only: the first and last have no arc either side.
                    var time = days[1].start
                    while time < days[days.count - 1].start {
                        defer { time.addTimeInterval(10 * 60) }
                        let at = try body.altAz(time)
                        guard at.altDeg > 0,
                              let span = SkyState.span(rises: body.rises, sets: body.sets, at: time,
                                                       latitude: site.lat, altAz: body.altAz,
                                                       declination: body.dec)
                        else { last = nil; continue }
                        faced[body.name, default: []].insert(span.facesSouth)
                        let label = "\(site.name) \(body.name) \(f.string(from: time)) alt \(at.altDeg) az \(at.azDeg)"
                        // At an upper culmination the body is seen on the side
                        // its frame faces, and drawn mid-frame. Near the zenith
                        // its azimuth is anyone's guess, so not there.
                        let before = try body.altAz(time.addingTimeInterval(-10 * 60))
                        let after = try body.altAz(time.addingTimeInterval(10 * 60))
                        if !span.circumpolar, at.altDeg >= before.altDeg, at.altDeg >= after.altDeg,
                           at.altDeg < 80 {
                            XCTAssertEqual(cos(at.azDeg * .pi / 180) < 0, span.facesSouth, "\(label): faces away")
                            let mid = skyPoint(azimuth: at.azDeg, altitude: at.altDeg, latitude: site.lat,
                                               span: span, pad: body.pad, size: size).x
                            XCTAssertEqual(mid, size.width / 2, accuracy: size.width / 4, "\(label): off centre")
                        }
                        if body.name == "moon", at.altDeg > 30, limbs[span.facesSouth] == nil {
                            limbs[span.facesSouth] = (time, days)
                        }
                        let x = skyBodyPoint(azimuth: at.azDeg, altitude: at.altDeg, latitude: site.lat,
                                             span: span, pad: body.pad, size: size).x
                        // A circumpolar moon runs round through the frame's edges.
                        if let last, last.span == span, !span.circumpolar {
                            XCTAssertLessThanOrEqual(x, last.x + 0.5, "\(label): moved right")
                        }
                        last = (span, x)
                    }
                }
            }
            // No tropical sun at Key West, and none at all at Aasiaat in June or December.
            if !["Key West", "Aasiaat"].contains(site.name) {
                XCTAssertEqual(faced["sun"], site.sides, "\(site.name): the sun's sides")
            }
            XCTAssertEqual(faced["moon"], site.sides, "\(site.name): the moon's sides")
            // Facing north the frame is the sky as seen, so the limb is not mirrored there.
            for (facesSouth, limb) in limbs {
                let sky = SkyState(time: limb.time, latitude: site.lat, longitude: site.lon, days: limb.days)
                XCTAssertEqual(sky.moonSpan?.facesSouth, facesSouth)
                assertBackdropLimbFacesTheDrawnSun(sky, sun: try sunAltAz(limb.time, observer: observer),
                                                   moon: try moonAltAz(limb.time, observer: observer),
                                                   "\(site.name) \(f.string(from: limb.time))")
            }
        }
    }

    /// Honolulu, 27 January 2026 at 00:00 UTC: the sun culminates south and
    /// the moon north, so their frames face apart. The limb turns to the side
    /// the sun is drawn on and keeps its lean, and as the drawn sun passes
    /// over the moon it turns through vertical instead of snapping across.
    func testMoonLimbFacesTheDrawnSunWhenTheirFramesFaceApart() throws {
        let honolulu = (lat: 21.3067, lon: -157.8670)
        let observer = try Observer(latitudeDeg: honolulu.lat, longitudeDeg: honolulu.lon)
        let at = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-27T00:00:00Z"))
        let days = try localDays(observer, zone: "Pacific/Honolulu", from: "2026-01-25T12:00:00Z", count: 4)
        let sky = SkyState(time: at, latitude: honolulu.lat, longitude: honolulu.lon, days: days)
        XCTAssertEqual(sky.sunSpan?.facesSouth, true)
        XCTAssertEqual(sky.moonSpan?.facesSouth, false)
        assertBackdropLimbFacesTheDrawnSun(sky, sun: try sunAltAz(at, observer: observer),
                                           moon: try moonAltAz(at, observer: observer), "Honolulu")
        var last = sky.backdropMoonLightAngle(sunDrawnOffset: -100)
        for offset in stride(from: -99, through: 100, by: 1) {
            let limb = sky.backdropMoonLightAngle(sunDrawnOffset: CGFloat(offset))
            XCTAssertLessThan(abs(atan2(sin(limb - last), cos(limb - last))), 5 * .pi / 180, "at \(offset)pt")
            last = limb
        }
        XCTAssertEqual(cos(sky.backdropMoonLightAngle(sunDrawnOffset: 0)), 0, accuracy: 1e-9)
    }

    /// Through moon passes whose frame faces away from the sun's, the
    /// backdrop limb never jumps: not at sunset, where the rule changes from
    /// the drawn sun to the moon's own frame, and not at solar midnight, where
    /// a set sun's off-screen x wraps round. Honolulu: the waxing fortnight in
    /// June, the sun's frame facing north, for sunsets; and a January night,
    /// the sun's frame facing south, for a wrap. (A north-facing sun frame
    /// never wraps: the sun's lower culmination is due north too.)
    func testMoonLimbTurnsSmoothlyWhileItsFrameFacesAwayFromTheSun() throws {
        let honolulu = (lat: 21.3067, lon: -157.8670)
        let observer = try Observer(latitudeDeg: honolulu.lat, longitudeDeg: honolulu.lon)
        let size = CGSize(width: 400, height: 160), step: TimeInterval = 10 * 60
        var sunsets = 0, wraps = 0
        for (start, count) in [("2026-06-14T12:00:00Z", 16), ("2026-01-25T12:00:00Z", 4)] {
            let days = try localDays(observer, zone: "Pacific/Honolulu", from: start, count: count)
            var last: (limb: Double, sunX: CGFloat, apart: Bool)?
            var time = days[1].start
            while time < days[days.count - 1].start {
                defer { time.addTimeInterval(step) }
                guard let moon = try? moonAltAz(time, observer: observer), moon.altDeg > 0,
                      // Near the zenith the true tilt itself swings quickly.
                      moon.altDeg < 70 else { last = nil; continue }
                let sky = SkyState(time: time, latitude: honolulu.lat, longitude: honolulu.lon, days: days)
                let sun = try XCTUnwrap(sky.sun)
                let apart = sky.sunSpan != nil && sky.moonSpan != nil
                    && sky.sunSpan?.facesSouth != sky.moonSpan?.facesSouth
                let sunX = skyBodyPoint(azimuth: sun.azDeg, altitude: sun.altDeg, latitude: honolulu.lat,
                                        span: sky.sunSpan, pad: sunDiscRadius, size: size).x
                let moonX = skyBodyPoint(azimuth: moon.azDeg, altitude: moon.altDeg, latitude: honolulu.lat,
                                         span: sky.moonSpan, pad: moonGlyphSize / 2, size: size).x
                let limb = sky.backdropMoonLightAngle(sunDrawnOffset: sunX - moonX)
                if let last {
                    XCTAssertLessThan(abs(atan2(sin(limb - last.limb), cos(limb - last.limb))), 20 * .pi / 180,
                                      ISO8601DateFormatter().string(from: time))
                    if apart, last.apart {
                        if (try? sunAltAz(time.addingTimeInterval(-step), observer: observer))?.altDeg ?? 0 > 0,
                           sun.altDeg <= 0 { sunsets += 1 }
                        if abs(sunX - last.sunX) > size.width { wraps += 1 }
                    }
                }
                last = (limb, sunX, apart)
            }
        }
        XCTAssertGreaterThan(sunsets, 0, "no sunset while the frames faced apart")
        XCTAssertGreaterThan(wraps, 0, "no midnight wrap while the frames faced apart")
    }

    /// The night the sun's crossing changes sides, its span flips round at
    /// midnight; the stars keep facing the equator, so the field only
    /// stretches a little. Singapore, 23 March 2026, as the sun's declination
    /// passes the latitude.
    func testStarsDoNotFlipWhenTheSunsCrossingChangesSides() throws {
        let singapore = (lat: 1.2644, lon: 103.8222)
        let observer = try Observer(latitudeDeg: singapore.lat, longitudeDeg: singapore.lon)
        let days = try localDays(observer, zone: "Asia/Singapore", from: "2026-03-20T12:00:00Z", count: 7)
        func sunSpan(_ time: Date) -> HorizonSpan? {
            SkyState.span(rises: days.compactMap(\.sunrise), sets: days.compactMap(\.sunset), at: time,
                          latitude: singapore.lat, altAz: { try sunAltAz($0, observer: observer) },
                          declination: { try sunPosition($0).decDeg })
        }
        // Find the flip to the second, between two noons either side of it.
        var lo = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-23T04:00:00Z"))
        var hi = lo.addingTimeInterval(86_400)
        let first = try XCTUnwrap(sunSpan(lo)).facesSouth
        XCTAssertNotEqual(try XCTUnwrap(sunSpan(hi)).facesSouth, first, "no flip in this window")
        while hi.timeIntervalSince(lo) > 1 {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            if sunSpan(mid)?.facesSouth == first { lo = mid } else { hi = mid }
        }
        let a = SkyState(time: lo, latitude: singapore.lat, longitude: singapore.lon, days: days)
        let b = SkyState(time: hi, latitude: singapore.lat, longitude: singapore.lon, days: days)
        XCTAssertLessThan(try XCTUnwrap(a.sun).altDeg, -18, "the flip is at night")
        XCTAssertEqual(a.starSpan?.facesSouth, true)
        XCTAssertEqual(b.starSpan?.facesSouth, true)
        let size = CGSize(width: 402, height: 240)
        var compared = 0
        for (s, t) in zip(a.stars, b.stars) where s.at.altDeg > 10 {
            let p = skyPoint(azimuth: s.at.azDeg, altitude: s.at.altDeg, latitude: singapore.lat,
                             span: a.starSpan, size: size)
            let q = skyPoint(azimuth: t.at.azDeg, altitude: t.at.altDeg, latitude: singapore.lat,
                             span: b.starSpan, size: size)
            if (0...size.width).contains(p.x) {
                XCTAssertLessThan(abs(p.x - q.x), 4, "a star jumped at the flip")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 10)
    }

    func testWinterSunEntersAndLeavesAtTheEdges() throws {
        let observer = try Observer(latitudeDeg: 48.535, longitudeDeg: -123.01)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        // The LOCAL day, the same window `TimelineStrip.dayChrome` builds. A
        // UTC day at this longitude straddles two local days and hands back a
        // sunset with the NEXT day's sunrise — a pair in the wrong order, which
        // no `TimelineDay` ever holds. The assert below keeps that honest.
        let noon = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-21T20:00:00Z"))
        let dayStart = cal.startOfDay(for: noon)
        let dayEnd = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: dayStart))
        let events = try sunEvents(from: dayStart, to: dayEnd, observer: observer)
        let rise = try XCTUnwrap(events.first { $0.kind == .rise })
        let set = try XCTUnwrap(events.first { $0.kind == .set })
        XCTAssertLessThan(rise.time, set.time, "a local day rises before it sets")
        let size = CGSize(width: 400, height: 320)
        // The spans come from the strip's day chrome, not from a second
        // search inside SkyState — so the test hands it the same shape
        // `TimelineData.days` does.
        let days = [TimelineDay(offset: 0, start: dayStart, sunrise: rise.time, sunset: set.time,
                                moonrise: nil, moonset: nil)]

        let rising = SkyState(time: rise.time, latitude: 48.535, longitude: -123.01, days: days)
        let sun = try XCTUnwrap(rising.sun)
        let atRise = skyPoint(azimuth: sun.azDeg, altitude: sun.altDeg, latitude: 48.535,
                              span: rising.sunSpan, pad: sunDiscRadius, size: size)
        XCTAssertEqual(atRise.x, 400 + sunDiscRadius, accuracy: 0.001)
        XCTAssertGreaterThan(atRise.y, 320, "the upper limb is on the horizon, the centre below it")

        let setting = SkyState(time: set.time, latitude: 48.535, longitude: -123.01, days: days)
        let sunSet = try XCTUnwrap(setting.sun)
        let atSet = skyPoint(azimuth: sunSet.azDeg, altitude: sunSet.altDeg, latitude: 48.535,
                             span: setting.sunSpan, pad: sunDiscRadius, size: size)
        XCTAssertEqual(atSet.x, -sunDiscRadius, accuracy: 0.001)
        XCTAssertNil(setting.moonSpan, "no moon chrome, no moon span")
    }

    /// No day chrome (an online gate still fetching) means no span: SkyBackdrop
    /// shows the whole 360° rather than inventing edges.
    func testSpansAreAbsentWithoutDayChrome() throws {
        let noon = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-21T20:00:00Z"))
        let sky = SkyState(time: noon, latitude: 48.535, longitude: -123.01)
        XCTAssertNil(sky.sunSpan)
        XCTAssertNil(sky.moonSpan)
    }

    /// The terminator is an ellipse, not an offset circle: a half moon is lit
    /// exactly to the meridian, a gibbous moon past it, a crescent short of it.
    func testMoonTerminatorFollowsThePhaseAngle() {
        let r: CGFloat = 10
        func lit(_ fraction: Double, _ x: CGFloat) -> Bool {
            moonLitPath(fraction: fraction, radius: r).contains(CGPoint(x: x, y: 0))
        }
        XCTAssertTrue(lit(0.5, 1)); XCTAssertFalse(lit(0.5, -1))
        XCTAssertTrue(lit(0.9, -5)); XCTAssertFalse(lit(0.9, -9))    // ellipse half-width 8
        XCTAssertFalse(lit(0.1, 5)); XCTAssertTrue(lit(0.1, 9))
        XCTAssertTrue(lit(1, -9)); XCTAssertFalse(lit(0, 9))
    }

    /// The tilt is Almanac's bright limb, turned into SwiftUI's frame. A waxing
    /// crescent low in the west after sunset is lit on its lower right from
    /// Victoria and on its lower left from Sydney. At every instant the limb
    /// points along the great circle to the sun, within a couple of degrees:
    /// the sun's direction at the moon, worked from both bodies' alt/az.
    func testMoonTiltAimsTheLitLimbAtTheSun() throws {
        let f = ISO8601DateFormatter()
        let victoria = (lat: 48.4284, lon: -123.3656), sydney = (lat: -33.8688, lon: 151.2093)
        func tilt(_ time: String, _ site: (lat: Double, lon: Double)) throws -> Double {
            let observer = try Observer(latitudeDeg: site.lat, longitudeDeg: site.lon)
            return try XCTUnwrap(moonTilt(at: XCTUnwrap(f.date(from: time)), observer: observer))
        }
        let north = try tilt("2026-10-15T02:00:00Z", victoria)
        XCTAssertGreaterThan(cos(north), 0, "lit on the right")
        XCTAssertGreaterThan(sin(north), 0, "lit from below (y runs down)")
        let south = try tilt("2026-10-14T09:00:00Z", sydney)
        XCTAssertLessThan(cos(south), 0, "lit on the left")
        XCTAssertGreaterThan(sin(south), 0, "lit from below (y runs down)")

        func gap(_ a: Double, _ b: Double) -> Double { abs(atan2(sin(a - b), cos(a - b))) }
        for (time, site) in [("2026-10-15T02:00:00Z", victoria), ("2026-10-19T01:17:00Z", victoria),
                             ("2026-10-21T06:00:00Z", victoria),
                             ("2026-10-28T12:00:00Z", victoria), ("2026-11-02T15:00:00Z", victoria),
                             ("2026-10-14T09:00:00Z", sydney), ("2026-10-21T12:00:00Z", sydney),
                             ("2026-11-02T19:00:00Z", sydney)] {
            let at = try XCTUnwrap(f.date(from: time))
            let observer = try Observer(latitudeDeg: site.lat, longitudeDeg: site.lon)
            let sun = try sunAltAz(at, observer: observer), moon = try moonAltAz(at, observer: observer)
            let sunAlt = sun.altDeg * .pi / 180, moonAlt = moon.altDeg * .pi / 180
            let deltaAz = (sun.azDeg - moon.azDeg) * .pi / 180
            // Facing the moon, a larger azimuth is to the right.
            let right = cos(sunAlt) * sin(deltaAz)
            let up = sin(sunAlt) * cos(moonAlt) - cos(sunAlt) * sin(moonAlt) * cos(deltaAz)
            let toSun = atan2(-up, right)
            XCTAssertLessThan(gap(try tilt(time, site), toSun), 2 * .pi / 180, time)
            // The tiles and the Moon sheet draw the moon as seen.
            let sky = SkyState(time: at, latitude: site.lat, longitude: site.lon)
            XCTAssertLessThan(gap(sky.moonLightAngle, toSun), 2 * .pi / 180, time)
            assertBackdropLimbFacesTheDrawnSun(sky, sun: sun, moon: moon, time)
        }
    }

    /// The backdrop's limb faces the sun as drawn. Where both frames face
    /// the same way, or the sun is down, it faces it as `skyPoint` draws it
    /// in the moon's own frame: a step from the moon toward the sun lands on
    /// the side the limb points. The frame stretches azimuth and altitude
    /// unequally, so only the signs carry over. Where they face apart with
    /// the sun up, the limb points across to the side the sun is drawn on,
    /// leaning up or down as it is seen.
    private func assertBackdropLimbFacesTheDrawnSun(_ sky: SkyState, sun: AltAz, moon: AltAz, _ label: String,
                                                    line: UInt = #line) {
        let size = CGSize(width: 400, height: 160)
        let sunDrawn = skyBodyPoint(azimuth: sun.azDeg, altitude: sun.altDeg, latitude: sky.latitude,
                                    span: sky.sunSpan, pad: sunDiscRadius, size: size)
        let moonDrawn = skyBodyPoint(azimuth: moon.azDeg, altitude: moon.altDeg, latitude: sky.latitude,
                                     span: sky.moonSpan, pad: moonGlyphSize / 2, size: size)
        let limb = sky.backdropMoonLightAngle(sunDrawnOffset: sunDrawn.x - moonDrawn.x)
        let north = sky.latitude >= 0
        guard (sky.sunSpan?.facesSouth ?? north) == (sky.moonSpan?.facesSouth ?? north) || sun.altDeg <= 0 else {
            XCTAssertEqual(cos(limb) > 0, sunDrawn.x > moonDrawn.x, "\(label): limb faces the drawn sun across",
                           line: line)
            XCTAssertEqual(sin(limb) > 0, sin(sky.moonLightAngle) > 0, "\(label): limb keeps its lean",
                           line: line)
            return
        }
        let sunAlt = sun.altDeg * .pi / 180, moonAlt = moon.altDeg * .pi / 180
        let deltaAz = (sun.azDeg - moon.azDeg) * .pi / 180
        let right = cos(sunAlt) * sin(deltaAz)
        let up = sin(sunAlt) * cos(moonAlt) - cos(sunAlt) * sin(moonAlt) * cos(deltaAz)
        let step = 0.5
        let norm = hypot(right, up)
        let here = skyPoint(azimuth: moon.azDeg, altitude: moon.altDeg, latitude: sky.latitude,
                            span: sky.moonSpan, size: size)
        let there = skyPoint(azimuth: moon.azDeg + step * right / norm / cos(moonAlt),
                             altitude: moon.altDeg + step * up / norm, latitude: sky.latitude,
                             span: sky.moonSpan, size: size)
        if abs(right) > 0.1 * norm {
            XCTAssertEqual(cos(limb) > 0, there.x > here.x, "\(label): limb faces the drawn sun across", line: line)
        }
        if abs(up) > 0.1 * norm {
            XCTAssertEqual(sin(limb) > 0, there.y > here.y, "\(label): limb faces the drawn sun vertically",
                           line: line)
        }
    }

    /// Phase names are presentation, kept app-side when the astronomy moved to
    /// Almanac (#228). The prototype's moonName buckets, driven by phase.
    func testMoonPhaseNames() {
        XCTAssertEqual(moonPhaseName(phase: 0.001), "New Moon")
        XCTAssertEqual(moonPhaseName(phase: 0.995), "New Moon")
        XCTAssertEqual(moonPhaseName(phase: 0.25), "First Quarter")
        XCTAssertEqual(moonPhaseName(phase: 0.5), "Full Moon")
        XCTAssertEqual(moonPhaseName(phase: 0.75), "Last Quarter")
        XCTAssertEqual(moonPhaseName(phase: 0.12), "Waxing Crescent")
        XCTAssertEqual(moonPhaseName(phase: 0.38), "Waxing Gibbous")
        XCTAssertEqual(moonPhaseName(phase: 0.62), "Waning Gibbous")
        XCTAssertEqual(moonPhaseName(phase: 0.88), "Waning Crescent")
    }

    /// `moonPhaseBlurb` is keyed on the displayed name, so a reworded phase or
    /// eclipse title silently drops its gloss instead of failing to compile.
    /// Sweeping the whole synodic month plus all three eclipse kinds is what
    /// catches that.
    func testEveryPhaseAndEclipseTitleHasABlurb() {
        for step in 0...295 {
            let name = moonPhaseName(phase: Double(step) / 295)
            XCTAssertFalse(moonPhaseBlurb(name).isEmpty, "no blurb for \(name)")
        }
        for kind in [LunarEclipseKind.total, .partial, .penumbral] {
            let name = eclipseTileText(kind)
            XCTAssertFalse(moonPhaseBlurb(name).isEmpty, "no blurb for \(name)")
        }
    }

    func testMoonTideLabelsCombinePhaseAndNearbyDistanceExtremes() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let near = at.addingTimeInterval(86_400)
        let away = at.addingTimeInterval(3 * 86_400)

        XCTAssertEqual(moonTideLabel(phase: 0, at: at, perigee: nil, apogee: nil), "Spring tide")
        XCTAssertEqual(moonTideLabel(phase: 0.5, at: at, perigee: near, apogee: nil), "Perigean spring tide")
        XCTAssertEqual(moonTideLabel(phase: 0.25, at: at, perigee: nil, apogee: near), "Apogean neap tide")
        XCTAssertEqual(moonTideLabel(phase: 0.75, at: at, perigee: nil, apogee: nil), "Neap tide")
        XCTAssertEqual(moonTideLabel(phase: 0.12, at: at, perigee: near, apogee: nil), "Perigean tide")
        XCTAssertEqual(moonTideLabel(phase: 0.38, at: at, perigee: nil, apogee: near), "Apogean tide")
        XCTAssertNil(moonTideLabel(phase: 0.12, at: at, perigee: away, apogee: nil))
    }

    func testMoonTideExplanationRelatesPhaseAndDistance() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let near = at.addingTimeInterval(86_400)

        let apogeanSpring = moonTideExplanation(phase: 0.5, at: at, perigee: nil, apogee: near)
        XCTAssertTrue(apogeanSpring.contains("farther"))
        XCTAssertTrue(apogeanSpring.contains("lower highs and higher lows than during a perigean spring tide"))
        XCTAssertFalse(apogeanSpring.contains("below-average"))

        let perigeanSpring = moonTideExplanation(phase: 0, at: at, perigee: near, apogee: nil)
        XCTAssertTrue(perigeanSpring.contains("closer"))
        XCTAssertTrue(perigeanSpring.contains("higher highs and lower lows than during an apogean spring tide"))

        let apogeanNeap = moonTideExplanation(phase: 0.25, at: at, perigee: nil, apogee: near)
        let perigeanNeap = moonTideExplanation(phase: 0.75, at: at, perigee: near, apogee: nil)
        XCTAssertTrue(apogeanNeap.contains("narrows the range further"))
        XCTAssertTrue(perigeanNeap.contains("offsets some of the neap narrowing"))
    }

    /// The names have to agree with Almanac's own phase convention (0 new,
    /// 0.5 full), not just with the bucket arithmetic: the 2026-08-28 full
    /// moon is the eclipse night #222 is about, and it must read "Full Moon".
    func testPhaseNameAgreesWithAlmanacAtAKnownFullMoon() throws {
        let peak = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-28T04:13:00Z"))
        let moon = try moonIllumination(peak)
        XCTAssertEqual(moonPhaseName(phase: moon.phase), "Full Moon")
        XCTAssertGreaterThan(moon.fraction, 0.99)
    }
}
