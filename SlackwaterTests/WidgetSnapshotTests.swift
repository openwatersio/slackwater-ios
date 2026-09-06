// Slackwater — GPL v3. WidgetSnapshot: next event, slack window, and a
// render-ready day curve — deterministic given (station, now).
import XCTest
import SwiftUI
@testable import Slackwater
import TideEngine

final class WidgetSnapshotTests: XCTestCase {
    var friday: WidgetStation { WidgetStationLoader.load(id: TideStationRecord.fridayHarborID)! }
    var current: WidgetStation {
        WidgetStationLoader.load(id: "current:" + CurrentStationRecord.all.first!.id)!
    }

    /// A synthetic semidiurnal derived gate (M2 only, ~12h25m period) — same
    /// construction as DerivedGateTests, so its slacks are analytic and its
    /// timing is deterministic given a fixed epoch.
    func derivedGate(tz: TimeZone) -> WidgetStation {
        let reference = Station(constituents: [HarmonicConstituent(name: "M2", amplitude: 1.5, phase: 0)],
                                offset: 3.0)
        let gate = DerivedSlackStation(reference: reference, hwLagMinutes: 25, lwLagMinutes: 35)
        return .derived(gate, tz: tz, name: "Test Gate")
    }

    func testTideNextEventIsFuture() {
        let now = Date()
        let s = WidgetSnapshot.build(friday, now: now)
        XCTAssertNotNil(s.next)
        XCTAssert(s.next!.time > now)
        XCTAssert(s.next!.label.hasPrefix("High") || s.next!.label.hasPrefix("Low"))
    }

    func testCurrentLocationSnapshotNamesResolvedStationHonestly() {
        let s = WidgetSnapshot.build(friday, now: Date(), stationNamePrefix: "Current Location")
        XCTAssertEqual(s.stationName, "Current Location · Friday Harbor")
    }

    func testTideSnapshotCarriesNextHighAndLow() throws {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let s = WidgetSnapshot.build(friday, now: now)

        let high = try XCTUnwrap(s.nextHigh)
        let low = try XCTUnwrap(s.nextLow)
        XCTAssertGreaterThan(high.time, now)
        XCTAssertGreaterThan(low.time, now)
        XCTAssertTrue(high.label.hasPrefix("High "))
        XCTAssertTrue(low.label.hasPrefix("Low "))
    }

    func testTideSnapshotCarriesScrubberMovement() {
        let station = Station(
            constituents: [HarmonicConstituent(name: "M2", amplitude: 5, phase: 0)],
            offset: 6)
        let tide = WidgetStation.tide(station, tz: TimeZone(identifier: "UTC")!,
                                      name: "Fast Tide")
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let s = WidgetSnapshot.build(tide, now: now)

        XCTAssertFalse(s.tideMovements.isEmpty)
        XCTAssertNotNil(s.tideRate)
        XCTAssert(s.tideMovements.allSatisfy { (0...1).contains($0.fraction) })
    }

    /// H2(4): the widget used to hardcode `" %.1f m"` regardless of the
    /// app's own Settings choice, so a metric-only label shipped to every
    /// imperial user. Setting imperial explicitly (rather than relying on
    /// the unset default, which is already imperial) is the test that
    /// actually distinguishes the fix from the old hardcoded string — that
    /// one always ended in "m", imperial or not.
    func testTideLabelRespectsImperialUnits() {
        let saved = AppGroup.defaults.object(forKey: unitsKey)
        defer {
            if let saved { AppGroup.defaults.set(saved, forKey: unitsKey) }
            else { AppGroup.defaults.removeObject(forKey: unitsKey) }
        }
        AppGroup.defaults.set("imperial", forKey: unitsKey)

        let s = WidgetSnapshot.build(friday, now: Date())
        let label = try! XCTUnwrap(s.next).label
        XCTAssert(label.hasSuffix("ft"), "expected an imperial label, got \(label)")
        XCTAssertFalse(label.hasSuffix("m"), "expected an imperial label, got \(label)")
    }

    func testCurrentNextEventAndWindow() {
        let s = WidgetSnapshot.build(current, now: Date())
        XCTAssertNotNil(s.next)
        // A slack inside the sampled day gets its 0.5 kn window attached.
        if s.next!.label == "Slack" { XCTAssertNotNil(s.window) }
    }

