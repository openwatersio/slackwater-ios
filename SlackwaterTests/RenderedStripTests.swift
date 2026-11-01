// Slackwater — GPL v3. The timeline strip actually draws, for each of the
// three curve shapes the app has: a tide track on the rate ramp, a derived
// gate's schematic shape, and an online gate's fetched velocities.
//
// Ink coverage, because nothing inside the strip is an accessibility element —
// it is one `Canvas` — so "did it draw" is the only question a test can put to
// it, and it is the question that matters: every readout, label and schedule
// row can be right while the chart renders nothing (the texture-cap blank, the
// empty gradient-stops array). Each threshold is measured against the same
// window with no track on it.
import XCTest
import SwiftUI
@testable import Slackwater
import SlackwaterKit

final class RenderedStripTests: XCTestCase {

    @MainActor
    func testSlackRunOnlyReplacesTheCurve() throws {
        for nowX: CGFloat in [0, 80] {
            let renderer = ImageRenderer(content:
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: 12))
                    line.addLine(to: CGPoint(x: 80, y: 12))
                    var run = Path()
                    run.move(to: CGPoint(x: 20, y: 12))
                    run.addLine(to: CGPoint(x: 60, y: 12))
                    CurveDrawing.currentLine(context, line, slackRuns: [run], samples: [],
                                             nowX: nowX, width: size.width, height: size.height)
                    CurveDrawing.runs(context, [run], nowX: nowX,
                                      width: size.width, height: size.height)
                }
                .frame(width: 80, height: 24)
                .background(Color.red))
            let image = try XCTUnwrap(renderer.uiImage?.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
                                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let side = (9 * image.width + 40) * 4
            XCTAssertGreaterThan(pixels[side], 200, "the run erased beside its body")
            XCTAssertGreaterThan(pixels[side + 1], 200, "the run erased beside its body")
            XCTAssertGreaterThan(pixels[side + 2], 200, "the run erased beside its body")
            let body = (12 * image.width + 40) * 4
            XCTAssertGreaterThan(pixels[body], pixels[body + 2], "the curve did not turn green")
            if nowX > 0 {
                XCTAssertGreaterThan(pixels[body], 180, "the current stroke showed through the faded run")
            }
            let end = (12 * image.width + 63) * 4
            XCTAssertGreaterThan(pixels[end], 200, "the end gap must preserve the layer below the curve")
            XCTAssertGreaterThan(pixels[end + 1], 200, "the end gap must preserve the layer below the curve")
            XCTAssertGreaterThan(pixels[end + 2], 200, "the end gap must preserve the layer below the curve")
        }
    }

    @MainActor
    private func render(_ draw: @escaping (GraphicsContext, CGSize) -> Void) throws -> (pixels: [UInt8], width: Int) {
        let renderer = ImageRenderer(content:
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                draw(context, size)
            }
            .frame(width: 80, height: 24)
            .background(Color.red))
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (pixels, image.width)
    }

    private func horizontal(_ a: CGFloat, _ b: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: a, y: 12))
        path.addLine(to: CGPoint(x: b, y: 12))
        return path
    }

    /// Slack joins its window's blue with no break: green and blue are not the
    /// deuteranopia pair, and a break at every colour change read as a dashed line (#821).
    @MainActor
    func testSlackJoinsItsWindowsBlue() throws {
        let (pixels, width) = try render { context, size in
            let window = self.horizontal(30, 50), slack = self.horizontal(36, 44)
            CurveDrawing.currentLine(context, self.horizontal(0, 80), slackRuns: [window, slack], samples: [],
                                     nowX: 0, width: size.width, height: size.height)
            CurveDrawing.windows(context, [window], nowX: 0, width: size.width, height: size.height)
            CurveDrawing.runs(context, [slack], nowX: 0, width: size.width, height: size.height)
        }
        let green = (12 * width + 40) * 4
        XCTAssertGreaterThan(pixels[green + 1], pixels[green + 2], "the slack is not the go colour")
        let joined = (12 * width + 47) * 4
        XCTAssertGreaterThan(pixels[joined + 2], 150, "the blue must run up to the green")
        XCTAssertLessThan(pixels[joined], 150, "the blue must run up to the green")
    }

    /// With the window off, slack meets the yellow line, and keeps the small
    /// break at its ends that separates the deuteranopia pair.
    @MainActor
    func testSlackWithNoWindowKeepsItsBreakFromTheYellow() throws {
        let (pixels, width) = try render { context, size in
            let slack = self.horizontal(30, 50)
            CurveDrawing.currentLine(context, self.horizontal(0, 80), slackRuns: [slack], samples: [],
                                     nowX: 0, width: size.width, height: size.height)
            CurveDrawing.runs(context, [slack], nowX: 0, width: size.width, height: size.height)
        }
        let gap = (12 * width + 53) * 4
        XCTAssertGreaterThan(pixels[gap + 2], 200, "the break must keep the layer below the curve")
        XCTAssertGreaterThan(pixels[gap + 1], 200, "the break must keep the layer below the curve")
        let line = (12 * width + 60) * 4
        XCTAssertGreaterThan(pixels[line], pixels[line + 2] + 80, "the curve beyond is yellow")
    }

    /// Slack is all lines: a run too short to stroke, and a slack no run
    /// holds, each draw as the shortest slack stroke centred on the slack.
    func testAShortSlackDrawsAsTheShortestStroke() {
        let t = Date(timeIntervalSince1970: 0)
        let long = WindowRun(start: t, end: t.addingTimeInterval(3600))
        let short = WindowRun(start: t.addingTimeInterval(7200), end: t.addingTimeInterval(7260))
        let bare = t.addingTimeInterval(14_400)
        let strokes = slackStrokes(cores: [long, short], bare: [bare], pointsPerHour: Timeline.pph)
        XCTAssertEqual(strokes.count, 3)
        XCTAssertEqual(strokes[0], long, "a run long enough to stroke is drawn as measured")
        let width = { (r: WindowRun) in CGFloat(r.end.timeIntervalSince(r.start) / 3600) * Timeline.pph }
        XCTAssertEqual(width(strokes[1]), CurveStyle.shortestSlackStroke, accuracy: 0.001)
        XCTAssertEqual(strokes[1].centre, short.centre)
        XCTAssertEqual(width(strokes[2]), CurveStyle.shortestSlackStroke, accuracy: 0.001)
        XCTAssertEqual(strokes[2].centre, bare)
        XCTAssertFalse(strokes.contains { $0.drawsAsDot(pointsPerHour: Timeline.pph) }, "never a dot")
    }

    /// A flood lobe fills beneath its curve; an ebb lobe's curve-to-zero area sits above the
    /// curve, and a tide chart never fills there, so it stays clear.
    @MainActor
    func testOnlyTheFloodLobeIsFilled() throws {
        let renderer = ImageRenderer(content:
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                var area = Path()
                area.move(to: CGPoint(x: 0, y: 50))
                area.addLine(to: CGPoint(x: 0, y: 10))
                area.addLine(to: CGPoint(x: 40, y: 10))
                area.addLine(to: CGPoint(x: 40, y: 90))
                area.addLine(to: CGPoint(x: 80, y: 90))
                area.addLine(to: CGPoint(x: 80, y: 50))
                area.closeSubpath()
                CurveDrawing.zeroFill(context, area, plotTop: 0, plotBottom: 100, zeroY: 50)
            }
            .frame(width: 80, height: 100))
        let image = renderer.uiImage
        let p = try pixels(XCTUnwrap(image))
        let flood = (12 * p.width + 20) * 4
        XCTAssertLessThan(p.bytes[flood], 200, "the flood lobe is filled beneath its curve")
        let ebb = (80 * p.width + 60) * 4
        XCTAssertEqual(p.bytes[ebb], 255, "the ebb lobe above its curve stays unfilled")
        XCTAssertEqual(p.bytes[ebb + 1], 255)
    }

    /// A tide held at 1 after one opening sample at 0, so the curve rides near the plot top and
    /// the shade beneath it is at full strength.
    private func flatTide(start: Date, end: Date, tz: TimeZone, days: [TimelineDay] = [],
                          extremes: [TideExtreme] = []) -> TimelineData {
        let count = Int(end.timeIntervalSince(start) / 600)
        let times = (0...count).map { start.addingTimeInterval(Double($0) * 600) }
        return TimelineData(tz: tz, anchor: start, today: start, start: start, end: end, days: days,
                            tidePoints: times.enumerated().map { TidePoint(time: $1, height: $0 == 0 ? 0 : 1) },
                            tideRates: times.map { TideRatePoint(time: $0, rate: 0) },
                            tideExtremes: extremes, currentPoints: [], currentEvents: [],
                            snapTimes: [], slackWindows: [])
    }

    /// RGBA bytes of a 1× render, row-major from the top.
    private func pixels(_ image: UIImage) throws -> (bytes: [UInt8], width: Int) {
        let cg = try XCTUnwrap(image.cgImage)
        var px = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: cg.width, height: cg.height,
                                          bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return (px, cg.width)
    }

    private func brightness(_ p: (bytes: [UInt8], width: Int), x: CGFloat, y: CGFloat) -> Int {
        let i = (Int(y) * p.width + Int(x)) * 4
        return Int(p.bytes[i]) + Int(p.bytes[i + 1]) + Int(p.bytes[i + 2])
    }

    /// Where sunset follows local midnight, the afternoon takes the daylight tint and the small
    /// hours the night band, rather than the civil day's sunset shading the whole day as night.
    @MainActor
    func testDaylightAndNightFollowTheSunWhereSunsetFollowsMidnight() throws {
        let (tz, days) = try lateSunsetDays()
        let start = days[0].start, end = try XCTUnwrap(days.last?.start)
        let lit = flatTide(start: start, end: end, tz: tz, days: days)
        let bare = flatTide(start: start, end: end, tz: tz)
        let before = start.addingTimeInterval(-86_400)
        let shaded = try pixels(XCTUnwrap(stripImage(lit, now: before)))
        let plain = try pixels(XCTUnwrap(stripImage(bare, now: before)))
        let y = TimelineGeo(data: lit).tideTop + 30
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        for d in days.dropFirst().dropLast() {
            let rise = try XCTUnwrap(d.sunrise), set = try XCTUnwrap(d.sunset)
            XCTAssertLessThan(set, rise, "\(d.start) sets before it rises: the fixture proves nothing")
            let afternoon = try XCTUnwrap(cal.date(bySettingHour: 15, minute: 0, second: 0, of: d.start))
            XCTAssertGreaterThan(brightness(shaded, x: lit.x(afternoon), y: y),
                                 brightness(plain, x: lit.x(afternoon), y: y),
                                 "\(d.start)'s afternoon is not tinted as daylight")
            let smallHours = set.addingTimeInterval(rise.timeIntervalSince(set) / 2)
            XCTAssertLessThan(brightness(shaded, x: lit.x(smallHours), y: y),
                              brightness(plain, x: lit.x(smallHours), y: y),
                              "\(d.start)'s small hours are not shaded as night")
        }
    }

    /// The daylight tint is `#A8CAE0` at 22% over the bare sea, where the curve's water carries
    /// no fill above datum: strong enough that a lit afternoon tells from the night beside it
    /// without the sky's bodies, faint enough that the sea still reads as sea.
    @MainActor
    func testTheDaylightTintIsTwentyTwoPercent() throws {
        let (tz, days) = try lateSunsetDays()
        let start = days[0].start, end = try XCTUnwrap(days.last?.start)
        let lit = flatTide(start: start, end: end, tz: tz, days: days)
        let bare = flatTide(start: start, end: end, tz: tz)
        let before = start.addingTimeInterval(-86_400)
        let shaded = try pixels(XCTUnwrap(stripImage(lit, now: before)))
        let plain = try pixels(XCTUnwrap(stripImage(bare, now: before)))
        // Inside the shade's full-strength top 35%, well under the curve.
        let y = TimelineGeo(data: lit).tideTop + 30
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let tint = [0xA8, 0xCA, 0xE0]
        for d in days.dropFirst().dropLast() {
            let afternoon = try XCTUnwrap(cal.date(bySettingHour: 15, minute: 0, second: 0, of: d.start))
            let over = rgb(shaded, x: lit.x(afternoon), y: y), under = rgb(plain, x: lit.x(afternoon), y: y)
            for c in 0..<3 {
                let alpha = Double(over[c] - under[c]) / Double(tint[c] - under[c])
                XCTAssert((0.195...0.245).contains(alpha),
                          "\(d.start)'s afternoon tint is \(alpha) in channel \(c), not 0.22")
            }
        }
    }

    /// The strip fills only below chart datum: no blue under a curve above datum, low amber
    /// between datum and a curve below it, and nothing at all when the water never reaches datum.
    @MainActor
    func testTheStripFillsOnlyBelowDatum() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(24 * 3600)
        let before = start.addingTimeInterval(-86_400)
        func tide(_ height: (Date) -> Double) -> TimelineData {
            let times = (0...Int(end.timeIntervalSince(start) / 600)).map { start.addingTimeInterval(Double($0) * 600) }
            return TimelineData(tz: tz, anchor: start, today: start, start: start, end: end, days: [],
                                tidePoints: times.map { TidePoint(time: $0, height: height($0)) },
                                tideRates: times.map { TideRatePoint(time: $0, rate: 0) },
                                tideExtremes: [], currentPoints: [], currentEvents: [],
                                snapTimes: [], slackWindows: [])
        }
        let morning = start.addingTimeInterval(6 * 3600 + 1000), evening = start.addingTimeInterval(18 * 3600 + 1000)

        // 1 m until midday, −1 m after it: datum sits mid-plot.
        let dips = tide { $0 < start.addingTimeInterval(12 * 3600) ? 1 : -1 }
        let geo = TimelineGeo(data: dips)
        let p = try pixels(XCTUnwrap(stripImage(dips, now: before)))
        let sea = rgb(p, x: dips.x(morning), y: 2)
        let above = rgb(p, x: dips.x(morning), y: geo.tideY(0.5))
        XCTAssert(zip(above, sea).allSatisfy { abs($0 - $1) <= 4 },
                  "the water above datum carries a fill: \(above) against the sea's \(sea)")
        let below = rgb(p, x: dips.x(evening), y: geo.tideY(-0.8))
        XCTAssertGreaterThan(below[0] - sea[0], 40, "no amber between datum and a curve below it: \(below)")
        XCTAssertGreaterThan(below[0] - below[2], 40, "the fill below datum is not amber: \(below)")

        // 2 m after an opening 1 m: the lowest water is above datum.
        let high = tide { $0 == start ? 1 : 2 }
        let highGeo = TimelineGeo(data: high)
        let q = try pixels(XCTUnwrap(stripImage(high, now: before)))
        let water = rgb(q, x: high.x(morning), y: highGeo.tideY(1.5))
        let bare = rgb(q, x: high.x(morning), y: 2)
        XCTAssert(zip(water, bare).allSatisfy { abs($0 - $1) <= 4 },
                  "water that never reaches datum carries a fill: \(water) against the sea's \(bare)")
    }

    private func rgb(_ p: (bytes: [UInt8], width: Int), x: CGFloat, y: CGFloat) -> [Int] {
        let i = (Int(y) * p.width + Int(x)) * 4
        return [Int(p.bytes[i]), Int(p.bytes[i + 1]), Int(p.bytes[i + 2])]
    }

    /// A turn an hour inside a loaded edge would have its label cut by it, so it draws nothing;
    /// two hours in, it draws whole.
    @MainActor
    func testATurnTooNearTheLoadedEdgeDrawsNoLabel() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(24 * 3600)
        let before = start.addingTimeInterval(-86_400)
        let none = try XCTUnwrap(stripImage(flatTide(start: start, end: end, tz: tz), now: before))
        for (hours, draws) in [(1.0, false), (2.0, true)] {
            for t in [start.addingTimeInterval(hours * 3600), end.addingTimeInterval(-hours * 3600)] {
                let turn = TideExtreme(time: t, height: 1, kind: .high)
                let one = try XCTUnwrap(stripImage(flatTide(start: start, end: end, tz: tz, extremes: [turn]),
                                                   now: before))
                let changed = differingFraction(one, none)
                if draws {
                    XCTAssertGreaterThan(changed, 0, "a turn \(hours) h inside the edge drew nothing")
                } else {
                    XCTAssertEqual(changed, 0, "a turn \(hours) h inside the edge drew a clipped label")
                }
            }
        }
    }

    /// A slack with no measured window, and every derived-gate slack, is still a mark with a time:
    /// a dot on the curve and a time in the row beneath it, on the strip and on the card.
    @MainActor
    func testASlackWithoutAWindowDrawsItsDotAndTime() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(24 * 3600)
        let slack = start.addingTimeInterval(12 * 3600)
        let before = start.addingTimeInterval(-86_400)
        for schematic in [false, true] {
            let plain = flatCurrent(start: start, end: end, tz: tz, slack: nil, schematic: schematic)
            let marked = flatCurrent(start: start, end: end, tz: tz, slack: slack, schematic: schematic)
            let geo = TimelineGeo(data: marked)
            let a = try XCTUnwrap(stripImage(plain, now: before)), b = try XCTUnwrap(stripImage(marked, now: before))
            let timeRow = Int(geo.timeY) - 8...Int(geo.timeY) + 8
            XCTAssertGreaterThan(try differing(a, b, rows: timeRow), 0, "schematic \(schematic): no time under the slack")
            let plot = Int(geo.curTop)...Int(geo.curBottom)
            XCTAssertGreaterThan(try differing(a, b, rows: plot), 0, "schematic \(schematic): no dot at the slack")
        }

        let now = start.addingTimeInterval(6 * 3600)
        let points = stride(from: now.addingTimeInterval(-StationCardGraph.backWindow),
                            through: now.addingTimeInterval(StationCardGraph.forwardWindow), by: 600)
            .map { StationCardGraph.Point(time: $0, value: 1) }
        for schematic in [false, true] {
            func card(_ slacks: [Date]) throws -> UIImage {
                let graph = StationCardGraph(points: points, extremes: [], now: now, includesZero: true, tz: tz,
                                             slacks: slacks, speedsAreSchematic: schematic)
                return try XCTUnwrap(ImageRenderer(content: graph.frame(width: 350, height: 96)
                    .background(SN.canvas)).uiImage)
            }
            let a = try card([]), b = try card([now.addingTimeInterval(3 * 3600)])
            XCTAssertGreaterThan(try differing(a, b, rows: 78...95), 0, "schematic \(schematic): no time under the card's slack")
            XCTAssertGreaterThan(try differing(a, b, rows: 0...77), 0, "schematic \(schematic): no dot at the card's slack")
        }
    }

    /// A windowless slack's dot is its mark, so near a loaded edge it draws like a short run's dot,
    /// while its time and a derived gate's dots still keep the edge margin (§12.3).
    @MainActor
    func testAWindowlessSlackDotDrawsToTheEdge() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(24 * 3600)
        let slack = start.addingTimeInterval(3600)
        let before = start.addingTimeInterval(-86_400)
        for schematic in [false, true] {
            let plain = flatCurrent(start: start, end: end, tz: tz, slack: nil, schematic: schematic)
            let marked = flatCurrent(start: start, end: end, tz: tz, slack: slack, schematic: schematic)
            XCTAssertFalse(marked.clearsLabelEdges(slack), "the fixture slack sits inside the edge margin")
            let geo = TimelineGeo(data: marked)
            let a = try XCTUnwrap(stripImage(plain, now: before)), b = try XCTUnwrap(stripImage(marked, now: before))
            let plot = try differing(a, b, rows: Int(geo.curTop)...Int(geo.curBottom))
            if schematic {
                XCTAssertEqual(plot, 0, "a derived gate's dot keeps the edge margin")
            } else {
                XCTAssertGreaterThan(plot, 0, "no dot at a windowless slack near the edge")
            }
            XCTAssertEqual(try differing(a, b, rows: Int(geo.timeY) - 8...Int(geo.timeY) + 8), 0,
                           "schematic \(schematic): its time keeps the edge margin")
        }
    }

    /// A card reading keeps its preferred side unless its value would leave the plot, where it hangs off the other side of its dot.
    func testACardReadingFlipsWhenItsSideWouldLeaveThePlot() {
        let plot: CGFloat = 108
        XCTAssertEqual(StationCardGraph.hangToward(dotY: 80, high: false, plotHeight: plot), -1, "a low hangs up, toward the middle")
        XCTAssertEqual(StationCardGraph.hangToward(dotY: 38, high: false, plotHeight: plot), -1, "a low with room above for its value keeps hanging up")
        XCTAssertEqual(StationCardGraph.hangToward(dotY: 37, high: false, plotHeight: plot), 1, "a low whose value would leave the top hangs down")
        XCTAssertEqual(StationCardGraph.hangToward(dotY: 20, high: true, plotHeight: plot), 1, "a high hangs down, toward the middle")
        XCTAssertEqual(StationCardGraph.hangToward(dotY: 70, high: true, plotHeight: plot), 1, "a high with room below for its value keeps hanging down")
        XCTAssertEqual(StationCardGraph.hangToward(dotY: 71, high: true, plotHeight: plot), -1, "a high whose value would reach the axis times hangs up")
    }

    /// A strip max's reading hangs below a crest and above a trough, so a
    /// relaxation extremum — the flow slackened without reversing, still
    /// flood or ebb by sign — hangs off the opposite side from the true
    /// maxima an hour either side of it instead of landing on their readings.
    func testAMaxReadingHangsBelowACrestAndAboveATrough() {
        XCTAssertEqual(maxHangToward(speed: 1.0, before: 0.8), 1, "a flood crest hangs down, toward the zero line")
        XCTAssertEqual(maxHangToward(speed: -1.1, before: -0.9), -1, "an ebb trough hangs up, toward the zero line")
        XCTAssertEqual(maxHangToward(speed: -0.85, before: -1.1), 1, "an ebb relaxation crest hangs down, off its neighbours' side")
        XCTAssertEqual(maxHangToward(speed: 0.3, before: 0.5), -1, "a flood relaxation trough hangs up, off its neighbours' side")
        XCTAssertEqual(maxHangToward(speed: 0.5, before: 0.5), 1, "a flat approach falls back to the flood side")
        XCTAssertEqual(maxHangToward(speed: -0.5, before: -0.5), -1, "a flat approach falls back to the ebb side")
    }

    /// The card's axis times stay 24pt in from each canvas edge and 48pt after the last time kept, in time order.
    func testCardAxisTimesKeepClearOfTheEdgesAndEachOther() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let at = { (px: Double) in t0.addingTimeInterval(px * 60) }
        let x = { (t: Date) in CGFloat(t.timeIntervalSince(t0) / 60) }
        let moments = ([200, 23, 130, 24, 71, 72, 100, 332, 333] as [Double]).map(at)
        XCTAssertEqual(StationCardGraph.thinAxisMoments(moments, x: x, width: 356),
                       ([24, 72, 130, 200, 332] as [Double]).map(at),
                       "130 is 30pt after a dropped time but 58pt after the last one kept")
    }

    /// On a rendered card, a low near the canvas top hangs its reading down, out of the identity rows
    /// the canvas starts under, and a high near the bottom hangs up, clear of the axis times. A turn
    /// too close to another, or to the edge, prints no time.
    @MainActor
    func testACardDrawsItsReadingsAndTimesInsideTheGraph() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let start = now.addingTimeInterval(-StationCardGraph.backWindow)
        let times = Array(stride(from: start, through: now.addingTimeInterval(StationCardGraph.forwardWindow), by: 600))
        // Flat at mid-height with one sample at each end of the range, so the domain is exactly -0.25…1.25.
        let points = times.enumerated().map { i, t in
            StationCardGraph.Point(time: t, value: i == 0 ? 0 : i == times.count - 1 ? 1 : 0.5)
        }
        // The list card's canvas: 3pt past the card each side, and below its 54pt identity inset.
        let width: CGFloat = 356, height: CGFloat = 114
        func at(_ px: CGFloat) -> Date { start.addingTimeInterval(StationCardGraph.window * Double(px / width)) }
        func turn(_ px: CGFloat, _ value: Double, high: Bool) -> StationCardGraph.Extreme {
            .init(time: at(px), value: value, valueText: "8.8", spokenText: "8.8 ft",
                  timeText: cardTime(at(px), tz), high: high)
        }
        func card(_ extremes: [StationCardGraph.Extreme], readings: Bool) throws -> UIImage {
            var graph = StationCardGraph(points: points, extremes: extremes, now: now)
            graph.showsReadings = readings
            graph.showsNow = false
            return try XCTUnwrap(ImageRenderer(content: graph.frame(width: width, height: height)
                .background(SN.canvas)).uiImage)
        }
        func reading(_ extremes: [StationCardGraph.Extreme], rows: ClosedRange<Int>) throws -> Int {
            try differing(card(extremes, readings: false), card(extremes, readings: true), rows: rows)
        }

        // On the 108pt plot, 0.8 sits 32pt down and 0.2 sits 76pt down; each dot and its halo span ±5.
        let low = [turn(120, 0.8, high: false)], high = [turn(240, 0.2, high: true)]
        XCTAssertEqual(try reading(low, rows: 0...26), 0, "a low near the top drew its reading above its dot")
        XCTAssertGreaterThan(try reading(low, rows: 38...80), 0, "the low's reading hangs below its dot")
        XCTAssertEqual(try reading(high, rows: 82...113), 0, "a high near the bottom drew its reading into the axis times")
        XCTAssertGreaterThan(try reading(high, rows: 30...70), 0, "the high's reading hangs above its dot")

        let axis = Int(height) - 18...Int(height) - 2
        let first = turn(150, 0.5, high: true)
        XCTAssertEqual(try differing(card([first], readings: false),
                                     card([first, turn(190, 0.5, high: false)], readings: false), rows: axis), 0,
                       "a turn 40pt after another printed its time over the first")
        XCTAssertGreaterThan(try differing(card([first], readings: false),
                                           card([first, turn(200, 0.5, high: false)], readings: false), rows: axis), 0,
                             "a turn 50pt after another prints its own time")
        XCTAssertEqual(try differing(card([], readings: false),
                                     card([turn(width - 22, 0.5, high: true)], readings: false), rows: axis), 0,
                       "a turn 22pt from the canvas edge printed a time the card clips")
    }

    @MainActor
    func testSlackAxisTimesUseTheGreenOfSlack() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(24 * 3600)
        let slack = start.addingTimeInterval(12 * 3600)
        for windows in [[], [(slack: slack, start: slack.addingTimeInterval(-3600), end: slack.addingTimeInterval(3600))]] {
            let data = flatCurrent(start: start, end: end, tz: .gmt, slack: slack, schematic: false, windows: windows)
            let geo = TimelineGeo(data: data)
            let p = try pixels(XCTUnwrap(stripImage(data, now: start.addingTimeInterval(-3600))))
            let hasGreen = (Int(geo.timeY) - 8...Int(geo.timeY) + 8).contains { y in
                (0..<p.width).contains { x in
                    let i = (y * p.width + x) * 4
                    return Int(p.bytes[i + 1]) > Int(p.bytes[i]) + 25 && Int(p.bytes[i + 1]) > Int(p.bytes[i + 2]) + 25
                }
            }
            XCTAssertTrue(hasGreen, "the slack time is not green; window count: \(windows.count)")
        }
    }

    @MainActor
    func testAContinuousWindowWithAVisibleOpeningNamesItsSlacks() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let h = { (hours: Double) in start.addingTimeInterval(hours * 3600) }
        let slacks = [h(6), h(12)]
        let data = TimelineData(tz: .gmt, anchor: start, today: start, start: start, end: h(24), days: [],
                                tidePoints: [], tideRates: [], tideExtremes: [],
                                currentPoints: [CurrentPoint(time: start, speed: 0), CurrentPoint(time: h(24), speed: 0)],
                                currentEvents: slacks.map { CurrentEvent(time: $0, speed: 0, kind: .slack) }, snapTimes: [],
                                slackWindows: slacks.map { (slack: $0, start: h(3), end: h(15)) })
        XCTAssertTrue(data.clearsLabelEdges(h(3)))
        XCTAssertEqual(data.slackAxisTimes, slacks)
        XCTAssertEqual(StationCardGraph.axisMoments(data.windowRuns, cores: [], slacks: slacks, pointsPerHour: 14), slacks)
    }

    @MainActor
    func testAContinuousSlackWindowKeepsItsSlackTimes() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(24 * 3600)
        let slacks = [6.0, 12, 18].map { start.addingTimeInterval($0 * 3600) }
        let points = stride(from: 0.0, through: 24 * 3600, by: 600).map {
            CurrentPoint(time: start.addingTimeInterval($0), speed: 0.2)
        }
        func data(_ events: [CurrentEvent]) -> TimelineData {
            TimelineData(tz: .gmt, anchor: start, today: start, start: start, end: end, days: [],
                         tidePoints: [], tideRates: [], tideExtremes: [], currentPoints: points,
                         currentEvents: events, snapTimes: [],
                         slackWindows: slacks.map { (slack: $0, start: start, end: end) })
        }
        let marked = data(slacks.map { CurrentEvent(time: $0, speed: 0, kind: .slack) })
        XCTAssertEqual(marked.slackAxisTimes, slacks)
        let geo = TimelineGeo(data: marked)
        let before = start.addingTimeInterval(-3600)
        XCTAssertGreaterThan(try differing(XCTUnwrap(stripImage(data([]), now: before)),
                                          XCTUnwrap(stripImage(marked, now: before)),
                                          rows: Int(geo.timeY) - 8...Int(geo.timeY) + 8), 0,
                             "a continuous window lost every visible time")
    }

    @MainActor
    func testSlackWindowOpeningDrawsAnAxisTime() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(24 * 3600)
        let slack = start.addingTimeInterval(12 * 3600)
        let plain = flatCurrent(start: start, end: end, tz: .gmt, slack: nil, schematic: false)
        let marked = flatCurrent(start: start, end: end, tz: .gmt, slack: slack, schematic: false,
                                 windows: [(slack: slack, start: slack.addingTimeInterval(-3600), end: slack.addingTimeInterval(3600))])
        let geo = TimelineGeo(data: marked)
        let before = start.addingTimeInterval(-3600)
        XCTAssertFalse(marked.slackAxisTimes.isEmpty)
        XCTAssertGreaterThan(try differing(XCTUnwrap(stripImage(plain, now: before)),
                                          XCTUnwrap(stripImage(marked, now: before)),
                                          rows: Int(geo.timeY) - 8...Int(geo.timeY) + 8), 0)
    }

    @MainActor
    func testPeakTimesDrawBelowSlackEvenWhenTheyAreClose() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let h = { (hours: Double) in start.addingTimeInterval(hours * 3600) }
        let slack = CurrentEvent(time: h(12), speed: 0, kind: .slack)
        func data(_ events: [CurrentEvent]) -> TimelineData {
            TimelineData(tz: .gmt, anchor: start, today: start, start: start, end: h(24), days: [],
                         tidePoints: [], tideRates: [], tideExtremes: [],
                         currentPoints: [CurrentPoint(time: start, speed: 1), CurrentPoint(time: h(24), speed: 1)],
                         currentEvents: events, snapTimes: [], slackWindows: [])
        }
        let plain = data([slack]), geo = TimelineGeo(data: plain)
        let before = h(-1)
        let a = try XCTUnwrap(stripImage(plain, now: before))
        for kind in [CurrentEventKind.maxFlood, .maxEbb] {
            let marked = data([slack, CurrentEvent(time: h(13), speed: 1, kind: kind)])
            let b = try XCTUnwrap(stripImage(marked, now: before))
            XCTAssertGreaterThan(try differing(a, b, rows: Int(geo.timeY) + 12...Int(geo.timeY) + 28), 0,
                                 "the peak time needs its own row even an hour from slack")
            XCTAssertEqual(try differing(a, b, rows: Int(geo.timeY) - 8...Int(geo.timeY) + 8), 0,
                           "adding a peak must preserve the slack time")
        }
    }

    private func flatCurrent(start: Date, end: Date, tz: TimeZone, slack: Date?, schematic: Bool,
                             windows: [(slack: Date, start: Date, end: Date)] = []) -> TimelineData {
        let count = Int(end.timeIntervalSince(start) / 600)
        let times = (0...count).map { start.addingTimeInterval(Double($0) * 600) }
        return TimelineData(tz: tz, anchor: start, today: start, start: start, end: end, days: [],
                            tidePoints: [], tideRates: [], tideExtremes: [],
                            currentPoints: times.map { CurrentPoint(time: $0, speed: 1) },
                            currentEvents: slack.map { [CurrentEvent(time: $0, speed: 0, kind: .slack)] } ?? [],
                            snapTimes: [], slackWindows: windows, speedsAreSchematic: schematic)
    }

    /// Pixels that differ between two same-size renders, within a band of rows.
    private func differing(_ a: UIImage, _ b: UIImage, rows: ClosedRange<Int>) throws -> Int {
        let pa = try pixels(a), pb = try pixels(b)
        var count = 0
        for y in rows where y >= 0 && (y + 1) * pa.width * 4 <= pa.bytes.count {
            for x in 0..<pa.width {
                let i = (y * pa.width + x) * 4
                if (0..<3).contains(where: { abs(Int(pa.bytes[i + $0]) - Int(pb.bytes[i + $0])) > 4 }) { count += 1 }
            }
        }
        return count
    }

    private var friday: TideStationRecord {
        TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!
    }
    private var avonmouth: TideStationRecord {
        TideStationRecord.all.first { $0.name == "Avonmouth" }!
    }
    private var boston: TideStationRecord {
        TideStationRecord.all.first { $0.name == "Boston" }!
    }

    @MainActor
    private func attach(_ image: UIImage, _ name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// #95: the tide fill carries |dh/dt| on an absolute ramp. The strip has to
    /// keep drawing — the rate stops replaced a fixed gradient, and an empty
    /// stops array renders a hollow track. Two stations because one picture
    /// proves nothing: Friday Harbor sits low on the ramp and Avonmouth
    /// (Severn, 13.7 ft/hr peak) near the top, so between them they exercise
    /// both ends of the ramp rather than one colour twice.
    ///
    @MainActor
    func testTideRateRampDrawsOnQuietAndExtremeStations() throws {
        let now = appNow()
        let floor = blankStripInk(tz: friday.tz, now: now)
        XCTAssertLessThan(floor, drawnStripInk,
                          "day chrome alone must stay under the threshold — \(floor)")

        for station in [friday, avonmouth] {
            let tl = TimelineData.build(tide: station, current: nil, now: now,
                                        anchor: todayLocal(station.tz))
            let image = try XCTUnwrap(stripImage(tl))
            let ink = inkFraction(image)
            XCTAssertGreaterThan(ink, drawnStripInk,
                                 "\(station.name)'s strip drew nothing — ink \(ink)")
            attach(image, "tide-ramp-\(station.id)")
        }
    }

    /// A station 4,000 km from the Salish Sea draws a real curve from bundled
    /// NOAA harmonics — no download, no signal, the same strip Friday Harbor
    /// gets. Boston's own identity (its "MA" region line, its New York zone,
    /// its metres of range) is pinned in NationalScaleTests; what this adds is
    /// that the far end of the bundle reaches the chart.
    ///
    @MainActor
    func testUsEastCoastStationDrawsItsCurve() throws {
        let now = appNow()
        let tl = TimelineData.build(tide: boston, current: nil, now: now,
                                    anchor: todayLocal(boston.tz))
        let scheduled = tl.tideExtremes.filter { tl.scheduleRange.contains($0.time) }
        XCTAssertGreaterThanOrEqual(scheduled.count, 3,
                                    "a week of Boston tide has turns to schedule")
        let floor = blankStripInk(tz: boston.tz, now: now)
        XCTAssertLessThan(floor, drawnStripInk,
                          "day chrome alone must stay under the threshold — \(floor)")
        let image = try XCTUnwrap(stripImage(tl))
        let ink = inkFraction(image)
        XCTAssertGreaterThan(ink, drawnStripInk, "the Boston strip drew nothing — ink \(ink)")
        attach(image, "us-east-coast-strip")
    }

    /// #38: the derived-gate strip. A derived gate is the one path where every
    /// slack takes the windowless branch — no `slackWindows` by design, so each
    /// event draws a dropline and a gutter time, never a band — and its curve is
    /// a schematic ±1 shape rather than a velocity.
    ///
    /// Malibu Rapids over a synthetic Point Atkinson fit: a reference port's
    /// model is fitted on-device and no unit test can fit one, so the port is
    /// built here the way the other derived-gate tests build theirs. Any
    /// plausible harmonic shape gives SlackwaterKit real highs and lows to lag
    /// into slacks, which is all a gate reads from its reference.
    ///
    /// A thin ±1 shape with fill
    /// only in its positive half, and no speed thread.
    @MainActor
    func testDerivedGateDrawsItsSchematicStrip() throws {
        let port = TideStationRecord(
            id: "chs-point-atkinson", name: "Point Atkinson", region: "West Vancouver",
            aliases: [], latitude: 49.337, longitude: -123.254,
            timezone: "America/Vancouver", chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0),
                           .init(name: "K1", amplitude: 0.9, phase: 90)])
        let gate = try XCTUnwrap(ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" })
        let record = DerivedGateRecord(gate: gate, port: port)
        let now = appNow()
        let tl = TimelineData.build(gate: record, now: now, anchor: todayLocal(gate.tz))

        XCTAssert(tl.speedsAreSchematic, "a derived gate's curve is a shape, not a velocity")
        XCTAssert(tl.slackWindows.isEmpty,
                  "a 0.5 kn window measured off a schematic shape would be fiction")
        XCTAssertFalse(tl.currentEvents.isEmpty, "the gate has slack events to draw")

        let floor = blankStripInk(tz: gate.tz, now: now)
        XCTAssertLessThan(floor, drawnStripInk,
                          "day chrome alone must stay under the threshold — \(floor)")
        let image = try XCTUnwrap(stripImage(tl))
        let ink = inkFraction(image)
        XCTAssertGreaterThan(ink, drawnStripInk, "the derived-gate strip drew nothing — ink \(ink)")
        attach(image, "derived-gate-strip")
    }

    /// The online (fit-reject) gates draw FETCHED CHS samples rather than an
    /// on-device fit. Those are real velocities, just downloaded — so unlike
    /// the derived gate their slacks carry windows, computed off the same
    /// series the strip draws, and the strip has to render the bands.
    ///
    /// The window is built here rather than read off disk: `TestSeeds.swift`
    /// writes one through private functions behind `#if DEBUG` that
    /// `@testable import` cannot reach, and what the strip reads is the
    /// `ChsOnlineWindow` value itself. Same shape the seed writes — an M2-ish
    /// sine at the 15-minute official-sample cadence, spanning exactly
    /// `Timeline.window(anchor:)`.
    ///
    @MainActor
    func testOnlineGateDrawsItsFetchedStrip() throws {
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == "chs-sechelt-rapids" })
        let now = appNow()
        let today = todayLocal(gate.tz)
        let span = Timeline.window(anchor: today)
        let period = 12.42 * 3600.0   // M2 tidal period, seconds
        var times: [Double] = [], speeds: [Double] = []
        var t = span.start
        while t <= span.end {
            times.append(t.timeIntervalSince1970)
            speeds.append(2.0 * sin(2 * .pi * t.timeIntervalSince(span.start) / period))
            t = t.addingTimeInterval(900)
        }
        let window = ChsOnlineWindow(
            stationID: gate.id, iwlsName: "\(gate.name) (seeded)", timezone: gate.timezone,
            fetchedAt: now, start: span.start, end: span.end,
            floodDirection: 0, ebbDirection: 180, times: times, speeds: speeds)

        let tl = TimelineData.build(onlinePoints: window.points, tz: gate.tz,
                                    lat: gate.latitude, lon: gate.longitude,
                                    now: now, anchor: today)
        XCTAssert(tl.hasCurrent && !tl.hasTide, "an online gate's strip is current-only")
        XCTAssertFalse(tl.slackWindows.isEmpty,
                       "online gates draw fetched speeds, so their slacks carry windows")

        let floor = blankStripInk(tz: gate.tz, now: now)
        XCTAssertLessThan(floor, drawnStripInk,
                          "day chrome alone must stay under the threshold — \(floor)")
        let image = try XCTUnwrap(stripImage(tl))
        let ink = inkFraction(image)
        XCTAssertGreaterThan(ink, drawnStripInk, "the online-gate strip drew nothing — ink \(ink)")
        attach(image, "online-gate-strip")
    }
}
