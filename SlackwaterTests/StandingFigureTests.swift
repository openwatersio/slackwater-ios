import XCTest
import SlackwaterKit
@testable import Slackwater

/// The figure's layout, without drawing it. Everything interesting about the
/// nesting is a decision about levels and a shared vertical scale, so that is
/// what `StandingFigure.levels` returns and what these hold.
final class StandingFigureTests: XCTestCase {
    private let height: CGFloat = 200

    /// A big swing, but not the fortnight's biggest, with room at both ends.
    private func standing(low: Double = 1.0, high: Double = 4.6,
                          bandLow: Double = 0.6, bandHigh: Double = 4.9) -> TideStanding {
        let t = Date(timeIntervalSince1970: 1_780_000_000)
        return TideStanding(
            selected: TideExtreme(time: t, height: low, kind: .low),
            rank: 0.05,
            windowHighest: TideExtreme(time: t.addingTimeInterval(3_600), height: bandHigh, kind: .high),
            windowLowest: TideExtreme(time: t.addingTimeInterval(7_200), height: bandLow, kind: .low),
            nextMoreExtreme: nil)
    }

    func testAllThreeLevelsShareOneScale() {
        let levels = StandingFigure.levels(standing: standing(), latDatum: 0, hatDatum: 5.4, height: height)
        let lat = levels.first { $0.role == .absoluteLow }!
        let hat = levels.first { $0.role == .absoluteHigh }!
        let bandLow = levels.first { $0.role == .fortnightLow }!
        // 0.6 m above a 5.4 m span, measured from the bottom.
        XCTAssertEqual((lat.y - bandLow.y) / (lat.y - hat.y), 0.6 / 5.4, accuracy: 0.01,
                       "a level's position is its real height on the shared axis")
    }

    /// Review Focus 1: every CHS station and a fifth of NOAA's references.
    func testWithoutBoundsTheFigureDrawsTwoLevels() {
        let levels = StandingFigure.levels(standing: standing(), latDatum: nil, hatDatum: nil, height: height)
        XCTAssertFalse(levels.contains { $0.role == .absoluteLow || $0.role == .absoluteHigh })
        XCTAssertTrue(levels.contains { $0.role == .fortnightLow })
        XCTAssertTrue(levels.contains { $0.role == .fortnightHigh })
    }

    /// Without an outer frame the band becomes the outermost thing and the
    /// scale fits it, so the figure still fills its box.
    func testWithoutBoundsTheBandSpansTheBox() {
        let levels = StandingFigure.levels(standing: standing(), latDatum: nil, hatDatum: nil, height: height)
        let low = levels.first { $0.role == .fortnightLow }!
        let high = levels.first { $0.role == .fortnightHigh }!
        XCTAssertGreaterThan(low.y - high.y, height * 0.6)
    }

    /// Review Focus 2: the strongest form of the claim. The curve touches both
    /// band lines, and must not read as clipped — the band's lines are drawn
    /// wider than the curve's span, so a touching curve meets a line that
    /// continues past it on both sides.
    func testASwingThatIsTheFortnightsBiggestTouchesBothBandLines() {
        let maximal = standing(low: 0.6, high: 4.9, bandLow: 0.6, bandHigh: 4.9)
        let levels = StandingFigure.levels(standing: maximal, latDatum: 0, hatDatum: 5.4, height: height)
        let band = levels.filter { $0.role == .fortnightLow || $0.role == .fortnightHigh }
        XCTAssertEqual(band.count, 2)
        for line in band {
            XCTAssertGreaterThan(line.width, StandingFigure.curveInset * 2,
                                 "the band outruns the curve so a touch is not a clip")
        }
    }

    /// When a fortnight nearly reaches the station's own ceiling, two lines
    /// land on the same pixel. Merge them rather than nudging either apart:
    /// the shared scale is the figure's whole premise, and the coincidence is
    /// itself the strongest thing the figure can say.
    func testLevelsTooCloseToSeparateMerge() {
        let levels = StandingFigure.levels(standing: standing(bandHigh: 5.37),
                                           latDatum: 0, hatDatum: 5.4, height: height)
        let near = levels.filter { $0.y < StandingFigure.minimumSeparation * 2 }
        XCTAssertEqual(near.count, 1, "two levels within a hair draw as one line")
        XCTAssertTrue(near[0].isMerged)
    }

    func testWellSeparatedLevelsDoNotMerge() {
        let levels = StandingFigure.levels(standing: standing(), latDatum: 0, hatDatum: 5.4, height: height)
        XCTAssertFalse(levels.contains { $0.isMerged })
    }

    /// The point of the whole figure: the curve is drawn on the SAME scale as
    /// the frame, so its amplitude is its real amplitude. A swing using a third
    /// of the fortnight's band occupies a third of the band's height.
    func testTheCurveIsDrawnOnTheSharedScale() {
        let t = Date(timeIntervalSince1970: 1_780_000_000)
        let points = (0...12).map {
            TidePoint(time: t.addingTimeInterval(Double($0) * 1_800),
                      height: 2.8 + 1.8 * cos(Double($0) / 12 * 2 * .pi))
        }
        let s = standing()  // band 0.6…4.9
        let path = StandingFigure.curvePath(points, standing: s, latDatum: 0, hatDatum: 5.4,
                                            size: CGSize(width: 300, height: height))
        let levels = StandingFigure.levels(standing: s, latDatum: 0, hatDatum: 5.4, height: height)
        let bandHigh = levels.first { $0.role == .fortnightHigh }!.y
        let bandLow = levels.first { $0.role == .fortnightLow }!.y
        // The curve spans 1.0…4.6 inside a band of 0.6…4.9: strictly inside.
        XCTAssertGreaterThan(path.boundingRect.minY, bandHigh)
        XCTAssertLessThan(path.boundingRect.maxY, bandLow)
        // 3.6 m of swing against a 5.4 m axis over `height` points.
        XCTAssertEqual(path.boundingRect.height, height * 3.6 / 5.4, accuracy: 2)
    }

    /// Review Focus 2 again, this time on the curve: when the swing IS the
    /// fortnight, its extremes land on the band's lines rather than past them.
    func testTheMaximalCurveLandsOnTheBandLines() {
        let t = Date(timeIntervalSince1970: 1_780_000_000)
        let points = (0...12).map {
            TidePoint(time: t.addingTimeInterval(Double($0) * 1_800),
                      height: 2.75 + 2.15 * cos(Double($0) / 12 * 2 * .pi))
        }
        let maximal = standing(low: 0.6, high: 4.9, bandLow: 0.6, bandHigh: 4.9)
        let path = StandingFigure.curvePath(points, standing: maximal, latDatum: 0, hatDatum: 5.4,
                                            size: CGSize(width: 300, height: height))
        let levels = StandingFigure.levels(standing: maximal, latDatum: 0, hatDatum: 5.4, height: height)
        XCTAssertEqual(path.boundingRect.minY, levels.first { $0.role == .fortnightHigh }!.y, accuracy: 1)
        XCTAssertEqual(path.boundingRect.maxY, levels.first { $0.role == .fortnightLow }!.y, accuracy: 1)
    }

    /// A drawing may never be the only carrier (WCAG 1.4.1), so every level the
    /// figure draws is named in the spoken summary.
    func testTheSpokenSummaryNamesEveryLevelDrawn() {
        let withBounds = StandingFigure.levels(standing: standing(), latDatum: 0, hatDatum: 5.4, height: height)
        let spoken = StandingFigure.summary(levels: withBounds, imperial: false)
        for level in withBounds { XCTAssertTrue(spoken.contains(level.label), level.label) }
    }
}
