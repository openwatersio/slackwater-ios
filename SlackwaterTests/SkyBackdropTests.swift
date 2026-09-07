// Slackwater — GPL v3.
import CoreGraphics
import Almanac
import XCTest
@testable import Slackwater

final class SkyBackdropTests: XCTestCase {
    func testEveryScrubDetailUsesTheSkyBackdrop() throws {
        for file in ["Slackwater/TideDetailView.swift", "Slackwater/CurrentDetailView.swift",
                     "Slackwater/OnlineGateDetailView.swift", "Slackwater/DerivedGateDetailView.swift"] {
            XCTAssertTrue(try repoSource(file).contains("topBackdrop: AnyView(SkyBackdrop(sky: sky))"), file)
        }
        XCTAssertTrue(try repoSource("Slackwater/CurrentLead.swift").contains("showsDayBands: false"))
    }

    func testStarsStandWhereTheAlmanacPutsTheSun() throws {
        // The sun is a star with a known RA/Dec: fed to the star transform,
        // Almanac's apparent position must land where sunAltAz puts it, give
        // or take refraction and the mean/apparent sidereal difference.
        let time = ISO8601DateFormatter().date(from: "2026-03-20T20:00:00Z")!
        let lat = 48.4, lon = -123.4
        let sun = try sunPosition(time)
        let expected = try sunAltAz(time, observer: Observer(latitudeDeg: lat, longitudeDeg: lon))
        let lst = localSiderealDeg(time, longitude: lon)
        let got = starAltAz(raDeg: sun.raDeg, decDeg: sun.decDeg, siderealDeg: lst, latitude: lat)
        XCTAssertEqual(got.altDeg, expected.altDeg, accuracy: 0.1)
        XCTAssertEqual(got.azDeg, expected.azDeg, accuracy: 0.1)
        // Polaris stands at the latitude, due north, whatever the hour.
        let polaris = starAltAz(raDeg: 37.95, decDeg: 89.26, siderealDeg: lst, latitude: lat)
        XCTAssertEqual(polaris.altDeg, lat, accuracy: 1)
        XCTAssertTrue(polaris.azDeg < 2 || polaris.azDeg > 358, "\(polaris.azDeg)")
        // Sirius leads the catalog.
        XCTAssertEqual(brightStars.count, 288)
        XCTAssertEqual(brightStars.first?.mag, -1.44)
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
                              span: rising.sunSpan, pad: sunGlowRadius, size: size)
        XCTAssertEqual(atRise.x, 400 + sunGlowRadius, accuracy: 0.001)
        XCTAssertGreaterThan(atRise.y, 320, "the upper limb is on the horizon, the centre below it")

        let setting = SkyState(time: set.time, latitude: 48.535, longitude: -123.01, days: days)
        let sunSet = try XCTUnwrap(setting.sun)
        let atSet = skyPoint(azimuth: sunSet.azDeg, altitude: sunSet.altDeg, latitude: 48.535,
                             span: setting.sunSpan, pad: sunGlowRadius, size: size)
        XCTAssertEqual(atSet.x, -sunGlowRadius, accuracy: 0.001)
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
