// Slackwater — GPL v3. The timeline strip actually draws, for each of the
// three curve shapes the app has: a tide track on the rate ramp, a derived
// gate's schematic shape, and an online gate's fetched velocities.
//
// Ink coverage, because nothing inside the strip is an accessibility element —
// it is one `Canvas` — so "did it draw" is the only question a test can put to
// it, and it is the question that matters: every readout, label and schedule
// row can be right while the chart renders nothing (the texture-cap blank, the
// empty gradient-stops array). Each threshold is measured against the same
// window with no track on it, and both numbers are recorded here.
import XCTest
import SwiftUI
@testable import Slackwater
import TideEngine

final class RenderedStripTests: XCTestCase {

    @MainActor
    func testSlackRunSeparatesOnlyFromTheCurve() throws {
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
                                         nowX: 0, width: size.width, height: size.height)
                CurveDrawing.runs(context, [run], nowX: 0, width: size.width, height: size.height)
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
        let end = (12 * image.width + 63) * 4
        XCTAssertGreaterThan(pixels[end], 200, "the end gap must preserve the layer below the curve")
        XCTAssertGreaterThan(pixels[end + 1], 200, "the end gap must preserve the layer below the curve")
        XCTAssertGreaterThan(pixels[end + 2], 200, "the end gap must preserve the layer below the curve")
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
    /// Measured at 1× on the 396pt canvas: Friday Harbor 0.115, Avonmouth
    /// 0.102, against a no-track floor of 0.028 (`drawnStripInk`).
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
    /// Measured at 1× on the 396pt canvas: Boston 0.097, against a no-track
    /// floor of 0.028.
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
    /// plausible harmonic shape gives TideEngine real highs and lows to lag
    /// into slacks, which is all a gate reads from its reference.
    ///
    /// Measured at 1× on the 396pt canvas: 0.090 against a no-track floor of
    /// 0.028 — a thin ±1 shape carries no fill under it, so it clears the
    /// floor by less than any tide curve does.
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
    /// Measured at 1× on the 396pt canvas: 0.075 against a no-track floor of
    /// 0.028 — the lowest drawn shape the app has, and the one that sets
    /// `drawnStripInk`. A fetched curve spends the window near zero, so it
    /// occupies less of the plot than a tide sweeping it top to bottom.
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
