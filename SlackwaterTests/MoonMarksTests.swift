// Slackwater — GPL v3. The Moon sheet's two drawings: the geometry behind the
// orbit, and the pair of horizon marks that have to be told apart at a glance.
import SwiftUI
import UIKit
import XCTest
@testable import Slackwater

final class MoonMarksTests: XCTestCase {
    private let anomalisticMonth = 27.554_549 * 86_400.0

    // MARK: - The orbit's geometry

    func testTheOrbitAngleRunsFromPerigee() {
        let perigee = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(moonOrbitAngle(at: perigee, perigee: perigee), 0, accuracy: 1e-9)
        XCTAssertEqual(moonOrbitAngle(at: perigee.addingTimeInterval(anomalisticMonth / 2),
                                      perigee: perigee), .pi, accuracy: 1e-6)
        // A whole month on is perigee again, not a second lap: the angle wraps
        // rather than growing, or the moon would fly off the drawing.
        //
        // Asserted on the POINT, not the angle. One period lands on 2π rather
        // than 0 — `turns` comes out a hair under 1.0 and the floor keeps it —
        // and 2π and 0 are the same place on an ellipse. The drawing is what
        // has to be right; the number naming it is free to take either form.
        let lap = orbitPoint(trueAnomaly: moonOrbitAngle(
            at: perigee.addingTimeInterval(anomalisticMonth), perigee: perigee), a: 100, e: 0.35)
        let start = orbitPoint(trueAnomaly: 0, a: 100, e: 0.35)
        XCTAssertEqual(lap.x, start.x, accuracy: 1e-6)
        XCTAssertEqual(lap.y, start.y, accuracy: 1e-6)
        // And it runs backward as readily as forward — `closest` is sampled
        // from a window that starts fifteen days BEFORE the scrub time, so a
        // perigee in the future is the ordinary case, not the exception.
        let ahead = moonOrbitAngle(at: perigee.addingTimeInterval(-anomalisticMonth / 4),
                                   perigee: perigee)
        XCTAssertEqual(ahead, 1.5 * .pi, accuracy: 1e-6)
    }

    func testTheOrbitIsClosestAtPerigeeAndFarthestAtApogee() {
        func radius(_ v: Double) -> Double {
            let p = orbitPoint(trueAnomaly: v, a: 100, e: 0.35)
            return (p.x * p.x + p.y * p.y).squareRoot()
        }
        // The polar ellipse: a(1 − e) at perigee, a(1 + e) at apogee.
        XCTAssertEqual(radius(0), 65, accuracy: 0.01)
        XCTAssertEqual(radius(.pi), 135, accuracy: 0.01)
        // Monotonic in between, which is what lets the moon's position on the
        // path stand in for its distance.
        for step in 1...90 {
            let v = Double(step) * .pi / 90
            XCTAssertGreaterThan(radius(v), radius(v - .pi / 90),
                                 "the radius fell while travelling to apogee at \(v)")
        }
    }

    // MARK: - The horizon marks

    @MainActor
    private func shot<V: View>(_ view: V) throws -> UIImage {
        let renderer = ImageRenderer(content:
            view.frame(width: 78, height: 44).background(SN.canvas))
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage)
    }

    /// Rise and set put the moon in the same place — that IS where it is at
    /// both events — so the trail and the arrow carry the whole distinction.
    /// If these two ever render alike, the sheet has two identical pictures
    /// captioned differently, which is worse than no picture at all.
    @MainActor
    func testTheRisingAndSettingMarksAreTellableApart() throws {
        let rising = try shot(MoonHorizonMark(fraction: 0.5, waxing: true, rising: true))
        let setting = try shot(MoonHorizonMark(fraction: 0.5, waxing: true, rising: false))
        XCTAssertGreaterThan(differingFraction(rising, setting), 0.02,
                             "the rise and set marks draw the same picture")
    }

    /// The moon is cut at the horizon rather than sitting on top of it: at
    /// moonrise half the disc is still below the line, and a tangent circle
    /// would be a moon that has already cleared it.
    @MainActor
    func testTheMarkSinksTheMoonToTheHorizon() throws {
        let mark = try shot(MoonHorizonMark(fraction: 1, waxing: true, rising: true))
        let full = try shot(MoonGlyph(fraction: 1, waxing: true, size: 26))
        XCTAssertGreaterThan(inkFraction(mark), 0.01, "the horizon mark drew nothing")
        XCTAssertLessThan(inkFraction(mark), inkFraction(full),
                          "the mark shows as much moon as a whole disc — nothing is submerged")
    }
}