    func testCurrentSnapshotPreservesMiniScrubberState() {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let s = WidgetSnapshot.build(current, now: now)

        XCTAssertEqual(s.curveKind, .current)
        XCTAssertEqual(s.threshold, slackThresholdKn)
        XCTAssertLessThan(s.sparkline.min()!, 0)
        XCTAssertGreaterThan(s.sparkline.max()!, 0)
        XCTAssertFalse(s.state.isEmpty)
        XCTAssertFalse(s.value.isEmpty)
    }

    /// The widget IS the list card — no second drawing of the curve.
    func testMediumWidgetIsTheCardNotASecondDrawing() throws {
        let source = try repoSource("Slackwater/DayCurveContentView.swift")

        XCTAssert(source.contains("StationCard(name: card.name"))
        XCTAssert(source.contains("ConditionsItem(reading: card.reading)"))
        XCTAssertFalse(source.contains("Canvas {"))
        XCTAssertFalse(source.contains("sparkline"))
    }

    func testWidgetCurrentColourUsesTheAbsoluteSpeedRamp() {
        XCTAssertEqual(widgetSpeedRampT(0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(widgetSpeedRampT(3), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(widgetSpeedRampT(8), 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(widgetSpeedRampT(12), 1, accuracy: 1e-9)
    }

    /// The record/instant among `records` whose card graph carries the
    /// longest slack window near `now` — a weak current sits under
    /// threshold far longer than a spring ebb, and the render below wants
    /// a stroke long enough to clear the pixel-count floor, not a blip a
    /// couple of samples wide. Falls back a day ahead for any record with
    /// no window in the next 25 hours.
    private func widestWindowCard(
        among records: [CurrentStationRecord], near now: Date
    ) -> (record: CurrentStationRecord, now: Date, graph: StationCardGraph)? {
        var best: (CurrentStationRecord, Date, StationCardGraph, TimeInterval)?
        for r in records {
            var t = now
            var g = r.cardGraph(at: t, unit: "kn")
            if g.windows.isEmpty,
               let w = r.cardGraph(at: now.addingTimeInterval(86_400), unit: "kn").windows.first {
                t = w.start
                g = r.cardGraph(at: t, unit: "kn")
            }
            guard let w = g.windows.first(where: { $0.contains(t) }) ?? g.windows.first else { continue }
            let duration = w.end.timeIntervalSince(w.start)
            if best == nil || duration > best!.3 { best = (r, t, g, duration) }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }

    /// The medium widget IS the card: a bundled current station's
    /// `WidgetCard` rendered through `DayCurveContentView` — name, reading
    /// with set, curve with dots and times, no second drawing. Rendered at
    /// both live medium-widget sizes: 338×158 (older phones) and 364×170
    /// (iPhone 15 Pro and later). No extra padding — `containerBackground`
    /// fills the family with no inset, so this frame IS the widget. `now`
    /// is a fixed epoch, not `Date()` — deterministic, not a flake.
    @MainActor
    func testMediumWidgetRendersTheStationCard() throws {
        let (record, now, graph) = try XCTUnwrap(widestWindowCard(
            among: Array(CurrentStationRecord.all.prefix(30)),
            near: Date(timeIntervalSince1970: 1_755_800_000)))
        let card = WidgetCard.build(.current(record, station: record.engineStation), now: now)

        func render(_ width: CGFloat, _ height: CGFloat, name: String) throws -> UIImage {
            // SN.canvas: the widget's real containerBackground (the list's
            // ground) — the card paints its translucent SN.cardFill over it.
            let renderer = ImageRenderer(content: DayCurveContentView(card: card)
                .frame(width: width, height: height)
                .background(SN.canvas))
            let image = try XCTUnwrap(renderer.uiImage)
            let png = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(png.count, 1_000)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            return image
        }

        _ = try render(338, 158, name: "widget-medium-158")
        let image170 = try render(364, 170, name: "widget-medium-170")

        if !graph.windows.isEmpty {
            let cg = try XCTUnwrap(image170.cgImage)
            let width = cg.width, height = cg.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            CIContext().render(CIImage(cgImage: cg), toBitmap: &pixels,
                               rowBytes: width * 4,
                               bounds: CGRect(x: 0, y: 0, width: width, height: height),
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            // SN.go == 0x88B868, ±24/channel.
            let goInk = (0..<height).reduce(into: 0) { count, y in
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    if abs(Int(pixels[i]) - 0x88) <= 24, abs(Int(pixels[i + 1]) - 0xB8) <= 24,
                       abs(Int(pixels[i + 2]) - 0x68) <= 24 { count += 1 }
                }
            }
            XCTAssertGreaterThan(goInk, 100, "expected go-coloured slack window ink")
        }
    }

    /// §15.5: the small widget is the card's reading over its own curve —
    /// name, hero with its arrow, the curve with dots and labels. Rendered at
    /// both live small-widget sizes (155² older phones, 170² iPhone 15 Pro
    /// and later) for a tide, a current and a derived gate; the frame IS the
    /// widget, as in the medium test above. Fixed epoch, not `Date()`.
    @MainActor
    func testSmallWidgetRendersTheCompactCard() throws {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let tideRecord = TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!
        let tide = WidgetCard.build(.tide(tideRecord, station: tideRecord.engineStation), now: now)
        let currentRecord = CurrentStationRecord.all.first!
        let current = WidgetCard.build(.current(currentRecord, station: currentRecord.engineStation), now: now)
        let gateInfo = try XCTUnwrap(ChsGateInfo.all.first)
        let port = try XCTUnwrap(ChsStationInfo.all.first { $0.id == gateInfo.reference })
        let model = ChsModel(
            stationID: port.id, iwlsID: "iwls-test", iwlsName: port.name,
            fittedAt: .now, fitStartMs: 0, fitEndMs: 1, offset: 1, rms: 0,
            constituents: [.init(name: "M2", amplitude: 1, phase: 0)])
        let gate = WidgetCard.build(.derived(DerivedGateRecord(gate: gateInfo, port: port.record(with: model))), now: now)

        for (card, kind) in [(tide, "tide"), (current, "current"), (gate, "gate")] {
            for side: CGFloat in [155, 170] {
                let renderer = ImageRenderer(content: NextEventContentView(card: card)
                    .frame(width: side, height: side)
                    .background(SN.canvas))
                let image = try XCTUnwrap(renderer.uiImage)
                let png = try XCTUnwrap(image.pngData())
                XCTAssertGreaterThan(png.count, 1_000)
                let attachment = XCTAttachment(image: image)
                attachment.name = "widget-small-\(kind)-\(Int(side))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        XCTAssertNotNil(tide.graph)
        XCTAssertNotNil(current.graph)
        XCTAssertNil(gate.graph)
        XCTAssertNotNil(gate.nextSlack)
    }

    /// The fastest current in the first sixty records, so the speed thread
    /// has something to colour: `testMediumWidgetRendersTheStationCard`
    /// picks the longest slack window, which is a station that never
    /// leaves green. An attachment to look at, not a pixel assertion.
    @MainActor
    func testMediumWidgetRendersAFastCurrentCard() throws {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let fastest = try XCTUnwrap(Array(CurrentStationRecord.all.prefix(60)).max { a, b in
            let peak = { (r: CurrentStationRecord) in
                r.cardGraph(at: now, unit: "kn").points.map { abs($0.value) }.max() ?? 0
            }
            return peak(a) < peak(b)
        })
        let card = WidgetCard.build(.current(fastest, station: fastest.engineStation), now: now)
        let renderer = ImageRenderer(content: DayCurveContentView(card: card)
            .frame(width: 364, height: 170)
            .background(SN.canvas))
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "widget-current-fast"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1_000)
    }

    /// The tide card, both ways the datum fill can go: a station whose lows
    /// reach under chart datum (amber below the dashed rule) and one that
    /// sits well above it (the fill fades out at its lowest trough, no
    /// rule). Attachments to look at; the pixel floor only says the curve
    /// drew at all. Fixed epoch, not `Date()`.
    @MainActor
    func testMediumWidgetRendersTheTideCard() throws {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let records = Array(TideStationRecord.all.prefix(60))
        func lowest(_ r: TideStationRecord) -> Double {
            r.cardGraph(at: now, imperial: false).points.map(\.value).min() ?? .infinity
        }
        let underDatum = try XCTUnwrap(records.first { lowest($0) < -0.1 }, "no station dips under datum")
        let aboveDatum = try XCTUnwrap(records.first { lowest($0) > 0.5 }, "no station stays clear of datum")
        for (record, name) in [(underDatum, "widget-tide-under-datum"), (aboveDatum, "widget-tide-above-datum")] {
            let card = WidgetCard.build(.tide(record, station: record.engineStation), now: now)
            let renderer = ImageRenderer(content: DayCurveContentView(card: card)
                .frame(width: 364, height: 170)
                .background(SN.canvas))
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1_000)
        }
    }

    /// §15.3: inside a slack window the widget's reading counts down to the
    /// window's close instead of showing a speed. Fixed epoch, not `Date()`
    /// — deterministic, not a flake.
    func testWidgetCardCountsDownInsideAWindow() throws {
        let record = CurrentStationRecord.all.first!
        let epoch = Date(timeIntervalSince1970: 1_755_800_000)
        var graph = record.cardGraph(at: epoch, unit: "kn")
        if graph.windows.isEmpty {
            graph = record.cardGraph(at: epoch.addingTimeInterval(86_400), unit: "kn")
        }
        let window = try XCTUnwrap(graph.windows.first)
        // One hour before the window closes: always under two hours
        // remaining regardless of how wide the fixture window itself is.
        let now = window.end.addingTimeInterval(-3_600)
        guard now >= window.start else {
            throw XCTSkip("fixture window is under an hour wide")
        }

        let card = WidgetCard.build(.current(record, station: record.engineStation), now: now)
        let end = try XCTUnwrap(card.countdownEnd, "expected a card counting down")
        if case .current(_, _, _, _, let inWindow) = card.reading {
            XCTAssertTrue(inWindow)
        } else {
            XCTFail("expected a .current reading")
        }
        // Sub-second tolerance: `end` comes from a graph re-sampled at
        // `now`, `window` from one sampled at the earlier anchor used to
        // find it — both interpolate the same crossing off a 10-min grid
        // offset by the shift between the two anchors.
        XCTAssertEqual(end.timeIntervalSince1970, window.end.timeIntervalSince1970, accuracy: 1.0)
    }

    /// No "> 2 hrs" state (user ruling): more than two hours before a
    /// window closes, the widget's corner shows nothing at all — the
    /// reading alone says Slack.
    func testWidgetCardHasNoCountdownBeyondTwoHours() throws {
        let epoch = Date(timeIntervalSince1970: 1_755_800_000)
        var found: (CurrentStationRecord, WindowRun)?
        outer: for record in CurrentStationRecord.all {
            for anchor in [epoch, epoch.addingTimeInterval(86_400)] {
                let graph = record.cardGraph(at: anchor, unit: "kn")
                if let w = graph.windows.first(where: { $0.end.timeIntervalSince($0.start) > 3 * 3_600 }) {
                    found = (record, w)
                    break outer
                }
            }
        }
        guard let (record, window) = found else {
            throw XCTSkip("no bundled window over three hours wide")
        }
        let now = window.end.addingTimeInterval(-3 * 3_600)
        let card = WidgetCard.build(.current(record, station: record.engineStation), now: now)
        XCTAssertNil(card.countdownEnd)
    }

    /// A widget explicitly configured to a CHS tide port builds that
    /// station's own card, not the current-location fallback — the data-path
    /// half of the widget's Station-picker bug: a chosen station must resolve
    /// to itself and carry no location mark.
    func testChosenChsTidePortBuildsItsOwnWidgetCard() throws {
        let id = "chs-narvaez-bay"
        guard ChsModelStore.load(id) == nil else {
            throw XCTSkip("\(id) already has a fitted model on this device")
        }
        let info = try XCTUnwrap(ChsStationInfo.all.first { $0.id == id })
        let model = ChsModel(
            stationID: id, iwlsID: "iwls-test", iwlsName: info.name,
            fittedAt: .now, fitStartMs: 0, fitEndMs: 1,
            offset: 1, rms: 0,
            constituents: [.init(name: "M2", amplitude: 1, phase: 0)])
        try ChsModelStore.save(model)
        defer { try? FileManager.default.removeItem(at: ChsModelStore.url(id)) }

        let record = try XCTUnwrap(WidgetStationLoader.loadRecord(id: id))
        guard case .tide = record else {
            return XCTFail("expected a .tide record for a CHS tide port")
        }
        let card = WidgetCard.build(record, now: Date(timeIntervalSince1970: 1_755_800_000))
        XCTAssertEqual(card.name, info.name)
        XCTAssertFalse(card.locationMark)
        XCTAssertNotNil(card.graph)
        guard case .tide = card.reading else {
            return XCTFail("expected a .tide reading")
        }
        XCTAssertEqual(WidgetStationLoader.resolvedStationID(id), id,
                       "a concrete choice must never resolve to the current location")
    }

    func testSparklineShape() {
        let s = WidgetSnapshot.build(friday, now: Date())
        XCTAssertEqual(s.sparkline.count, 97)
        XCTAssert(s.sparkline.allSatisfy { (0.0...1.0).contains($0) })
        XCTAssert((0.0...1.0).contains(s.nowFraction))
    }

    func testDeterministic() {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        XCTAssertEqual(WidgetSnapshot.build(friday, now: now),
                       WidgetSnapshot.build(friday, now: now))
    }

    /// Regression for the unpadded backward fetch: `DerivedSlackStation
    /// .schematicSigned` reads 0 before the first slack in its `slacks`
    /// array, so a fetch starting exactly at dayStart left the sparkline
    /// flat from midnight until the day's first slack. Picks a fixed epoch
    /// whose UNPADDED first slack lands well after midnight (guarded below),
    /// so the leading samples can only be non-flat if the backward pad
    /// pulled in the slack that actually straddles midnight.
    func testDerivedSparklineIsNotFlatBeforeFirstSlack() {
        let tz = TimeZone(identifier: "UTC")!
        let station = derivedGate(tz: tz)
        guard case .derived(let gate, _, _) = station else { return XCTFail("expected .derived") }

        let now = Date(timeIntervalSince1970: 1_755_800_000)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let dayStart = cal.startOfDay(for: now)

        // Fixture sanity: without a backward pad, the day's first slack is
        // well after midnight, so a flat run at the start is unambiguous.
        let unpaddedFirst = gate.slacks(from: dayStart, to: dayStart.addingTimeInterval(86_400)).first
        let firstSlackOffset = try! XCTUnwrap(unpaddedFirst).time.timeIntervalSince(dayStart)
        XCTAssertGreaterThan(firstSlackOffset, 3_600,
                             "fixture must have its first slack well after midnight to exercise the pad")

        let s = WidgetSnapshot.build(station, now: now)
        // Samples strictly before that first slack must show real curve
        // (the prior cycle bleeding across midnight), not the padding bug's
        // flat run of exact zeros.
        let leadingCount = Int(firstSlackOffset / (86_400.0 / 96))
        let leading = s.sparkline.prefix(leadingCount)
        XCTAssertGreaterThan(leading.count, 0)
        XCTAssert(leading.contains { abs($0) > 0.01 }, "leading samples are flat — backward pad missing")
    }

    func testDerivedStateUsesTheCanonicalSlackWindow() {
        let station = derivedGate(tz: TimeZone(identifier: "UTC")!)
        guard case .derived(let gate, _, _) = station else { return XCTFail("expected .derived") }
        let seed = Date(timeIntervalSince1970: 1_755_800_000)
        let slacks = gate.slacks(from: seed.addingTimeInterval(-30 * 3600),
                                 to: seed.addingTimeInterval(30 * 3600))
        let now = slacks[1].time.addingTimeInterval(15 * 60)

        XCTAssertNotEqual(gate.phase(at: now, slacks: slacks).word, "Slack")
        XCTAssertEqual(WidgetSnapshot.build(station, now: now).state,
                       gate.phase(at: now, slacks: slacks).word)
    }

    /// 2026-03-08 is the US spring-forward date: America/Los_Angeles has a
    /// 23-hour local day. The derived branch is the one whose sample count
    /// is pinned to the real day length (step = dayLength/96), so this is
    /// the one that must hold exactly 97 on a DST day.
    func testDerivedSparklineHandlesDSTDay() {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        let station = derivedGate(tz: tz)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!

        let s = WidgetSnapshot.build(station, now: now)
        XCTAssertEqual(s.sparkline.count, 97)
        XCTAssert((0.0...1.0).contains(s.nowFraction))
        // The correct (23h) denominator, not the old fixed 86_400s one.
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        XCTAssertEqual(dayEnd.timeIntervalSince(dayStart), 23 * 3600)
        XCTAssertEqual(s.nowFraction, now.timeIntervalSince(dayStart) / (23 * 3600), accuracy: 0.0001)
    }
}
