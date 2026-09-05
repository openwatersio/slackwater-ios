// Slackwater — GPL v3.
import CoreGraphics
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
        XCTAssertTrue(skyUsesDarkInk(sunAltitude: 10))
        XCTAssertTrue(skyUsesDarkInk(sunAltitude: 0))
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
        for (azimuth, expected) in [(90.0, CGPoint(x: 0, y: 320)),
                                    (180, CGPoint(x: 200, y: 120)),
                                    (270, CGPoint(x: 400, y: 320))] {
            let point = sunArcPoint(azimuth: azimuth, size: arc)
            XCTAssertEqual(point.x, expected.x, accuracy: 0.001)
            XCTAssertEqual(point.y, expected.y, accuracy: 0.001)
        }
    }
}
