// Slackwater — GPL v3. Accessory labels and next event, plus home-screen cards.
import XCTest
import SwiftUI
@testable import Slackwater
import SlackwaterKit

@MainActor final class WidgetSnapshotTests: XCTestCase {
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

    /// H2(4): the widget used to hardcode `" %.1f m"` regardless of the
    /// app's own Settings choice, so a metric-only label shipped to every
    /// imperial user. Setting imperial explicitly (rather than relying on
    /// the regional default) is the test that
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

    func testCurrentNextEventIsFuture() throws {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let s = WidgetSnapshot.build(current, now: now)
        XCTAssertGreaterThan(try XCTUnwrap(s.next).time, now)
        XCTAssertEqual(s.curveKind, .current)
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
            // SN.slackWindow == 0x38BDF8, ±24/channel.
            let windowInk = (0..<height).reduce(into: 0) { count, y in
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    if abs(Int(pixels[i]) - 0x38) <= 24, abs(Int(pixels[i + 1]) - 0xBD) <= 24,
                       abs(Int(pixels[i + 2]) - 0xF8) <= 24 { count += 1 }
                }
            }
            XCTAssertGreaterThan(windowInk, 100, "expected slack-window ink")
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

    /// The card says Slack only inside a window, as the detail lead and the complication do:
    /// weak water outside one still names its direction, and a window holds Slack at any speed.
    func testTheCardSaysSlackOnlyInsideAWindow() {
        typealias Reading = ConditionsItem.Reading
        XCTAssertEqual(Reading.current(magnitude: 0.1, direction: 0, speed: 0.1, unit: "kn").currentWord, .flood)
        XCTAssertEqual(Reading.current(magnitude: 0.1, direction: 180, speed: -0.1, unit: "kn").currentWord, .ebb)
        XCTAssertEqual(Reading.current(magnitude: 0.4, direction: 0, speed: 0.4, unit: "kn", inWindow: true).currentWord, .slack)
        XCTAssertEqual(Reading.current(magnitude: 0, direction: nil, speed: 0, unit: "kn").currentWord, .flood, "zero counts as flood, as on the lead")
        XCTAssertNil(Reading.gate(.slack).currentWord)
    }

