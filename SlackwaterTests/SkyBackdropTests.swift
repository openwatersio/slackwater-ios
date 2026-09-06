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
        XCTAssertEqual(starOpacity(sunAltitude: 0), 0)
        XCTAssertEqual(starOpacity(sunAltitude: -12), 0.35, accuracy: 0.001)
        XCTAssertEqual(starOpacity(sunAltitude: -18), 0.7)
        XCTAssertEqual(starTwinkle(index: 3, seconds: 10, reduceMotion: true), 1)
        XCTAssertGreaterThanOrEqual(starTwinkle(index: 3, seconds: 10, reduceMotion: false), 0.72)
        XCTAssertLessThanOrEqual(starTwinkle(index: 3, seconds: 10, reduceMotion: false), 1)
        XCTAssertNotEqual(starTwinkle(index: 3, seconds: 10, reduceMotion: false),
                          starTwinkle(index: 3, seconds: 11, reduceMotion: false))
        XCTAssertEqual(skyOpacity(sunAltitude: 0), 0.55)
        XCTAssertEqual(skyOpacity(sunAltitude: -6), 1)

        let size = CGSize(width: 400, height: 160)
        XCTAssertEqual(skyPoint(azimuth: 180, altitude: 0, latitude: 48, size: size),
                       CGPoint(x: 200, y: 160))
        XCTAssertEqual(skyPoint(azimuth: 180, altitude: 90, latitude: 48, size: size),
                       CGPoint(x: 200, y: 0))
        XCTAssertEqual(skyPoint(azimuth: 90, altitude: 0, latitude: 48, size: size),
                       CGPoint(x: 100, y: 160))

        let arc = CGSize(width: 400, height: 320)
        for (progress, expected) in [(0.0, CGPoint(x: 0, y: 320)),
                                     (0.5, CGPoint(x: 200, y: 120)),
                                     (1.0, CGPoint(x: 400, y: 320))] {
            let point = sunArcPoint(progress: progress, size: arc)
            XCTAssertEqual(point.x, expected.x, accuracy: 0.001)
            XCTAssertEqual(point.y, expected.y, accuracy: 0.001)
        }
    }

    func testWinterSunArcMeetsHorizonAtActualRiseAndSet() throws {
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
        // The arc's endpoints come from the strip's day chrome, not from a
        // second computation inside SkyState — so the test hands it the same
        // shape `TimelineData.days` does.
        let days = [TimelineDay(offset: 0, start: dayStart, sunrise: rise.time, sunset: set.time)]

        for time in [rise.time.addingTimeInterval(60), set.time.addingTimeInterval(-60)] {
            let sky = SkyState(time: time, latitude: 48.535, longitude: -123.01, days: days)
            let point = sunArcPoint(progress: try XCTUnwrap(sky.sunProgress), size: size)
            XCTAssertGreaterThan(point.y, 318)
        }
    }

    /// No day chrome (an online gate still fetching) means no arc: SkyBackdrop
    /// falls back to the sun's true az/alt rather than inventing endpoints.
    func testSunArcIsAbsentWithoutDayChrome() throws {
        let noon = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-21T20:00:00Z"))
        XCTAssertNil(SkyState(time: noon, latitude: 48.535, longitude: -123.01).sunProgress)
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