    /// The widget and card read Slack on the marks their curve draws, as the detail lead does:
    /// a window up to but not at its closing, and a windowless slack's own second.
    func testWidgetCardSaysSlackOnTheCurvesSlackMarks() throws {
        let record = try XCTUnwrap(CurrentStationRecord.all.first)
        let t = Date(timeIntervalSince1970: 1_755_800_000)
        let bare = t.addingTimeInterval(3 * 3600)
        let points = stride(from: -720, through: 1440, by: 10).map { minute in
            CurrentPoint(time: t.addingTimeInterval(Double(minute) * 60), speed: minute == 0 ? 0 : 1)
        }
        let station = FixedWidgetCurrent(points: points, slacks: [t, bare])
        let window = try XCTUnwrap(record.cardGraph(at: t, unit: "kn", station: station).windows.first)
        func card(_ now: Date) -> WidgetCard { WidgetCard.build(.current(record, station: station), now: now) }

        XCTAssertEqual(card(t).reading.currentWord, .slack)
        XCTAssertEqual(card(t).countdownEnd, window.end)
        XCTAssertEqual(card(window.end).reading.currentWord, .flood, "the closing is already leaving slack")
        XCTAssertNil(card(window.end).countdownEnd, "no countdown at the closing")
        XCTAssertEqual(card(bare).reading.currentWord, .slack, "a windowless slack's dot")
        XCTAssertNil(card(bare).countdownEnd, "no window to count down")
        XCTAssertEqual(card(bare.addingTimeInterval(2)).reading.currentWord, .flood)
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
        if case .current(_, _, _, _, _, let slack) = card.reading {
            XCTAssertFalse(slack, "an hour before the window closes the water is moving, though the countdown runs")
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

    func testDeterministic() {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        XCTAssertEqual(WidgetSnapshot.build(friday, now: now),
                       WidgetSnapshot.build(friday, now: now))
    }

    func testDerivedNextSlackAcrossDSTTransitions() throws {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        let station = derivedGate(tz: tz)
        guard case .derived(let gate, _, _) = station else { return XCTFail("expected .derived") }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        for (month, day) in [(3, 8), (11, 1)] {
            let now = cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let expected = try XCTUnwrap(gate.slacks(from: now, to: cal.date(byAdding: .day, value: 2, to: now)!)
                .first { $0.time > now })
            let s = WidgetSnapshot.build(station, now: now)
            let next = try XCTUnwrap(s.next)
            XCTAssertEqual(next.time, expected.time)
            XCTAssertGreaterThan(next.time, now)
            XCTAssertEqual(next.label, "Slack")
            XCTAssertEqual(s.tz, tz)
            XCTAssertEqual(s.curveKind, .schematic)
        }
    }

    // MARK: - The card's speed and set

    /// 2026-08-10 12:00 UTC, the day the detail lead's Kodiak and Pollock Rip tests read.
    private var day: Date { Date(timeIntervalSince1970: 1_786_363_200) }

    /// A current card's reading as it prints and speaks: the word, the value, the set it shows (`•` where the neutral mark stands) and the spoken label.
    private func face(_ reading: ConditionsItem.Reading) -> [String] {
        guard case .current(let magnitude, let direction, let speed, let unit, _, let inWindow) = reading,
              let phase = reading.currentWord else { return [] }
        let f = currentCardFace(magnitude: magnitude, direction: direction, speed: speed, unit: unit,
                                inWindow: inWindow, setFormat: "compass")
        return [phase.word, f.value, f.markedSet.map { formatSet($0, format: "compass") } ?? "•", f.spoken]
    }

    /// The instants a day of a current's card is read at: every third hour, each event, and half a minute after each slack, where the water is too weak to show a set.
    private func cardInstants(_ station: any CurrentPredicting) -> [Date] {
        let events = station.events(from: day, to: day.addingTimeInterval(86_400))
        return (0..<8).map { day.addingTimeInterval(Double($0) * 3 * 3600 + 7) } + events.map(\.time)
            + events.filter { $0.kind == .slack }.map { $0.time.addingTimeInterval(30) }
    }

    /// Pollock Rip has no cross-flow constants, so its card and widget read exactly as they did before vectors: the unsigned major-axis speed and the published bearing for its sign.
    func testAOneAxisCardReadsAsItAlwaysHas() throws {
        let pollock = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/ACT1616"))
        XCTAssertNil(pollock.minorConstituents, "the fixture is one-axis")
        let faces = cardInstants(pollock.engineStation).map {
            face(WidgetCard.build(.current(pollock, station: pollock.engineStation), now: $0).reading)
        }
        XCTAssertEqual(faces, [
            ["Ebbing", "0.1", "SW", "0.1 kn, Ebbing, setting SW"],
            ["Ebbing", "1.4", "SW", "1.4 kn, Ebbing, setting SW"],
            ["Flooding", "0.2", "NE", "0.2 kn, Flooding, setting NE"],
            ["Flooding", "1.6", "NE", "1.6 kn, Flooding, setting NE"],
            ["Flooding", "0.1", "NE", "0.1 kn, Flooding, setting NE"],
            ["Ebbing", "1.6", "SW", "1.6 kn, Ebbing, setting SW"],
            ["Ebbing", "0.1", "SW", "0.1 kn, Ebbing, setting SW"],
            ["Flooding", "2.0", "NE", "2.0 kn, Flooding, setting NE"],
            ["Ebbing", "1.4", "SW", "1.4 kn, Ebbing, setting SW"],
            ["Slack", "0.0", "•", "0.0 kn, slack"],
            ["Flooding", "1.6", "NE", "1.6 kn, Flooding, setting NE"],
            ["Slack", "0.0", "•", "0.0 kn, slack"],
            ["Ebbing", "1.6", "SW", "1.6 kn, Ebbing, setting SW"],
            ["Slack", "0.0", "•", "0.0 kn, slack"],
            ["Flooding", "2.1", "NE", "2.1 kn, Flooding, setting NE"],
            ["Flooding", "0.0", "•", "0.0 kn, Flooding, setting NE"],
            ["Ebbing", "0.0", "•", "0.0 kn, Ebbing, setting SW"],
            ["Flooding", "0.0", "•", "0.0 kn, Flooding, setting NE"],
        ])
    }

    /// Kodiak's cross-flow runs at up to about 0.8 of its major axis: away from slack the card and widget print the water's full speed and point its own set, in the word the signed speed gives.
    func testARotaryCardShowsTheWatersSpeedAndSet() throws {
        let kodiak = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/KOD0901"))
        XCTAssertNotNil(kodiak.minorConstituents, "the fixture is rotary")
        let station = kodiak.engineStation
        var departs = 0
        for hour in 0..<24 {
            let t = day.addingTimeInterval(Double(hour) * 3600 + 7)
            let p = try XCTUnwrap(station.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first)
            let direction = try XCTUnwrap(p.direction)
            let word = p.speed >= 0 ? "Flooding" : "Ebbing"
            let value = formatSpeed(p.magnitude, unit: "kn")
            XCTAssertEqual(face(WidgetCard.build(.current(kodiak, station: station), now: t).reading),
                           [word, value, p.magnitude < 0.05 ? "•" : compassPoint(direction),
                            "\(value) kn, \(word), setting \(compassPoint(direction))"], "\(t)")
            let published = p.speed >= 0 ? kodiak.floodDirection : kodiak.ebbDirection
            if value != formatSpeed(abs(p.speed), unit: "kn") || compassPoint(direction) != compassPoint(published) {
                departs += 1
            }
        }
        XCTAssertGreaterThan(departs, 0, "the day's water leaves the major axis")
    }

    /// At Kodiak's slacks the card prints the water's full speed. Where it says Slack it shows the crossing flow's set only while that flow prints above zero; the card finds its own slacks over its own span, which can land them a second or more from these, so a slack it does not mark reads as moving water.
    func testARotaryCardAtSlackShowsTheCrossingFlow() throws {
        let kodiak = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/KOD0901"))
        let station = kodiak.engineStation
        let slacks = station.events(from: day, to: day.addingTimeInterval(86_400)).filter { $0.kind == .slack }
        var crossing = 0
        for slack in slacks {
            let p = try XCTUnwrap(station.speeds(from: slack.time, to: slack.time.addingTimeInterval(1), step: 1).first)
            let f = face(WidgetCard.build(.current(kodiak, station: station), now: slack.time).reading)
            let value = formatSpeed(p.magnitude, unit: "kn")
            let set = compassPoint(try XCTUnwrap(p.direction))
            if f.first != "Slack" {
                let word = p.speed >= 0 ? "Flooding" : "Ebbing"
                XCTAssertEqual(f, [word, value, p.magnitude < 0.05 ? "•" : set, "\(value) kn, \(word), setting \(set)"], "\(slack.time)")
            } else if value == "0.0" {
                XCTAssertEqual(f, ["Slack", "0.0", "•", "0.0 kn, slack"], "\(slack.time)")
            } else {
                crossing += 1
                XCTAssertEqual(f, ["Slack", value, set, "\(value) kn, slack, setting \(set)"], "\(slack.time)")
            }
        }
        XCTAssertGreaterThan(crossing, 0, "the water still crosses at a slack the card marks")
    }

    /// The widget's card at a synthetic rotary slack: the word Slack, the full speed, and the crossing flow's set; off the slack, the water's own set by the signed speed's word.
    func testTheWidgetCardShowsARotarySlacksCrossingFlow() throws {
        let record = try XCTUnwrap(CurrentStationRecord.all.first)
        let t = day
        let points = stride(from: -720, through: 1440, by: 10).map { minute in
            minute == 0 ? CurrentPoint(time: t, speed: 0, magnitude: 0.6, direction: 95)
                : CurrentPoint(time: t.addingTimeInterval(Double(minute) * 60), speed: 1, magnitude: 1.3, direction: 40)
        }
        let station = FixedWidgetCurrent(points: points, slacks: [t])
        func card(_ now: Date) -> [String] { face(WidgetCard.build(.current(record, station: station), now: now).reading) }
        XCTAssertEqual(card(t), ["Slack", "0.6", "E", "0.6 kn, slack, setting E"])
        XCTAssertEqual(card(t.addingTimeInterval(600)), ["Flooding", "1.3", "NE", "1.3 kn, Flooding, setting NE"])
    }

    /// The card's state keeps the whole engine-exact point, and the lock-screen widget's value is the same full speed the card prints.
    func testTheCardStateAndTheAccessoryValueCarryTheWatersSpeed() throws {
        let kodiak = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/KOD0901"))
        let station = WidgetStation.current(kodiak.engineStation, tz: TimeZone(identifier: "UTC")!, name: kodiak.name)
        for hour in [0, 6, 12, 18] {
            let t = day.addingTimeInterval(Double(hour) * 3600 + 7)
            let p = try XCTUnwrap(kodiak.engineStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first)
            let state = kodiak.cardState(at: t)
            XCTAssertEqual(state.signed, p.speed)
            XCTAssertEqual(state.magnitude, p.magnitude)
            XCTAssertEqual(state.direction, p.direction)
            XCTAssertEqual(WidgetSnapshot.build(station, now: t).value, "\(formatSpeed(p.magnitude, unit: "kn")) kn")
        }
        let pollock = try XCTUnwrap(CurrentStationRecord.record(id: "noaa/ACT1616"))
        let ebbing = pollock.cardState(at: day.addingTimeInterval(3 * 3600 + 7))
        XCTAssertLessThan(ebbing.signed, 0)
        XCTAssertEqual(ebbing.magnitude, abs(ebbing.signed))
        XCTAssertEqual(ebbing.direction, pollock.ebbDirection, "a one-axis card sets along the published bearing for its sign")
    }

    /// The card's set rule on a synthetic rotary current: at a slack the crossing flow's set shows only while it prints above zero, water too weak to mark keeps the neutral mark, and water with no known set claims none.
    func testTheCardMarksTheSetTheLeadWouldShow() {
        func face(_ magnitude: Double, _ direction: Double?, _ speed: Double, slack: Bool) -> CurrentCardFace {
            currentCardFace(magnitude: magnitude, direction: direction, speed: speed, unit: "kn", inWindow: slack, setFormat: "compass")
        }
        XCTAssertEqual(face(0.6, 95, 0, slack: true), CurrentCardFace(value: "0.6", markedSet: 95, spoken: "0.6 kn, slack, setting E"))
        XCTAssertEqual(face(0.03, 95, 0, slack: true), CurrentCardFace(value: "0.0", markedSet: nil, spoken: "0.0 kn, slack"))
        XCTAssertEqual(face(0.3, 0, 0.3, slack: true), CurrentCardFace(value: "0.3", markedSet: nil, spoken: "0.3 kn, slack"),
                       "along the axis there is no crossing flow to point at")
        XCTAssertEqual(face(1.5, 40, 1.2, slack: false), CurrentCardFace(value: "1.5", markedSet: 40, spoken: "1.5 kn, Flooding, setting NE"))
        XCTAssertEqual(face(0.04, 230, -0.03, slack: false), CurrentCardFace(value: "0.0", markedSet: nil, spoken: "0.0 kn, Ebbing, setting SW"))
        XCTAssertEqual(face(1.5, nil, 1.2, slack: false), CurrentCardFace(value: "1.5", markedSet: nil, spoken: "1.5 kn, Flooding"))
    }

    /// The card a state reads as, with the set format the tests pin.
    private func face(_ state: CurrentCardState, inWindow: Bool = false) -> [String] {
        face(.current(magnitude: state.magnitude, direction: state.direction, speed: state.signed, unit: "kn", inWindow: inWindow))
    }

    /// Dodd Narrows floods 355° and ebbs 155°, which is not the flood's reciprocal (175°): a one-axis card sets along the published bearing for its sign, never the flood turned around.
    func testAOneAxisCardSetsAlongThePublishedBearingNotTheReciprocal() {
        let t = day
        let ebbing = CurrentCardState(point: CurrentPoint(time: t, speed: -1.2), flood: 355, ebb: 155, next: nil)
        XCTAssertEqual(ebbing.direction, 155)
        XCTAssertEqual(face(ebbing), ["Ebbing", "1.2", "SSE", "1.2 kn, Ebbing, setting SSE"])
        XCTAssertEqual(currentCardFace(magnitude: ebbing.magnitude, direction: ebbing.direction, speed: ebbing.signed,
                                       unit: "kn", inWindow: false, setFormat: "compass").markedSet, 155)
        let flooding = CurrentCardState(point: CurrentPoint(time: t, speed: 1.2), flood: 355, ebb: 155, next: nil)
        XCTAssertEqual(flooding.direction, 355)
        XCTAssertEqual(face(flooding), ["Flooding", "1.2", "N", "1.2 kn, Flooding, setting N"])
        XCTAssertEqual(currentCardFace(magnitude: flooding.magnitude, direction: flooding.direction, speed: flooding.signed,
                                       unit: "kn", inWindow: false, setFormat: "compass").markedSet, 355)
    }

    /// An online gate's fetched samples, ten minutes apart from `day`, flooding 355° and ebbing 155°. The flood's last 0.2 kn turns to a 0.6 kn ebb a quarter of the way to the next sample, so the slack the samples derive lies 150 s after the 0.2.
    private var doddWindow: ChsOnlineWindow {
        let speeds = [1.0, 0.6, 0.2, -0.6, -1.2, -0.8]
        let times = speeds.indices.map { day.addingTimeInterval(Double($0) * 600).timeIntervalSince1970 }
        return ChsOnlineWindow(stationID: "test", iwlsName: "Test", timezone: "UTC", fetchedAt: day,
                               start: day, end: Date(timeIntervalSince1970: times.last!),
                               floodDirection: 355, ebbDirection: 155, times: times, speeds: speeds)
    }

    /// The online card reads its nearest sample's speed, and an ebb sample sets along the published ebb bearing.
    func testTheOnlineCardStateSetsAlongThePublishedEbb() {
        let window = doddWindow
        let ebb = day.addingTimeInterval(4 * 600)
        let state = window.cardState(at: ebb)
        XCTAssertEqual(state.signed, -1.2)
        XCTAssertEqual(state.magnitude, 1.2)
        XCTAssertEqual(state.direction, 155)
        XCTAssertEqual(face(state), ["Ebbing", "1.2", "SSE", "1.2 kn, Ebbing, setting SSE"])
    }

    /// Within a second of a slack the samples derive, the online card says Slack over its nearest sample's 0.2 kn. That water runs along the axis, so no crossing flow prints and the card shows the slack dot and speaks no set.
    func testTheOnlineCardAtADerivedSlackShowsTheDot() throws {
        let window = doddWindow
        let slack = try XCTUnwrap(sampleEvents(window.points).first { $0.kind == .slack }).time
        XCTAssertEqual(slack, day.addingTimeInterval(2 * 600 + 150))
        let now = slack.addingTimeInterval(0.5)
        let state = window.cardState(at: now)
        XCTAssertEqual(state.signed, 0.2, "the nearest sample")
        let graph = window.cardGraph(at: now, unit: "kn")
        XCTAssertTrue(graph.isSlack(at: now))
        XCTAssertEqual(face(state, inWindow: graph.isSlack(at: now)), ["Slack", "0.2", "•", "0.2 kn, slack"])
    }
}

/// A current whose samples and slacks are given, clipped to the range asked for.
private struct FixedWidgetCurrent: CurrentPredicting {
    let points: [CurrentPoint]
    let slacks: [Date]
    func speeds(from: Date, to: Date, step: TimeInterval) -> [CurrentPoint] {
        points.filter { $0.time >= from && $0.time <= to }
    }
    func events(from: Date, to: Date) -> [CurrentEvent] {
        slacks.filter { $0 >= from && $0 <= to }.map { CurrentEvent(time: $0, speed: 0, kind: .slack) }
    }
}
