// Slackwater — GPL v3. Tests for the continuous pan-under-centerline timeline
// (TimelineStrip.swift): fixed window and x↔time mapping, the now-readout
// equivalence with the old model's committed readout, night continuity across
// midnight, and the multi-day schedule window.
import Almanac
import SwiftUI
import XCTest
@testable import Slackwater
import SlackwaterKit

/// Wales, Alaska, in late July: sunset falls after local midnight, so a civil
/// day's first sunset comes before its sunrise. Day chrome as the builders make it.
func lateSunsetDays() throws -> (tz: TimeZone, days: [TimelineDay]) {
    let tz = try XCTUnwrap(TimeZone(identifier: "America/Nome"))
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let observer = try Observer(latitudeDeg: 65.61, longitudeDeg: -168.09)
    let first = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 7, day: 20)))
    let days = try (0..<5).map { i -> TimelineDay in
        let start = try XCTUnwrap(cal.date(byAdding: .day, value: i, to: first))
        let end = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: start))
        let sun = try sunEvents(from: start, to: end, observer: observer)
        return TimelineDay(offset: i, start: start,
                           sunrise: sun.first { $0.kind == .rise }?.time,
                           sunset: sun.first { $0.kind == .set }?.time,
                           moonrise: nil, moonset: nil)
    }
    return (tz, days)
}

@MainActor private final class FoldPageTestSource: ObservableObject {
    @Published var timeline: TimelineData?
    init(_ timeline: TimelineData?) { self.timeline = timeline }
}

private struct FoldPageTestHarness: View {
    @ObservedObject var source: FoldPageTestSource
    let tz: TimeZone
    @Binding var scrubTime: Date
    @Binding var anchor: Date
    let onPicked: (Date) -> Void

    var body: some View {
        ScrubDetailScaffold(name: "Fold test", region: "", favoriteId: "fold-page", tz: tz,
                            timeline: source.timeline, entries: { _ in [] },
                            scrubTime: $scrubTime, anchor: $anchor, onPicked: onPicked,
                            above: { EmptyView() },
                            card: { _ in Color.clear.frame(height: 1200) },
                            links: { _, _ in EmptyView() },
                            bottom: { Color.clear.frame(height: 1200) })
    }
}

@MainActor final class TimelineTests: XCTestCase {
    let friday = TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!

    @MainActor func testInitialCenterDoesNotPublishFromLayout() async {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let geo = TimelineGeo(data: data)
        for animated in [true, false] {
            let start = Timeline.introStart(for: now)
            var scrub = start
            var writes: [Date] = []
            let published = animated ? nil : expectation(description: "opening published after layout")
            let strip = TimelineScrubber(data: data, geo: geo, imperial: true, speedUnit: "kn", now: now,
                                        scrubTime: Binding(get: { scrub }, set: {
                                            scrub = $0
                                            writes.append($0)
                                            if writes.count == 1 { published?.fulfill() }
                                        }))
            let co = TimelineScrubber.Coordinator(strip)
            defer { co.stopIntro() }
            let sv = TimelineScrubber.ScrubScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: geo.height))
            sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
            sv.delegate = co
            co.centerIfNeeded(sv, animated: animated)
            co.centerIfNeeded(sv, animated: animated)
            XCTAssertTrue(writes.isEmpty, "initial layout must not write the SwiftUI binding, animated: \(animated)")
            XCTAssertTrue(co.didInitialCenter)
            XCTAssertEqual(co.nudging, animated)
            let target = animated ? start : now
            XCTAssertEqual(data.time(atX: sv.contentOffset.x + sv.bounds.width / 2).timeIntervalSince(target),
                           0, accuracy: 300)
            if let published {
                await fulfillment(of: [published], timeout: 2)
                XCTAssertEqual(writes, [now], "instant opening publishes exactly once after layout")
            }
            co.stopIntro()
            let count = writes.count
            sv.contentOffset.x += 40
            XCTAssertGreaterThan(writes.count, count, "ordinary scroll feedback must still publish")
            XCTAssertEqual(scrub, data.time(atX: sv.contentOffset.x + sv.bounds.width / 2))
        }
    }

    @MainActor func testViewUpdatesDoNotPublishScrollFeedback() {
        let now = Date(timeIntervalSince1970: 1788868800)
        let anchor = dayLocal(now, friday.tz)
        let initial = TimelineData.build(tide: friday, current: nil, now: now, anchor: anchor)
        let shifted = TimelineData.build(tide: friday, current: nil, now: now,
                                          anchor: addingDays(-1, to: anchor, in: friday.tz))
        var scrub = now
        var writes: [Date] = []
        let binding = Binding(get: { scrub }, set: { scrub = $0; writes.append($0) })
        let strip = TimelineScrubber(data: initial, geo: TimelineGeo(data: initial), imperial: true,
                                    speedUnit: "kn", now: now, scrubTime: binding)
        let co = TimelineScrubber.Coordinator(strip)
        let sv = TimelineScrubber.ScrubScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: strip.geo.height))
        sv.contentSize = CGSize(width: initial.totalWidth, height: strip.geo.height)
        sv.delegate = co
        co.centerIfNeeded(sv)
        for (hours, jump) in [(0.0, 0), (1.0, 0), (-30.0, 1)] {
            let requested = now.addingTimeInterval(hours * 3600)
            scrub = requested
            let updated = TimelineScrubber(data: shifted, geo: TimelineGeo(data: shifted), imperial: true,
                                          speedUnit: "kn", now: now, scrubTime: binding, jumpToken: jump)
            updated.updateUIView(sv, coordinator: co)
            XCTAssertTrue(writes.isEmpty, "applying a window, external time, or jump must not publish inside updateUIView")
            XCTAssertEqual(scrub, requested)
            // A request within a week rides; a window shift alone keeps the centre.
            let destination = co.magnetTarget ?? shifted.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
            XCTAssertEqual(destination.timeIntervalSince(requested), 0, accuracy: 300)
        }
        sv.contentOffset.x += 40
        XCTAssertEqual(writes.count, 1, "ordinary scrolling must publish after the view update returns")
        XCTAssertEqual(scrub, shifted.time(atX: sv.contentOffset.x + sv.bounds.width / 2))
    }

    func testInstantOpeningSurvivesUpdatesBeforeItsSelectionPublishes() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        for resized in [false, true] {
            let sel = Selection(now.addingTimeInterval(-7200))
            let m = mountedStrip(data, sel, now: now)
            defer { m.window.isHidden = true }
            if resized {
                m.sv.frame.size.width = 504
                m.co.layoutDidRun(m.sv)
            }
            m.strip(0).updateUIView(m.sv, coordinator: m.co)
            XCTAssertEqual(sel.time, now.addingTimeInterval(-7200), "layout and view updates defer the binding write")
            try await settle(m.co)
            XCTAssertEqual(sel.time, now, "an intervening update must not cancel the opening's deferred selection")
            XCTAssertEqual(data.time(atX: m.sv.contentOffset.x + m.sv.bounds.width / 2).timeIntervalSince(now),
                           0, accuracy: 100, "the opening stays centered on now through a resize")
        }
    }

    func testAnExplicitRequestSupersedesAnUnpublishedInstantOpening() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let sel = Selection(now.addingTimeInterval(-7200))
        let m = mountedStrip(data, sel, now: now)
        defer { m.window.isHidden = true }
        let requested = now.addingTimeInterval(9 * 3600)
        sel.time = requested
        m.strip(1).updateUIView(m.sv, coordinator: m.co)
        try await settle(m.co)
        XCTAssertEqual(sel.time, requested, "the deferred opening must not overwrite a newer request")
        XCTAssertEqual(data.time(atX: m.sv.contentOffset.x + m.sv.bounds.width / 2).timeIntervalSince(requested),
                       0, accuracy: 100)
    }

    func testADragSupersedesAnUnpublishedInstantOpening() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let sel = Selection(now.addingTimeInterval(-7200))
        let m = mountedStrip(data, sel, now: now)
        defer { m.window.isHidden = true }
        m.co.scrollViewWillBeginDragging(m.sv)
        m.sv.contentOffset.x += Timeline.pph * 3
        try await settle(m.co)
        XCTAssertEqual(sel.time.timeIntervalSince(now), 10800, accuracy: 100,
                       "the deferred opening must not overwrite the first drag")
    }

    func testPixelRoundedCenterStaysWithinHalfAPointOfTheReadout() {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let geo = TimelineGeo(data: data)
        let target = formatter("yyyy-MM-dd HH:mm", friday.tz).date(from: "2026-09-09 09:54")!
        for width in [CGFloat(400), 500, 514, 800, 834, 1194] {
            var scrub = target
            let strip = TimelineScrubber(data: data, geo: geo, imperial: true, speedUnit: "kn", now: now,
                                        scrubTime: Binding(get: { scrub }, set: { scrub = $0 }))
            let co = TimelineScrubber.Coordinator(strip)
            let sv = TimelineScrubber.ScrubScrollView(frame: CGRect(x: 0, y: 0, width: width, height: geo.height))
            sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
            sv.delegate = co
            co.layoutDidRun(sv)
            let centre = data.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
            XCTAssertEqual(centre.timeIntervalSince(target), 0, accuracy: 0.5 * 3600 / Double(Timeline.pph),
                           "width \(width): the curve drifted more than half a point")
            XCTAssertEqual(sv.accessibilityValue, spokenWhen(centre, data.tz))
            XCTAssertEqual(scrub, target, "pixel rounding must not rewrite the selected time")
        }
    }

    func testSlackWindowSettingHasIncrementalTouchControls() throws {
        let source = try repoSource("Slackwater/SettingsView.swift")
        XCTAssertTrue(source.contains("Stepper(value: slackWindowSpeedBinding, in: slackThresholdRange, step: 0.1)"),
                      "Comfort current needs visible ± controls in 0.1-kn steps")
        XCTAssertEqual(slackThresholdRange, 0...10, "zero is Off (#821)")
        XCTAssertFalse(source.contains("TextField(\"0.5\""),
                       "a bare text field makes the setting look non-interactive")
    }

    func testSlackWindowSpeedStaysInItsSupportedRange() {
        XCTAssertEqual(normalizedSlackThresholdKn(1), 1)
        XCTAssertEqual(normalizedSlackThresholdKn(0), 0, "Off")
        XCTAssertEqual(normalizedSlackThresholdKn(0.3 - 0.1 - 0.1 - 0.1), 0, "a stepped-down tenth is Off, not −3e-17 kn")
        XCTAssertEqual(normalizedSlackThresholdKn(-0.1), defaultSlackThresholdKn)
        XCTAssertEqual(normalizedSlackThresholdKn(10.1), defaultSlackThresholdKn)
    }

    func testTimelineKeepsItsChosenSlackWindowSpeed() {
        let station = CurrentStationRecord.all.first!
        let timeline = TimelineData.build(tide: nil, current: station, now: Date(),
                                          anchor: todayLocal(station.tz), threshold: 1)
        XCTAssertEqual(timeline.slackThreshold, 1)
    }

    /// Calendar days, never `n * 86_400`. Only durations belong in
    /// `addingTimeInterval`: across a DST transition a 34×86,400-second offset
    /// from a local midnight lands at 01:00 or 23:00, and an anchor that isn't
    /// a midnight fails every assertion that compares one. Measured over 2026
    /// in Pacific, 68 of 365 start dates land off midnight — the suite was
    /// green today and red for roughly two months of the year.
    ///
    /// The calendar carries the STATION's zone, not the device's: a
    /// calendar-day add is only correct in the zone the dates belong to.
    private func addingDays(_ n: Int, to date: Date, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(byAdding: .day, value: n, to: date)!
    }

    func testWindowAndMapping() {
        let now = Date()
        let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: todayLocal(friday.tz))
        // -48h … +180h around today's local midnight (spec §2).
        XCTAssertEqual(d.end.timeIntervalSince(d.start), 228 * 3600, accuracy: 3601)
        XCTAssertEqual(d.totalWidth, 228 * Timeline.pph, accuracy: 13)
        XCTAssert(d.start <= now && now <= d.end)
        // x ↔ time round trip under the centerline.
        XCTAssertEqual(d.time(atX: d.x(now)).timeIntervalSince(now), 0, accuracy: 1)
        // Snap stops exist across the whole window (turns + sun events).
        XCTAssert(d.snapTimes.count > 20, "expected a full week of stops, got \(d.snapTimes.count)")
        XCTAssert(d.snapTimes.first! < d.today, "stops must reach back before today")
    }

    func testTideChevronCentersAreMagneticStops() {
        let fastest = TideStationRecord.all.max {
            $0.constituents.reduce(0) { $0 + $1.amplitude }
                < $1.constituents.reduce(0) { $0 + $1.amplitude }
        }!
        let d = TimelineData.build(tide: fastest, current: nil, now: Date(), anchor: todayLocal(fastest.tz))
        let chevrons = tideFlowArrows(d.tideRates).filter { $0.time >= d.start && $0.time <= d.end }
        XCTAssertFalse(chevrons.isEmpty)
        XCTAssertTrue(chevrons.allSatisfy { d.snapTimes.contains($0.time) })
    }

    func testSixFeetPerHourTideRateIsRed() {
        XCTAssertEqual(Timeline.rampT(forTideRateMHr: 1.8), 1, accuracy: 1e-9)
        XCTAssertEqual(Timeline.rampT(forTideRateMHr: 6.1 / 3.28084), 1, accuracy: 1e-9)
    }

    func testScrubberIntroStartsTwoHoursBeforeNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Timeline.introStart(for: now), Date(timeIntervalSince1970: 992_800))
    }

    func testScrubberIntroStaysBrief() {
        XCTAssertTrue((0.5...1).contains(Timeline.introDuration))
    }

    func testScrubberIntroAdvancesThroughTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = Timeline.introStart(for: now)
        XCTAssertEqual(Timeline.introTime(from: start, to: now, elapsed: 0), start)
        XCTAssertEqual(Timeline.introTime(from: start, to: now,
                                          elapsed: Timeline.introDuration / 2),
                       now.addingTimeInterval(-3600))
        XCTAssertEqual(Timeline.introTime(from: start, to: now,
                                          elapsed: Timeline.introDuration), now)
    }

    func testHingeProgressRunsFromTheFirstAngleToFlat() {
        XCTAssertEqual(Timeline.hingeProgress(angle: 0.5, from: 0.5), 0)
        XCTAssertEqual(Timeline.hingeProgress(angle: (0.5 + .pi) / 2, from: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Timeline.hingeProgress(angle: .pi, from: 0.5), 1)
        XCTAssertEqual(Timeline.hingeProgress(angle: 0.2, from: 0.5), 0, "closing past the start stays at the start")
        XCTAssertEqual(Timeline.hingeProgress(angle: .pi, from: .pi), 1, "already flat is done")
    }

    func testAHingeThatHasNotMovedYetGetsLongerToStart() {
        XCTAssertFalse(Timeline.hingeSettled(moved: false, idle: 0.67), "the simulator's pause at the posture switch")
        XCTAssertTrue(Timeline.hingeSettled(moved: false, idle: Timeline.hingeFirstMove + 0.1))
        XCTAssertFalse(Timeline.hingeSettled(moved: true, idle: Timeline.hingeSettle / 2))
        XCTAssertTrue(Timeline.hingeSettled(moved: true, idle: Timeline.hingeSettle + 0.05), "propped half-open")
    }

    func testFoldHandoffGoesOnlyToTheSameStationWhileFresh() {
        defer { FoldHandoff.slot = nil }
        let moment = FoldHandoff.Moment(stationID: "a", time: Date(), live: false, closing: false, at: 100)
        FoldHandoff.slot = moment
        XCTAssertNil(FoldHandoff.take("b", at: 100.5), "another station's strip")
        XCTAssertNil(FoldHandoff.slot, "a take clears the slot either way")
        FoldHandoff.slot = moment
        XCTAssertNil(FoldHandoff.take("a", at: 100 + FoldHandoff.freshFor + 1), "a different visit")
        FoldHandoff.slot = moment
        XCTAssertEqual(FoldHandoff.take("a", at: 100.5)?.time, moment.time)
    }

    /// The rebuilt detail reads the folded moment before its strip takes it, so
    /// its first data is built around a moment far from now.
    func testAPendingFoldIsReadWithoutTakingIt() {
        defer { FoldHandoff.slot = nil }
        let moment = FoldHandoff.Moment(stationID: "a", time: Date(timeIntervalSince1970: 0), live: false, closing: false, at: 100)
        FoldHandoff.slot = moment
        XCTAssertEqual(FoldHandoff.pending("a", at: 100.5), moment.time)
        XCTAssertNotNil(FoldHandoff.slot, "pending leaves the moment for the strip's take")
        XCTAssertNil(FoldHandoff.pending("b", at: 100.5), "another station's strip")
        XCTAssertNil(FoldHandoff.pending("a", at: 100 + FoldHandoff.freshFor + 1), "a different visit")
        FoldHandoff.slot = .init(stationID: "a", time: moment.time, live: true, closing: false, at: 100)
        XCTAssertNil(FoldHandoff.pending("a", at: 100.5), "on now, the ordinary build already covers it")
    }

    /// A fold rebuilds the detail. Closing lands the cover screen's strip on the
    /// folded moment; opening starts ahead of it and the hinge brings it back.
    @MainActor func testAFoldHandsTheMomentToTheRebuiltStrip() async {
        defer { FoldHandoff.slot = nil }
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let geo = TimelineGeo(data: data)
        let moment = now.addingTimeInterval(3 * 3600)
        for closing in [true, false] {
            var scrub = Timeline.introStart(for: now)
            let landed = expectation(description: "lands on the folded moment, closing: \(closing)")
            landed.assertForOverFulfill = false  // the scroll callback and the final park both write it
            let strip = TimelineScrubber(data: data, geo: geo, imperial: true, speedUnit: "kn", now: now,
                                        scrubTime: Binding(get: { scrub }, set: {
                                            scrub = $0
                                            if $0 == moment { landed.fulfill() }
                                        }), stationID: "fh",
                                        foldPage: .init(anchor: data.anchor, showingSchedule: true))
            let co = TimelineScrubber.Coordinator(strip)
            defer { co.stopIntro() }
            let sv = TimelineScrubber.ScrubScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: geo.height))
            sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
            sv.delegate = co
            scrub = moment
            co.hingeDidChange(closed: closing, fullyOpen: false, angle: 0.5)
            XCTAssertEqual(FoldHandoff.peek("fh")?.page?.anchor, data.anchor)
            XCTAssertEqual(FoldHandoff.peek("fh")?.page?.showingSchedule, true)
            scrub = Timeline.introStart(for: now)
            co.centerIfNeeded(sv, animated: true)
            let centered = data.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
            XCTAssertEqual(centered.timeIntervalSince(moment), closing ? 0 : Timeline.hingeLead, accuracy: 300)
            if !closing {
                co.hingeDidChange(closed: false, fullyOpen: false, angle: 0.5)
                co.hingeDidChange(closed: false, fullyOpen: true, angle: .pi)
            }
            await fulfillment(of: [landed], timeout: 3)
        }
    }

    func testFoldPageSurvivesTheStripTakingItsMomentBeforeAppear() async {
        defer { FoldHandoff.slot = nil; FoldHandoff.pageSlot = nil }
        let week = Date(timeIntervalSince1970: 1790665200)
        let moment = week.addingTimeInterval(4 * 3600)
        var anchor = Date.distantPast
        var scrub = Date.distantPast
        let picked = expectation(description: "restore the captured page")
        FoldHandoff.slot = .init(stationID: "fold-page", time: moment, live: false, closing: true,
                                 at: CACurrentMediaTime(), page: .init(anchor: week, showingSchedule: false))
        let page = ScrubDetailScaffold(name: "Fold test", region: "", favoriteId: "fold-page", tz: friday.tz,
                                       timeline: nil, entries: { _ in [] },
                                       scrubTime: Binding(get: { scrub }, set: { scrub = $0 }),
                                       anchor: Binding(get: { anchor }, set: { anchor = $0 }),
                                       onPicked: { _ in picked.fulfill() },
                                       above: { EmptyView() }, card: { _ in EmptyView() },
                                       links: { _, _ in EmptyView() }, bottom: { EmptyView() })
        _ = FoldHandoff.take("fold-page", at: CACurrentMediaTime())
        let host = UIHostingController(rootView: page)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        await fulfillment(of: [picked], timeout: 2)
        XCTAssertEqual(anchor, week)
        XCTAssertEqual(scrub, moment)
    }

    func testFoldPageAndMomentCanBeTakenInEitherOrder() {
        defer { FoldHandoff.slot = nil; FoldHandoff.pageSlot = nil }
        let week = Date(timeIntervalSince1970: 1790665200)
        for pageFirst in [true, false] {
            FoldHandoff.slot = .init(stationID: "fold-page", time: week, live: false, closing: true,
                                     at: 100, page: .init(anchor: week, showingSchedule: true))
            let page: FoldHandoff.Moment?
            let moment: FoldHandoff.Moment?
            if pageFirst {
                page = FoldHandoff.takePage("fold-page", at: 100.5)
                moment = FoldHandoff.take("fold-page", at: 100.6)
            } else {
                moment = FoldHandoff.take("fold-page", at: 100.5)
                XCTAssertNil(FoldHandoff.takePage("another", at: 100.6))
                page = FoldHandoff.takePage("fold-page", at: 100.7)
            }
            XCTAssertEqual(page?.page?.anchor, week)
            XCTAssertEqual(page?.page?.showingSchedule, true)
            XCTAssertEqual(moment?.time, week)
            XCTAssertNil(FoldHandoff.takePage("fold-page", at: 100.8), "a page is consumed once")
        }
        FoldHandoff.slot = .init(stationID: "fold-page", time: week, live: false, closing: true,
                                 at: 100, page: .init(anchor: week, showingSchedule: true))
        _ = FoldHandoff.take("fold-page", at: 100.5)
        XCTAssertNil(FoldHandoff.takePage("fold-page", at: 103), "an expired page is a different visit")
    }

    func testAFoldRestoresTheChosenWeekAndSchedule() async throws {
        defer { FoldHandoff.slot = nil; FoldHandoff.pageSlot = nil }
        let now = Date(timeIntervalSince1970: 1788868800)
        let week = Date(timeIntervalSince1970: 1790665200)
        let moment = week.addingTimeInterval(60 * 3600)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: week)
        for (delayed, showingSchedule, live) in [(true, true, false), (false, true, true), (false, false, false)] {
            var anchor = Date.distantPast
            var scrub = Timeline.introStart(for: now)
            let picked = expectation(description: "load the restored week")
            FoldHandoff.slot = .init(stationID: "fold-page", time: moment, live: live, closing: true,
                                     at: CACurrentMediaTime(),
                                     page: .init(anchor: week, showingSchedule: showingSchedule))
            let source = FoldPageTestSource(delayed ? nil : data)
            let host = UIHostingController(rootView: FoldPageTestHarness(
                source: source, tz: friday.tz,
                scrubTime: Binding(get: { scrub }, set: { scrub = $0 }),
                anchor: Binding(get: { anchor }, set: { anchor = $0 }),
                onPicked: { XCTAssertEqual($0, week); picked.fulfill() }))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            host.view.layoutIfNeeded()
            await fulfillment(of: [picked], timeout: 2)
            XCTAssertEqual(anchor, week, "keep the chosen week's start, not the selected moment's day")
            if live { XCTAssertEqual(scrub.timeIntervalSince(appNow()), 0, accuracy: 2) }
            else { XCTAssertEqual(scrub, moment) }
            _ = FoldHandoff.take("fold-page", at: CACurrentMediaTime())
            if delayed {
                source.timeline = data
                host.view.layoutIfNeeded()
            }
            func scrollView(in view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView { return scroll }
                return view.subviews.compactMap { scrollView(in: $0) }.first
            }
            for frame in 0..<100 {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                if let scroll = scrollView(in: host.view), scroll.contentOffset.y > 1000 { break }
                if !showingSchedule, frame >= 5 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let scroll = try XCTUnwrap(scrollView(in: host.view))
            if showingSchedule {
                XCTAssertGreaterThan(scroll.contentOffset.y, 1000, "the schedule stays in view; delayed: \(delayed), live: \(live); size \(scroll.contentSize), bounds \(scroll.bounds)")
            } else {
                XCTAssertEqual(scroll.contentOffset.y, 0, accuracy: 1, "the chart stays in view")
            }
        }
    }

    /// The current lead speaks plain language, and both current surfaces get
    /// it from the same view. `CurrentScrubCard` is the shared anatomy —
    /// strip, lead, commentary — so a redesign cannot land on a harmonic
    /// station and miss an online gate the way it did in #55.
    func testCurrentHeadersLeadWithPlainLanguageAndRestoreNow() throws {
        let lead = try repoSource("Slackwater/CurrentLead.swift")
        XCTAssertTrue(lead.contains("phase.word"), "the lead names the phase in words")
        XCTAssertTrue(lead.contains("formatSet(setDegrees, format: setFormat)"), "and the set in the chosen format")
        for file in ["Slackwater/CurrentDetailView.swift", "Slackwater/OnlineGateDetailView.swift"] {
            let source = try repoSource(file)
            XCTAssertTrue(source.contains("CurrentScrubCard("), "\(file) must draw the shared scrub card")
            XCTAssertTrue(source.contains("onReturn: returnToNow"), "\(file) must offer a way back to now")
        }
        let strip = try repoSource("Slackwater/TimelineScrubber.swift")
        XCTAssertTrue(strip.contains("scrubbedAway(scrubTime, from: now)"))
        XCTAssertTrue(strip.contains("detail-return-now"))
    }

    /// No current detail reaches for the global threshold: `TimelineData.build`
    /// takes `threshold:` as a parameter, and the lead reads the windows the
    /// strip was built with, so nothing can draw one band and describe
    /// another (#233). The run on the line is the threshold's only mark.
    func testSlackReadoutsNeverUseTheGlobalThreshold() throws {
        for file in ["Slackwater/CurrentDetailView.swift", "Slackwater/OnlineGateDetailView.swift",
                     "Slackwater/CurrentLead.swift"] {
            let source = try repoSource(file)
            XCTAssertFalse(source.contains("formatSpeed(slackThresholdKn"), file)
            XCTAssertFalse(source.contains("threshold: slackThresholdKn"), file)
            XCTAssertFalse(source.contains("slackWindow(tl.currentPoints"), file)
        }
    }

    func testOnlineGatesShareTheDownloadSurfaceAndCopy() throws {
        let manager = try repoSource("Slackwater/OfflineDownloads.swift")
        let detail = try repoSource("Slackwater/OnlineGateDetailView.swift")
        let service = try repoSource("Slackwater/ChsFitService.swift")
        XCTAssertTrue(manager.contains("case .online(let gate): onlineRow(gate)"))
        XCTAssertTrue(service.contains("private func observeConnectivity()"))
        XCTAssertFalse(detail.contains("No offline prediction here"))
    }

    /// `now:` used to be a dead parameter — `today` was always derived from the
    /// real clock (`todayLocal(tz)`) regardless of what was passed in. A caller
    /// simulating a different day (a test, or a future date-picker caller) must
    /// get back ITS day, not the device's.
    func testTodayDerivesFromThePassedNowNotTheRealClock() {
        let tz = friday.tz
        let simulatedNow = todayLocal(tz).addingTimeInterval(5 * 86_400 + 3600)  // 5 days ahead, mid-morning
        let d = TimelineData.build(tide: friday, current: nil, now: simulatedNow, anchor: todayLocal(tz))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        XCTAssertEqual(d.today, cal.startOfDay(for: simulatedNow),
                       "today must follow the passed `now`, not the real clock")
    }

    /// The anchor drives geometry; `today` stays the real day. A September strip
    /// must be built around September and still know what day it actually is.
    func testFutureAnchorMovesTheWindowButNotToday() {
        let now = Date()
        let tz = friday.tz
        let today = todayLocal(tz)
        let future = addingDays(34, to: today, in: tz)

        let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: future)
        XCTAssertEqual(d.anchor, future)
        XCTAssertEqual(d.today, today, "today is the real day, not the anchor")
        XCTAssertEqual(d.start, future.addingTimeInterval(-Timeline.backHours * 3600),
                       "the 48h back-pad is unconditional (#67 item 1)")
        XCTAssertEqual(d.end.timeIntervalSince(d.start), (Timeline.backHours + 180) * 3600, accuracy: 3601)
        XCTAssert(d.tidePoints.allSatisfy { $0.time >= d.start && $0.time <= d.end })
    }

    func testContainsBoundsTheStripWindow() {
        let tz = friday.tz
        let today = todayLocal(tz)
        let now = Date()
        let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: today)
        XCTAssert(d.contains(now), "a today-anchored strip contains now")

        let ahead = TimelineData.build(tide: friday, current: nil, now: now,
                                       anchor: addingDays(34, to: today, in: tz))
        XCTAssertFalse(ahead.contains(now),
                       "a September strip must not claim to hold today's now-marker")
        XCTAssert(ahead.contains(ahead.anchor.addingTimeInterval(3 * 86_400)))
    }

    /// `days` must reach one day PAST the last visible night — `drawDayChrome`
    /// reads day+1's sunrise to place the moon mid-night — and far enough BACK
    /// that the day containing `start` was built, which is what `visibleDays`
    /// needs to decide what draws.
    ///
    /// Both stated against the window, never against the literal range. This
    /// test used to pin `days.first?.offset == -2` and `.last?.offset == 8`,
    /// and the -2 went red the moment the range legitimately widened to -3: a
    /// bound of `dayChrome`'s own array is an implementation detail, not a
    /// property anything depends on. What IS depended on is that the array
    /// covers the window at both ends.
    ///
    /// The March pair keeps the backward half honest year-round. On the two
    /// anchors following a spring-forward the 48h look-back reaches an hour
    /// into the THIRD calendar day back, because the day between them is only
    /// 23 hours long — narrow the range to -2 again and this fails on any day
    /// of the year, not just in March. `anchor` alone drives `start`/`end`/`days`
    /// (the back-pad is unconditional, #67 item 1), so the custom `now` here
    /// only keeps `today` sane for a March date — it plays no part in exercising
    /// the -3-day spread.
    func testDayChromeCoversTheLastNightsMoon() {
        let springForwardPlusOne = vancouverMidnight(2026, 3, 9)
        for (anchor, now) in [(todayLocal(friday.tz), Date()),
                              (springForwardPlusOne, springForwardPlusOne.addingTimeInterval(9 * 3600))] {
            let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: anchor)

            XCTAssertNotNil(d.day(of: d.start),
                            "no built day contains the strip's start (anchor \(anchor))")

            let lastNight = d.visibleDays.last!
            let nextDay = d.days.first { $0.offset == lastNight.offset + 1 }
            XCTAssertNotNil(nextDay,
                            "the last visible night has no following day (anchor \(anchor))")
            XCTAssertNotNil(lastNight.sunset)
            XCTAssertNotNil(nextDay?.sunrise,
                            "the last visible night needs the next day's sunrise for its moon")
        }
    }

    /// "Today" must mean today, on any strip. The old signature took a
    /// days-from-today offset; once the anchor moves, offset is days-from-ANCHOR
    /// and passing it here would label a September Monday "Today".
    func testRelativeDayLabelTracksTodayNotTheAnchor() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        let today = vancouverMidnight(2026, 8, 11)          // a Tuesday
        let tomorrow = vancouverMidnight(2026, 8, 12)
        let yesterday = vancouverMidnight(2026, 8, 10)
        let september = vancouverMidnight(2026, 9, 14)      // a Monday

        XCTAssertEqual(relativeDayLabel(today, tz, today: today), "Today")
        XCTAssertEqual(relativeDayLabel(tomorrow, tz, today: today), "Tomorrow")
        XCTAssertEqual(relativeDayLabel(yesterday, tz, today: today), "Yesterday")
        XCTAssertEqual(relativeDayLabel(september, tz, today: today), "Mon",
                       "a day 34 days out is a weekday, never Today")
    }

    /// The first group of a future-anchored schedule is the anchor's own day, and
    /// it must NOT be called Today.
    func testFutureAnchorFirstDayIsNotLabelledToday() {
        let tz = friday.tz
        let today = todayLocal(tz)
        let future = addingDays(34, to: today, in: tz)
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: future)
        let firstDay = d.days.first { $0.offset == 0 }!
        XCTAssertEqual(firstDay.start, future, "offset 0 is the ANCHOR's day")
        XCTAssertNotEqual(relativeDayLabel(firstDay.start, tz, today: today), "Today")
    }

    /// The list runs the anchor's 00:00 → +7 local calendar days, and it is
    /// strictly inside the strip — even when DST makes that week 167h or 169h.
    func testScheduleRangeIsSevenLocalDaysAcrossDST() {
        let tz = friday.tz
        for (anchor, hours) in [(vancouverMidnight(2026, 3, 8), 167.0),
                                (vancouverMidnight(2026, 11, 1), 169.0)] {
            let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: anchor)
            XCTAssertEqual(d.scheduleRange.lowerBound, anchor)
            XCTAssertEqual(d.scheduleRange.upperBound, addingDays(7, to: anchor, in: tz))
            XCTAssertEqual(d.scheduleRange.upperBound.timeIntervalSince(anchor) / 3600, hours)
            XCTAssertLessThan(d.scheduleRange.upperBound, d.end,
                              "the strip must outrun the list by the centerPad")
        }
    }

    /// Seven day-groups, and the first is the anchor's own day.
    func testFutureAnchorSchedulesSevenDays() {
        let tz = friday.tz
        let future = addingDays(34, to: todayLocal(tz), in: tz)
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: future)
        let turns = d.tideExtremes.filter { d.scheduleRange.contains($0.time) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let days = Set(turns.map { cal.startOfDay(for: $0.time) })
        XCTAssertEqual(days.count, 7, "a week of tide turns, got \(days.count)")
        XCTAssertEqual(days.min(), future)
    }

    // MARK: - The window (spec §1, §2)

    private func vancouverMidnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// #67 item 1: every window carries the 48h look-back — today's answers "what
    /// did the water just do"; a picked week's puts data behind the noon park
    /// (216pt in), which otherwise opens on dead space on any pane wider than
    /// 432pt (UIScrollView clamps the negative centering offset). One
    /// unconditional shape also deletes the anchor == today exact-equality trap
    /// three comment blocks used to guard.
    func testWindowBackPadIsUnconditional() {
        let today = vancouverMidnight(2026, 8, 11)
        let current = Timeline.window(anchor: today)
        XCTAssertEqual(current.start, today.addingTimeInterval(-48 * 3600))
        XCTAssertEqual(current.end, today.addingTimeInterval(180 * 3600))

        let future = vancouverMidnight(2026, 9, 14)
        let ahead = Timeline.window(anchor: future)
        XCTAssertEqual(ahead.start, future.addingTimeInterval(-48 * 3600),
                       "a picked week gets the same look-back as today's")
        XCTAssertEqual(ahead.end, future.addingTimeInterval(180 * 3600))

        let past = vancouverMidnight(2026, 7, 6)
        let behind = Timeline.window(anchor: past)
        XCTAssertEqual(behind.start, past.addingTimeInterval(-48 * 3600),
                       "a past anchor gets the same look-back as today's")
        XCTAssertEqual(behind.end, past.addingTimeInterval(180 * 3600))
    }

    /// The strip must stay WIDER than the list, or tapping the last schedule row
    /// lands the centerline short of the event it names (UIScrollView clamps
    /// contentOffset). The pad is what guarantees it.
    func testStripOutrunsTheScheduleByTheCenterPad() {
        XCTAssertEqual(Timeline.scheduleHours, 168, "a week in the list")
        XCTAssertEqual(Timeline.forwardHours, Timeline.scheduleHours + Timeline.centerPad)
        XCTAssertGreaterThan(Timeline.centerPad * Timeline.pph, 200,
                             "the pad must exceed half a phone's width in points")
    }

    func testTodayLocalIsMidnightInTheGivenZone() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let t = todayLocal(tz)
        XCTAssertEqual(t, cal.startOfDay(for: appNow()))
        XCTAssertEqual(cal.component(.hour, from: t), 0)
    }

    /// The centerline readout at "now" must equal the old model's now-readout:
    /// both are the same engine step-1 heights call. The strip's riding dot
    /// (10-min interpolation) must agree within rendering tolerance.
    func testNowReadoutEquivalence() {
        let now = Date()
        let engine = friday.engineStation
            .heights(from: now, to: now.addingTimeInterval(1), step: 1).first!.height
        let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: todayLocal(friday.tz))
        XCTAssertEqual(d.heightAt(now), engine, accuracy: 0.02)
        print("NOW-READOUT Friday Harbor @ \(now): engine=\(engine) m, strip=\(d.heightAt(now)) m")
    }

    /// Days bleed into each other: every night band runs sunset → next
    /// sunrise, straddling the midnight between them.
    func testNightContinuityAcrossMidnight() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        var checked = 0
        for (a, b) in zip(d.days, d.days.dropFirst()) {
            guard let set = a.sunset, let rise = b.sunrise else { continue }
            XCTAssert(set < b.start && b.start < rise,
                      "night must straddle midnight: \(set) … \(rise)")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 7)
    }

    /// Where sunset follows local midnight, each sun event pairs with the next one rather than with its civil day's,
    /// and each day's name centres on the daylight its sunrise begins.
    func testSunBandsPairBySuccessionWhereSunsetFollowsMidnight() throws {
        let (tz, days) = try lateSunsetDays()
        XCTAssertTrue(days.contains { d in
            guard let rise = d.sunrise, let set = d.sunset else { return false }
            return set < rise
        }, "no day here sets before it rises: the fixture proves nothing")
        let start = days[0].start, end = try XCTUnwrap(days.last?.start)
        let data = TimelineData(tz: tz, anchor: start, today: start, start: start, end: end, days: days,
                                tidePoints: [], tideRates: [], tideExtremes: [],
                                currentPoints: [], currentEvents: [], snapTimes: [], slackWindows: [])
        let spans = data.sunSpans
        XCTAssertGreaterThanOrEqual(spans.count, 8)
        for (a, b) in zip(spans, spans.dropFirst()) {
            XCTAssertEqual(a.end, b.start, "bands must meet without overlapping")
            XCTAssertNotEqual(a.daylight, b.daylight, "night and daylight must alternate")
        }
        for d in days.dropLast() {
            let rise = try XCTUnwrap(d.sunrise)
            let daylight = try XCTUnwrap(spans.first { $0.daylight && $0.start == rise }, "\(d.start) has no daylight")
            let label = data.dayLabelTime(d)
            XCTAssertTrue(daylight.start < label && label < daylight.end, "\(d.start)'s name sits in the night")
        }
        let last = try XCTUnwrap(days.last)
        XCTAssertEqual(data.dayLabelTime(last), noonLocal(last.start, tz),
                       "a daylight with no following sunset centres the name on noon")
    }

    /// Day chrome draws every day the strip touches, and nothing else draws a
    /// snap stop. The filter behind `drawDayChrome` was a literal `offset <= 5`
    /// left over from the 132h strip: days 6 and 7 of the week drew no night
    /// band, no tint, no label and no sun dots, while their sun events stayed
    /// in `snapTimes` — the magnet parked the centerline on a sunrise drawn
    /// nowhere, silently. So this asserts the RELATIONSHIP to the window, never
    /// The day band's edge is the next local midnight, not start + 86,400: on a
    /// DST transition the local day is 25 h (fall back) or 23 h (spring forward)
    /// and the duration bound misdraws the band by an hour (#62).
    func testDayEndIsExactAcrossDSTTransitions() {
        let tz = friday.tz  // America/Los_Angeles — both 2026 transitions
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        for (ymd, hours) in [((2026, 11, 1), 25.0), ((2026, 3, 8), 23.0)] {
            let anchor = cal.date(from: DateComponents(year: ymd.0, month: ymd.1, day: ymd.2))!
            let d = TimelineData.build(tide: friday, current: nil, now: anchor, anchor: anchor)
            let day = d.day(of: anchor)!
            XCTAssertEqual(day.start, anchor, "anchor must be the transition day's midnight")
            XCTAssertEqual(d.dayEnd(day).timeIntervalSince(day.start), hours * 3600,
                           "the \(ymd) local day is \(hours) hours")
        }
    }

    /// a literal offset range, and it must survive a change to `forwardHours`.
    func testVisibleDaysFollowTheWindowNotAFixedOffset() {
        let tz = friday.tz
        for anchor in [todayLocal(tz), addingDays(-7, to: todayLocal(tz), in: tz)] {
            let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: anchor)
            let visible = d.visibleDays
            let drawn = Set(visible.map(\.offset))
            XCTAssertFalse(drawn.isEmpty)

            // Drawn ⟺ the day overlaps the window. `days` is contiguous, so a
            // day ends where the next begins (exact across DST, unlike +86400).
            for day in d.days {
                let overlaps = day.start <= d.end && d.dayEnd(day) > d.start
                XCTAssertEqual(drawn.contains(day.offset), overlaps,
                               "day \(day.offset) (anchor \(anchor)): overlaps=\(overlaps), drawn=\(drawn.contains(day.offset))")
            }
            // No gap at either end: chrome opens on or before the window and
            // runs past its end.
            XCTAssert(visible.first!.start <= d.start)
            XCTAssert(visible.last!.start <= d.end)
            XCTAssert(d.dayEnd(visible.last!) >= d.end,
                      "the last drawn day must reach the end of the strip")
            // The original failure, stated directly: a day that draws nothing
            // must contribute no snap stop.
            for day in d.days where !drawn.contains(day.offset) {
                for t in [day.sunrise, day.sunset].compactMap({ $0 }) {
                    XCTAssertFalse(d.snapTimes.contains { abs($0.timeIntervalSince(t)) < 1 },
                                   "day \(day.offset) draws no chrome, so \(t) must not be a snap stop")
                }
            }
        }
    }

    /// The schedule window (the anchor's midnight → +7d) spans at least two
    /// local days of tide turns — the rolling multi-day list. Asked of
    /// `scheduleRange`, the one definition the list itself filters on; the
    /// hand-built `today ± hours` version here only agreed by accident of
    /// `anchor == today`.
    func testScheduleWindowSpansMultipleDays() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        let turns = d.tideExtremes.filter { d.scheduleRange.contains($0.time) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = d.tz
        let days = Set(turns.map { cal.startOfDay(for: $0.time) })
        XCTAssertGreaterThanOrEqual(days.count, 2)
    }

    /// One clock wherever a moment is printed, following the reader's locale.
    func testOneLocaleAwareClockAcrossTheApp() {
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        let american = Locale(identifier: "en_US")
        let french = Locale(identifier: "fr_FR")
        let korean = Locale(identifier: "ko_KR")
        cal.timeZone = utc
        func at(_ h: Int, _ m: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: h, minute: m))!
        }
        XCTAssertEqual(chartTime(at(7, 3), utc, locale: american), "7:03\u{202F}AM")
        XCTAssertEqual(cardTime(at(7, 3), utc, locale: american),
                       chartTime(at(7, 3), utc, locale: american),
                       "cards, readouts and charts print one clock")
        XCTAssertEqual(chartTime(at(16, 22), utc, locale: american), "4:22\u{202F}PM")
        XCTAssertEqual(chartTime(at(16, 22), utc, locale: french), "16:22")
        XCTAssertEqual(chartTime(at(16, 22), utc, locale: korean), "오후 4:22")
        XCTAssertEqual(shortWeekday(at(16, 22), utc, locale: french), "lun.")
    }

    func testLeadWhenUsesLocalizedDateAndClockOrder() {
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        cal.timeZone = utc
        func at(_ h: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: h, minute: 5))!
        }
        let american = Locale(identifier: "en_US")
        XCTAssertEqual(leadWhen(at(7), utc, locale: american), "Aug 10 · \u{2007}7:05\u{202F}AM")
        XCTAssertEqual(leadWhen(at(12), utc, locale: american), "Aug 10 · 12:05\u{202F}PM")
        XCTAssertEqual(leadWhen(at(7), utc, locale: american).count,
                       leadWhen(at(12), utc, locale: american).count,
                       "one width for every hour — the centered line must not shift")
        XCTAssertEqual(leadWhen(at(7), utc, locale: Locale(identifier: "fr_FR")),
                       "10 août · 07:05")
        XCTAssertTrue(leadWhen(at(7), utc, locale: Locale(identifier: "ko_KR"))
            .contains("오전 \u{2007}7:05"))
    }

    /// A programmatic move — a pill, return-to-now, a schedule row, a tap —
    /// rides the animated path so the curve eases under the centerline, except
    /// under Reduce Motion, where it lands directly. A source scan, not a
    /// behaviour test: the branch needs a live `UIAccessibility`, which this
    /// target cannot inject. The UI suite covers what a scrub actually does;
    /// this only guards the accessibility branch from being simplified away.
    ///
    /// The branch asks `landsInstantly`, which is the Reduce Motion question
    /// with `-uiTestQuiet` folded in, so `assertLandsInstantly` below keeps
    /// the name honest rather than letting the indirection hide its removal.
    func testExternalScrubHonoursReduceMotion() throws {
        let source = try repoSource("Slackwater/TimelineScrubber.swift")
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("func move(_ sv: UIScrollView, to target: Date") }),
              let end = lines[(start + 1)...].firstIndex(where: { $0.contains("syncGate(sv)") })
        else { return XCTFail("the move was not found — this tripwire needs retargeting") }
        let move = lines[start...end].joined(separator: "\n")
        assertLandsInstantlyAsksAboutReduceMotion(source)
        XCTAssertTrue(move.contains("landsInstantly"),
                      "the move must ask about Reduce Motion before animating")
        XCTAssertTrue(move.contains("sv.contentOffset = CGPoint(x: offset, y: 0)"),
                      "the direct landing sets the offset rather than riding to it")
        XCTAssertTrue(move.contains("animated: true"),
                      "and the ordinary path animates the travel")
    }

    /// A drag-end magnetic settle rides the standard scroll animation, except
    /// under Reduce Motion, where it parks on the target directly (scenario
    /// 11). The same source-scan shape as the jump tripwire above, for the
    /// same reason: `magnet` needs a live `UIScrollView` and `UIAccessibility`.
    func testDragEndMagnetHonoursReduceMotion() throws {
        let source = try repoSource("Slackwater/TimelineScrubber.swift")
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("private func magnet(_ sv: UIScrollView)") }),
              let end = lines[(start + 1)...].firstIndex(where: { $0.contains("animated: true") })
        else { return XCTFail("the magnet was not found — this tripwire needs retargeting") }
        let magnet = lines[start...end].joined(separator: "\n")
        assertLandsInstantlyAsksAboutReduceMotion(source)
        XCTAssertTrue(magnet.contains("landsInstantly"),
                      "the drag-end magnet must ask about Reduce Motion before animating")
        XCTAssertTrue(magnet.contains("move(sv, to: target, ride: false)"),
                      "the direct landing parks on the target itself")
    }

    /// Both tripwires above read `landsInstantly` rather than the flag itself,
    /// so they are only as good as what that name means. A scrubber that asks
    /// it but has quietly stopped asking about Reduce Motion is the exact
    /// regression they exist to catch.
    private func assertLandsInstantlyAsksAboutReduceMotion(_ source: String) {
        let lines = source.components(separatedBy: .newlines)
        guard let decl = lines.firstIndex(where: { $0.contains("private var landsInstantly: Bool") })
        else { return XCTFail("landsInstantly was not found — these tripwires need retargeting") }
        XCTAssertTrue(lines[decl...min(decl + 3, lines.count - 1)]
            .joined(separator: "\n").contains("UIAccessibility.isReduceMotionEnabled"),
                      "landsInstantly must still be the Reduce Motion question")
    }

    /// The chrome pills fade in once the scrub rests; under Reduce Motion the
    /// opacity flips with no animation (§ 15). SwiftUI's environment cannot be
    /// injected into a view body from this target, so a source scan guards
    /// every `settled` animation reading the environment flag.
    func testPillSettleFadeHonoursReduceMotion() throws {
        let source = try repoSource("Slackwater/TimelineScrubber.swift")
        let fades = source.components(separatedBy: .newlines)
            .filter { $0.contains(".animation(") && $0.contains("value: settled") }
        XCTAssertFalse(fades.isEmpty, "the settle fade was not found — this tripwire needs retargeting")
        for line in fades {
            XCTAssertTrue(line.contains("reduceMotion ? nil :"),
                          "a settle fade must not animate under Reduce Motion:\n\(line)")
        }
    }

    @MainActor func testCommentaryJumpSurvivesScrollFeedback() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = friday.tz
        let data = TimelineData.build(tide: friday, current: nil, now: now,
                                      anchor: calendar.startOfDay(for: now))
        let geo = TimelineGeo(data: data)
        var scrub = now.addingTimeInterval(-6 * 3600)
        func strip(_ token: Int) -> TimelineScrubber {
            let renderedTime = scrub
            return TimelineScrubber(data: data, geo: geo, imperial: true, speedUnit: "kn", now: now,
                                    scrubTime: Binding(get: { renderedTime }, set: { scrub = $0 }),
                                    jumpToken: token)
        }
        let host = UIHostingController(rootView: strip(0))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: geo.height))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        func scrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? TimelineScrubber.ScrubScrollView { return scroll }
            return view.subviews.compactMap { scrollView(in: $0) }.first
        }
        let sv = try XCTUnwrap(scrollView(in: host.view))
        let co = try XCTUnwrap(sv.delegate as? TimelineScrubber.Coordinator)
        let target = scrub.addingTimeInterval(2 * 3600)
        scrub = target
        host.rootView = strip(1)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let landing = co.magnetTarget
        XCTAssertTrue(co.magneting, "the commentary must still be travelling when feedback arrives")
        // A rendered scroll update can trail the offset while the jump animates.
        scrub = data.time(atX: sv.contentOffset.x + sv.bounds.width / 2).addingTimeInterval(-600)
        host.rootView = strip(1)
        host.view.layoutIfNeeded()
        for _ in 0..<100 where co.magneting {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(landing, target, "scroll feedback must not replace the tapped destination")
        XCTAssertEqual(scrub.timeIntervalSince(target), 0, accuracy: 1,
                       "the commentary jump must finish on its destination despite scroll feedback")
        XCTAssertEqual(data.time(atX: sv.contentOffset.x + sv.bounds.width / 2).timeIntervalSince(target),
                       0, accuracy: 300, "the curve must finish under the same selected time")
    }

    @MainActor func testTheCanvasLeavesTouchesToTheNativeScrollView() throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now,
                                      anchor: dayLocal(now, friday.tz))
        let strip = TimelineScrubber(data: data, geo: TimelineGeo(data: data),
                                     imperial: true, speedUnit: "kn", now: now,
                                     scrubTime: .constant(now))
        let host = UIHostingController(rootView: strip)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: strip.geo.height))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        func scrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? TimelineScrubber.ScrubScrollView { return scroll }
            return view.subviews.compactMap { scrollView(in: $0) }.first
        }
        let sv = try XCTUnwrap(scrollView(in: host.view))
        let point = CGPoint(x: sv.bounds.midX, y: sv.bounds.midY)
        XCTAssertTrue(sv.hitTest(point, with: nil) === sv,
                      "the decorative canvas must not receive the scroll view's touches")
    }

    /// The host's state, which the strip's own writes land in, as SwiftUI's would.
    private final class Selection {
        var time: Date
        init(_ time: Date) { self.time = time }
    }

    /// What the scaffold hands the strip for alerts: closures while it has an offer, nil without one.
    private final class AlertHost {
        var offered: Bool
        var presses = 0
        var actions = 0
        init(offered: Bool) { self.offered = offered }
    }

    /// In a window, so its animated scrolls run.
    private func mountedStrip(_ data: TimelineData, _ sel: Selection, now: Date,
                              gate: ScrollGate? = nil, opening: Bool = false, pills: [CGRect] = [],
                              alerts: AlertHost? = nil, onPickDate: @escaping () -> Void = {},
                              scrollView: (CGRect) -> UIScrollView = { TimelineScrubber.ScrubScrollView(frame: $0) })
        -> (window: UIWindow, sv: UIScrollView, co: TimelineScrubber.Coordinator, strip: (Int) -> TimelineScrubber) {
        let geo = TimelineGeo(data: data)
        let strip = { (token: Int) in
            TimelineScrubber(data: data, geo: geo, imperial: true, speedUnit: "kn", now: now,
                             scrubTime: Binding(get: { sel.time }, set: { sel.time = $0 }),
                             jumpToken: token, scrollGate: gate, onPickDate: onPickDate,
                             onLongPress: alerts.flatMap { host in host.offered ? { host.presses += 1 } : nil },
                             onAlertAction: alerts.flatMap { host in host.offered ? { host.actions += 1 } : nil },
                             restingPills: pills)
        }
        let co = TimelineScrubber.Coordinator(strip(0))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: geo.height))
        let sv = scrollView(window.bounds)
        sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
        sv.bounces = false
        sv.delegate = co
        window.addSubview(sv)
        window.isHidden = false
        co.centerIfNeeded(sv, animated: opening)
        return (window, sv, co, strip)
    }

    private func settle(_ co: TimelineScrubber.Coordinator) async throws {
        for _ in 0..<150 where co.magneting || co.nudging { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(20))
    }

    /// A rest a hair off a stop reads the stop's own time without a redundant animation.
    func testADragEndingWithinHalfAUnitOfAStopLandsOnItExactly() throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let stop = try XCTUnwrap(data.snapTimes.first { $0 > now.addingTimeInterval(12 * 3600) })
        let sel = Selection(stop.addingTimeInterval(0.2 * 3600 / Double(Timeline.pph)))
        let m = mountedStrip(data, sel, now: now)
        defer { m.window.isHidden = true }
        let offset = m.sv.contentOffset.x
        m.co.scrollViewWillBeginDragging(m.sv)
        m.co.scrollViewDidEndDragging(m.sv, willDecelerate: false)
        XCTAssertEqual(sel.time, stop, "the magnet lands on the stop's own instant")
        XCTAssertEqual(m.sv.contentOffset.x, offset, "and moves nothing to get there")
        XCTAssertFalse(m.co.magneting)
    }

    /// The newest request wins, or a schedule row tapped mid-ride would be dropped.
    func testAHostSelectionDuringARideOrTheOpeningWins() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))

        let sel = Selection(now.addingTimeInterval(-6 * 3600))
        let m = mountedStrip(data, sel, now: now)
        defer { m.window.isHidden = true }
        let first = now.addingTimeInterval(-3 * 3600)
        sel.time = first
        m.strip(1).updateUIView(m.sv, coordinator: m.co)
        XCTAssertTrue(m.co.magneting, "a commentary request rides")
        XCTAssertEqual(m.co.magnetTarget, first)
        let second = now.addingTimeInterval(4 * 3600)
        sel.time = second
        m.strip(2).updateUIView(m.sv, coordinator: m.co)
        XCTAssertEqual(m.co.magnetTarget, second, "a schedule row mid-ride replaces the ride's destination")
        try await settle(m.co)
        XCTAssertEqual(sel.time, second)
        XCTAssertEqual(data.time(atX: m.sv.contentOffset.x + m.sv.bounds.width / 2).timeIntervalSince(second),
                       0, accuracy: 300)
        // A time set without a request only resyncs a quiet strip, directly.
        let unasked = second.addingTimeInterval(3600)
        sel.time = unasked
        m.strip(2).updateUIView(m.sv, coordinator: m.co)
        XCTAssertFalse(m.co.magneting, "only a request rides")
        XCTAssertEqual(data.time(atX: m.sv.contentOffset.x + m.sv.bounds.width / 2).timeIntervalSince(unasked),
                       0, accuracy: 300)

        let opening = Selection(Timeline.introStart(for: now))
        let o = mountedStrip(data, opening, now: now, opening: true)
        defer { o.window.isHidden = true; o.co.stopIntro() }
        XCTAssertNotNil(o.co.introDisplayLink, "the opening is running")
        let linked = now.addingTimeInterval(9 * 3600)
        opening.time = linked
        o.strip(1).updateUIView(o.sv, coordinator: o.co)
        XCTAssertNil(o.co.introDisplayLink, "a shared link stops the opening")
        try await settle(o.co)
        XCTAssertEqual(opening.time, linked)
    }

    /// A finger still down keeps control: a request under it moving the strip, or the drag's momentum outliving it, would fight the finger or overwrite the request.
    func testARequestDuringADragWaitsForTheLiftAndReplacesMomentum() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let sel = Selection(now)
        let held = HeldScrollView(frame: .zero)
        let m = mountedStrip(data, sel, now: now, scrollView: { held.frame = $0; return held })
        defer { m.window.isHidden = true }

        m.co.scrollViewWillBeginDragging(m.sv)
        held.fingerDown = true
        m.sv.contentOffset.x -= 60
        let grabbed = m.sv.contentOffset
        let first = now.addingTimeInterval(4 * 3600)
        sel.time = first
        m.strip(1).updateUIView(m.sv, coordinator: m.co)
        XCTAssertEqual(m.co.pendingTarget, first, "the request waits for the finger")
        XCTAssertFalse(m.co.magneting, "nothing rides under a finger")
        XCTAssertEqual(m.sv.contentOffset, grabbed, "the strip stays where the finger holds it")
        let second = now.addingTimeInterval(7 * 3600)
        sel.time = second
        m.strip(2).updateUIView(m.sv, coordinator: m.co)
        XCTAssertEqual(m.co.pendingTarget, second, "a newer request replaces a waiting one")
        XCTAssertEqual(m.sv.contentOffset, grabbed)

        var momentum = CGPoint(x: grabbed.x - 900, y: 0)
        m.co.scrollViewWillEndDragging(m.sv, withVelocity: CGPoint(x: -3, y: 0), targetContentOffset: &momentum)
        XCTAssertEqual(momentum, grabbed, "the lift's fling is cancelled in favour of the request")
        held.fingerDown = false
        m.co.scrollViewDidEndDragging(m.sv, willDecelerate: false)
        XCTAssertNil(m.co.pendingTarget)
        XCTAssertTrue(m.co.magneting, "the waiting request rides once the finger lifts")
        XCTAssertEqual(m.co.magnetTarget, second)
        try await settle(m.co)
        XCTAssertEqual(sel.time, second)
        XCTAssertEqual(data.time(atX: m.sv.contentOffset.x + m.sv.bounds.width / 2).timeIntervalSince(second),
                       0, accuracy: 300)
    }

    /// `isDragging` follows a real pan only; this one says a finger is down when told to.
    private final class HeldScrollView: UIScrollView {
        var fingerDown = false
        override var isDragging: Bool { fingerDown }
    }

    /// An unreachable target would leave the reading disagreeing with the curve under the line.
    func testAnExternalSelectionPastTheEdgeIsClampedAndReadBack() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let sel = Selection(data.start.addingTimeInterval(30 * 3600))
        let m = mountedStrip(data, sel, now: now)
        defer { m.window.isHidden = true }
        let reachable = data.time(atX: m.sv.bounds.width / 2)
        sel.time = data.start.addingTimeInterval(-2 * 3600)
        m.strip(1).updateUIView(m.sv, coordinator: m.co)
        if m.co.magneting { XCTAssertEqual(m.co.magnetTarget, reachable, "the ride heads for the edge, not past it") }
        try await settle(m.co)
        XCTAssertEqual(m.sv.contentOffset.x, 0, accuracy: 0.5)
        XCTAssertEqual(sel.time, reachable, "the reading is the reachable time, not the request")

        // The far end, with nothing to ride: a direct landing reads back too.
        m.co.move(m.sv, to: data.end.addingTimeInterval(3600), ride: false)
        XCTAssertEqual(sel.time, data.time(atX: data.totalWidth - m.sv.bounds.width / 2))
    }

    /// One touch on a resting pill reaches the strip's tap recognizer too; scrubbing to the tapped instant would overwrite the pill's request.
    func testATapOnARestingPillLeavesThePillsRequestStanding() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let pill = CGRect(x: 140, y: 124, width: 120, height: Timeline.pillTarget)
        let sel = Selection(now)
        let m = mountedStrip(data, sel, now: now, pills: [pill])
        defer { m.window.isHidden = true }
        let target = now.addingTimeInterval(2 * 3600)
        // The pill's action runs first, then the strip's tap for the same touch.
        sel.time = target
        m.co.tap(m.sv, at: CGPoint(x: m.sv.contentOffset.x + pill.midX, y: pill.midY))
        XCTAssertEqual(sel.time, target, "the strip's tap must leave the pill's selection alone")
        m.strip(1).updateUIView(m.sv, coordinator: m.co)
        try await settle(m.co)
        XCTAssertEqual(sel.time, target)
        XCTAssertEqual(data.time(atX: m.sv.contentOffset.x + m.sv.bounds.width / 2).timeIntervalSince(target),
                       0, accuracy: 300, "the strip moves to the stop the pill names")

        // Off the pill, the same tap scrubs as ever.
        m.co.tap(m.sv, at: CGPoint(x: m.sv.contentOffset.x + 20, y: pill.midY))
        try await settle(m.co)
        XCTAssertLessThan(sel.time, target, "a tap left of the pill brings an earlier moment to the line")
    }

    /// A press held on a resting pill would park a moment, buzz, and name it in the alert line before the pill's button fires.
    func testAPressOnARestingPillNeverReachesTheStrip() throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let pill = CGRect(x: 140, y: 124, width: 120, height: Timeline.pillTarget)
        let m = mountedStrip(data, Selection(now), now: now, pills: [pill], alerts: AlertHost(offered: true))
        defer { m.window.isHidden = true }
        m.strip(0).updateUIView(m.sv, coordinator: m.co)
        let press = try XCTUnwrap(m.co.pressRecognizer)
        let tap = try XCTUnwrap(m.co.tapRecognizer)
        let onPill = PlacedTouch(CGPoint(x: m.sv.contentOffset.x + pill.midX, y: pill.midY))
        let offPill = PlacedTouch(CGPoint(x: m.sv.contentOffset.x + 20, y: pill.midY))
        // UIKit asks the delegate, and a recognizer without one receives every touch.
        func receives(_ g: UIGestureRecognizer, _ t: UITouch) -> Bool { g.delegate?.gestureRecognizer?(g, shouldReceive: t) ?? true }
        for (name, g) in [("press", press as UIGestureRecognizer), ("tap", tap)] {
            XCTAssertFalse(receives(g, onPill), "the \(name) must leave a resting pill's touch to the pill")
            XCTAssertTrue(receives(g, offPill), "off the pill, the \(name) acts on the strip as ever")
        }
    }

    private final class PlacedTouch: UITouch {
        let point: CGPoint
        init(_ point: CGPoint) { self.point = point; super.init() }
        override func location(in view: UIView?) -> CGPoint { point }
    }

    /// A host with nothing to alert on gets no press and no "Set an alert"; a preview's model landing adds both under the same strip.
    func testThePressAndItsActionFollowTheHostsAlertOffer() throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let host = AlertHost(offered: false)
        let m = mountedStrip(data, Selection(now), now: now, alerts: host)
        defer { m.window.isHidden = true }
        // UIScrollView brings long presses of its own; count the strip's against them.
        func presses() -> Int { (m.sv.gestureRecognizers ?? []).filter { $0 is UILongPressGestureRecognizer }.count }
        func actionNames() -> [String] { (m.sv.accessibilityCustomActions ?? []).map(\.name) }

        m.strip(0).updateUIView(m.sv, coordinator: m.co)
        let builtIn = presses()
        XCTAssertNil(m.co.pressRecognizer, "no alert offer, no press recognizer")
        let plainTap = try XCTUnwrap(m.co.tapRecognizer, "every strip taps")
        XCTAssertTrue(m.sv.gestureRecognizers?.contains(plainTap) ?? false)
        XCTAssertEqual(actionNames(), ["Next event", "Previous event"], "no alert offer, no Set an alert")

        host.offered = true
        m.strip(0).updateUIView(m.sv, coordinator: m.co)
        let press = try XCTUnwrap(m.co.pressRecognizer, "the offer arriving installs the press")
        XCTAssertTrue(m.sv.gestureRecognizers?.contains(press) ?? false)
        XCTAssertEqual(presses(), builtIn + 1)
        let waitingTap = try XCTUnwrap(m.co.tapRecognizer)
        XCTAssertFalse(waitingTap === plainTap, "the tap that waits for the press replaces the one that did not")
        XCTAssertFalse(m.sv.gestureRecognizers?.contains(plainTap) ?? true)
        XCTAssertEqual(actionNames(), ["Next event", "Previous event", "Set an alert"])
        let action = try XCTUnwrap(m.sv.accessibilityCustomActions?.last)
        XCTAssertTrue(action.actionHandler?(action) ?? false)
        XCTAssertEqual(host.actions, 1, "the action reaches the host")
        m.strip(0).updateUIView(m.sv, coordinator: m.co)
        XCTAssertEqual(presses(), builtIn + 1, "an update does not stack a second press")
        XCTAssertTrue(m.co.tapRecognizer === waitingTap, "nor rebuild an unchanged tap")

        host.offered = false
        m.strip(0).updateUIView(m.sv, coordinator: m.co)
        XCTAssertNil(m.co.pressRecognizer, "the offer leaving removes the press")
        XCTAssertFalse(m.sv.gestureRecognizers?.contains(press) ?? false)
        XCTAssertEqual(presses(), builtIn)
        XCTAssertFalse(m.co.tapRecognizer === waitingTap, "a fresh tap no longer waits on it")
        XCTAssertFalse(m.sv.gestureRecognizers?.contains(waitingTap) ?? true)
        XCTAssertEqual(actionNames(), ["Next event", "Previous event"])
    }

    /// A date tap lands where the date is drawn, on the daylight midpoint, not at clock noon.
    func testADateTapLandsWhereTheDateIsDrawn() throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let geo = TimelineGeo(data: data)
        let day = try XCTUnwrap(data.visibleDays.first { d in
            d.sunset != nil && data.x(data.dayLabelTime(d)) - data.x(noonLocal(d.start, data.tz)) > 8
        }, "no day here draws its date clear of noon: the fixture proves nothing")
        let label = data.x(data.dayLabelTime(day))
        let sunset = data.x(try XCTUnwrap(day.sunset))
        let noon = data.x(noonLocal(day.start, data.tz))
        // Nearer the drawn date than the sunset, but nearer the sunset than noon.
        let x = (label + sunset) / 2 - 2
        XCTAssertGreaterThan(x - noon, sunset - x, "the tap must sit where a noon anchor would lose to the sunset")
        var picked = 0
        let sel = Selection(now)
        let m = mountedStrip(data, sel, now: now, onPickDate: { picked += 1 })
        defer { m.window.isHidden = true }
        let before = sel.time
        m.co.tap(m.sv, at: CGPoint(x: x, y: geo.dayY + 17))
        XCTAssertEqual(picked, 1, "a tap nearer the drawn date opens the picker")
        XCTAssertEqual(sel.time, before, "and moves nothing")
        XCTAssertFalse(m.co.magneting)
    }

    func testTappingTheBottomOfAPeakTimeSelectsThePeak() async throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let h = { (hours: Double) in start.addingTimeInterval(hours * 3600) }
        let peak = h(12), now = h(8)
        let day = TimelineDay(offset: 0, start: start, sunrise: h(6), sunset: h(18), moonrise: nil, moonset: nil)
        let data = TimelineData(tz: .gmt, anchor: start, today: start, start: start, end: h(24), days: [day],
                                tidePoints: [], tideRates: [], tideExtremes: [],
                                currentPoints: [CurrentPoint(time: start, speed: 1), CurrentPoint(time: h(24), speed: 1)],
                                currentEvents: [CurrentEvent(time: peak, speed: 1, kind: .maxFlood)],
                                snapTimes: [peak], slackWindows: [])
        var picked = 0
        let selection = Selection(now)
        let m = mountedStrip(data, selection, now: now, onPickDate: { picked += 1 })
        defer { m.window.isHidden = true }
        m.co.tap(m.sv, at: CGPoint(x: data.x(peak), y: TimelineGeo(data: data).peakTimeY + 5))
        try await settle(m.co)
        XCTAssertEqual(picked, 0)
        XCTAssertEqual(selection.time.timeIntervalSince(peak), 0, accuracy: 1)
    }

    /// A left-edge publish mid-ride would move the origin under the animation.
    func testATapRideMarksTheStoreBusy() async throws {
        let now = Date(timeIntervalSince1970: 1788868800)
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: dayLocal(now, friday.tz))
        let gate = ScrollGate()
        let sel = Selection(now)
        let m = mountedStrip(data, sel, now: now, gate: gate)
        defer { m.window.isHidden = true }
        let geo = TimelineGeo(data: data)
        m.co.tap(m.sv, at: CGPoint(x: m.sv.contentOffset.x + 380, y: geo.bodyTop + 20))
        XCTAssertTrue(m.co.magneting, "a tap across most of the viewport rides")
        XCTAssertFalse(gate.isQuiet, "the ride holds the store's left edge")
        try await settle(m.co)
        XCTAssertTrue(gate.isQuiet, "and releases it on landing")
    }

    /// #280: rotation keeps `contentOffset.x` while the viewport width
    /// changes, so the time under the centerline (`offset + width / 2`)
    /// drifts by half the width change and the curve disagrees with the
    /// readout. The coordinator's layout hook must put `scrubTime` back under
    /// the centerline without touching `scrubTime` itself or re-running the
    /// opening centre. A real `UIScrollView` driven through `layoutIfNeeded`,
    /// the same path a rotation takes.
    func testWidthChangeKeepsScrubTimeUnderTheCenterline() {
        let now = Date()
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: todayLocal(friday.tz))
        let geo = TimelineGeo(data: data)
        // Six hours back: not the intro start, so no opening slide.
        let parked = now.addingTimeInterval(-6 * 3600)
        var scrub = parked
        let scrubber = TimelineScrubber(data: data, geo: geo, imperial: true, speedUnit: "kn", now: now,
                                        scrubTime: Binding(get: { scrub }, set: { scrub = $0 }))
        let co = TimelineScrubber.Coordinator(scrubber)
        let sv = TimelineScrubber.ScrubScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: geo.height))
        sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
        sv.delegate = co
        sv.onLayout = { [weak sv] in if let sv { co.layoutDidRun(sv) } }
        sv.layoutIfNeeded()
        func centre() -> TimeInterval {
            data.time(atX: sv.contentOffset.x + sv.bounds.width / 2).timeIntervalSince(parked)
        }
        XCTAssertTrue(co.didInitialCenter)
        XCTAssertEqual(centre(), 0, accuracy: 300, "opening centre missed the parked time")

        for width in [CGFloat(800), 400, 1194] {
            sv.frame.size.width = width
            sv.layoutIfNeeded()
            XCTAssertEqual(centre(), 0, accuracy: 300,
                           "at \(width)pt the curve under the centerline left the readout")
            XCTAssertEqual(scrub, parked, "re-anchoring must not rewrite scrubTime from layout")
            XCTAssertTrue(co.didInitialCenter, "a resize must not restart the opening centre")
        }
    }

    /// The strip is one adjustable VoiceOver control (spec § 15): a swipe up
    /// or down moves five minutes, the custom actions jump to the next or
    /// previous magnetic target, and the value speaks a dated station-local
    /// time rather than a bare clock. The same real `UIScrollView` as above.
    func testStripIsAnAdjustableControlSteppingFiveMinutes() throws {
        let now = Date()
        let data = TimelineData.build(tide: friday, current: nil, now: now, anchor: todayLocal(friday.tz))
        let geo = TimelineGeo(data: data)
        let parked = now.addingTimeInterval(-6 * 3600)
        var scrub = parked
        let scrubber = TimelineScrubber(data: data, geo: geo, imperial: true, speedUnit: "kn", now: now,
                                        scrubTime: Binding(get: { scrub }, set: { scrub = $0 }),
                                        spokenLead: "Rising 2.3 feet")
        let co = TimelineScrubber.Coordinator(scrubber)
        let sv = TimelineScrubber.ScrubScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: geo.height))
        sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
        sv.delegate = co
        sv.onLayout = { [weak sv] in if let sv { co.layoutDidRun(sv) } }
        sv.layoutIfNeeded()
        func centre() -> Date { data.time(atX: sv.contentOffset.x + sv.bounds.width / 2) }

        XCTAssertTrue(sv.isAccessibilityElement)
        XCTAssertTrue(sv.accessibilityTraits.contains(.adjustable))
        XCTAssertEqual(sv.accessibilityLabel, "Tide timeline")
        // The spoken time is the pixel-rounded centre, not the exact scrub.
        XCTAssertEqual(sv.accessibilityValue, "Rising 2.3 feet, " + spokenWhen(centre(), data.tz))

        sv.accessibilityIncrement()
        XCTAssertEqual(scrub.timeIntervalSince(parked), 300, accuracy: 1)
        XCTAssertEqual(centre().timeIntervalSince(scrub), 0, accuracy: 60, "the curve follows the step")
        sv.accessibilityDecrement()
        XCTAssertEqual(scrub.timeIntervalSince(parked), 0, accuracy: 1)

        let actions = try XCTUnwrap(sv.accessibilityCustomActions)
        XCTAssertEqual(actions.map(\.name), ["Next event", "Previous event"])
        let next = try XCTUnwrap(data.snapTimes.first { $0 > parked.addingTimeInterval(1) })
        XCTAssertTrue(actions[0].actionHandler?(actions[0]) ?? false)
        XCTAssertEqual(scrub, next, "the next-event action parks exactly on the target")
        XCTAssertTrue(actions[1].actionHandler?(actions[1]) ?? false)
        XCTAssertLessThan(scrub, next, "and the previous-event action walks back off it")
    }

    func testSpokenWhenIsLocalizedDatedAndZoned() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        let t = formatter("yyyy-MM-dd HH:mm", tz).date(from: "2026-09-20 16:22")!
        XCTAssertEqual(spokenWhen(t, tz, locale: Locale(identifier: "en_US")),
                       "September 20 at 4:22\u{202F}PM PDT")
        XCTAssertEqual(spokenWhen(t, tz, locale: Locale(identifier: "fr_FR")),
                       "20 septembre à 16:22 UTC−7")
    }

    /// The pad over the plot grows with the lead's text size (spec § 15), and
    /// everything under it — plot, chrome rows, the strip's height — moves
    /// down by the same amount rather than being overprinted.
    func testALargerPadMovesThePlotDownIntact() {
        let data = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        let base = TimelineGeo(data: data, padTop: 160)
        let large = TimelineGeo(data: data, padTop: 200)
        XCTAssertEqual(base.tideTop, 170)
        XCTAssertEqual(large.tideTop, 210)
        XCTAssertEqual(large.tideBottom - large.tideTop, base.tideBottom - base.tideTop, "the plot box keeps its size")
        XCTAssertEqual(large.chromeY, 164)
        XCTAssertEqual(large.height - base.height, 40)
        XCTAssertGreaterThanOrEqual(TimelineGeo.scaledPadTop, 160, "the pad never shrinks below the reference")
    }

    /// The axis row's crowding rule, on its own. Two times a label's width
    /// apart both print; closer than that, the LATER one is dropped — the
    /// schedule below still lists it. Order-independent, because the callers
    /// hand this whatever order their events came out in.
    func testAxisTimesDropTheLaterOfACrowdedPair() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let close = t0.addingTimeInterval(2400)      // 40pt at 60pt/hour
        let clear = t0.addingTimeInterval(4200)      // 70pt
        let x = { (t: Date) -> CGFloat in CGFloat(t.timeIntervalSince(t0)) / 60 }

        XCTAssertEqual(thinnedAxisTimes([t0, close], x: x, minGap: 64), [t0],
                       "40pt apart, the later label is dropped")
        XCTAssertEqual(thinnedAxisTimes([t0, clear], x: x, minGap: 64), [t0, clear],
                       "70pt apart, both print")
        XCTAssertEqual(thinnedAxisTimes([close, t0], x: x, minGap: 64), [t0],
                       "the earlier time survives whichever order it arrives in")
        XCTAssertEqual(thinnedAxisTimes([clear, t0], x: x, minGap: 64), [t0, clear],
                       "and the output is always in time order")
    }

    /// EVERY time the strip prints must be a time the strip can stop on.
    ///
    /// The magnet snaps to `snapTimes`, so a label showing anything else puts a
    /// number on screen that the scrubber will never park you at. The slack
    /// label printed its WINDOW'S OPENING EDGE for one iteration and that edge
    /// is not a snap stop — you read one time, let go, and landed eight minutes later
    /// with nothing explaining the gap.
    ///
    /// Window edges are labelled as the start/end of the usable window, so
    /// they need to be valid stops too.
    func testEveryLabelledTimeIsSomethingTheMagnetCanStopOn() throws {
        // The comfort current is shared App Group state; Off would leave no windows to test.
        let saved = AppGroup.defaults.object(forKey: AppGroup.slackWindowSpeedKey)
        defer { AppGroup.defaults.set(saved, forKey: AppGroup.slackWindowSpeedKey) }
        AppGroup.defaults.set(0.5, forKey: AppGroup.slackWindowSpeedKey)
        let victoria = CurrentStationRecord.all.first { !$0.isChs } ?? CurrentStationRecord.all[0]
        let d = TimelineData.build(tide: nil, current: victoria, now: Date(), anchor: todayLocal(victoria.tz))
        let stops = Set(d.snapTimes)
        XCTAssertFalse(stops.isEmpty, "no snap stops — the rest of this proves nothing")

        // A slack inside a core drawn as a dot is the dot's stop, its centre.
        let dots = d.coreRuns.filter(\.isDot)
        let slacks = d.currentEvents.filter { e in
            e.kind == .slack && e.time >= d.start && e.time <= d.end && !dots.contains { $0.contains(e.time) }
        }
        XCTAssertFalse(slacks.isEmpty, "no slacks at this station — pick another fixture")
        for e in slacks {
            XCTAssert(stops.contains(e.time),
                      "the strip labels slack at \(e.time) but the magnet cannot stop there")
        }
        // Maxes are labelled too, and they are snap stops for the same reason.
        for e in d.currentEvents where e.kind != .slack && e.time >= d.start && e.time <= d.end
            && !dots.contains(where: { $0.contains(e.time) }) {
            XCTAssert(stops.contains(e.time),
                      "the strip labels a max at \(e.time) but the magnet cannot stop there")
        }

        let runs = d.windowRuns.filter { $0.start >= d.start && $0.end <= d.end && !$0.isDot }
        XCTAssertFalse(runs.isEmpty, "no windows at this station — pick another fixture")
        for run in runs {
            for moment in run.snapMoments { XCTAssert(stops.contains(moment)) }
        }
        for run in d.coreRuns where run.start >= d.start && run.end <= d.end {
            for moment in run.snapMoments { XCTAssert(stops.contains(moment)) }
        }
        for t in d.slackAxisTimes where t >= d.start && t <= d.end {
            XCTAssert(stops.contains(t), "the strip prints \(t) but the magnet cannot stop there")
        }
    }

    func testComfortCurrentChangesOnlyTheWindowAroundZero() throws {
        let station = try XCTUnwrap(CurrentStationRecord.all.first)
        let now = Date(), anchor = todayLocal(station.tz)
        for threshold in [0.0, 0.1, 1] {
            let d = TimelineData.build(tide: nil, current: station, now: now,
                                       anchor: anchor, threshold: threshold)
            let slacks = d.currentEvents.filter { $0.kind == .slack && d.contains($0.time) }.map(\.time)
            XCTAssertFalse(slacks.isEmpty)
            XCTAssertTrue(d.slackCores.isEmpty)
            XCTAssertEqual(d.slackWindows.isEmpty, threshold == 0)
            for slack in slacks {
                XCTAssertTrue(d.isSlack(at: slack))
                XCTAssertFalse(d.isSlack(at: slack.addingTimeInterval(30)))
                XCTAssertTrue(d.snapTimes.contains(slack))
            }
        }
    }

    /// Two single-track geometries, no combined case (split-scrubbers spec §1/§2).
    func testSingleTrackGeometries() {
        let tideData = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        let tide = TimelineGeo(data: tideData)
        XCTAssert(tide.hasTide && !tide.hasCurrent)
        // One plot box for either track (card-look spec §2): the readings
        // live on the curve and one time row under it, so there is nothing
        // left to size differently. Asserted as structure, not pixels.
        XCTAssertEqual(tide.bodyTop, tide.tideTop)
        XCTAssertEqual(tide.bodyBottom, tide.tideBottom)
        // Chrome reads downward under the curve — time row, day label and sun
        // times, then the moon disc — and the canvas ends a moon's radius
        // past the last of them. The card graph's order, asserted as ordering
        // rather than as the pixel each row happens to sit on.
        XCTAssertGreaterThan(tide.timeY, tide.bodyBottom, "the time row sits under the plot")
        XCTAssertGreaterThan(tide.dayY, tide.timeY, "the day row sits under the times")
        XCTAssertGreaterThan(tide.sunY, tide.dayY, "sun times sit under the day label")
        XCTAssertGreaterThan(tide.sunY - (tide.dayY + 17), 12, "sun times clear the date on short days")
        XCTAssertGreaterThan(tide.eclipseY, tide.sunY, "eclipses clear the sun times")
        XCTAssertEqual(tide.height, tide.eclipseY + 18, "the canvas ends below the moon disc")
        // The lead and its pill row own the pad above the plot: the row's top
        // plus a pill's height has to land inside it, or a pill overlaps the
        // curve it floats above.
        XCTAssertLessThanOrEqual(tide.chromeY + 30, tide.padTop, "the pill row clears the plot's pad")

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cur = TimelineGeo(data: TimelineData(
            tz: .current, anchor: t0, today: t0, start: t0, end: t0.addingTimeInterval(3600),
            days: [], tidePoints: [], tideRates: [], tideExtremes: [],
            currentPoints: [CurrentPoint(time: t0, speed: 1)], currentEvents: [],
            snapTimes: [], slackWindows: []))
        XCTAssert(!cur.hasTide && cur.hasCurrent)
        XCTAssertEqual(cur.bodyTop, cur.curTop)
        XCTAssertEqual(cur.bodyBottom, cur.curBottom)
        XCTAssertEqual(cur.height, tide.height, "a current with no maxima needs no peak-time row")
        XCTAssertFalse(cur.hasPeakTimes)
        XCTAssertEqual(cur.curTop, tide.tideTop, "same plot box for both tracks")
        XCTAssertEqual(cur.curBottom, tide.tideBottom)
        XCTAssertEqual(cur.timeY, tide.timeY)

        // Both arrays non-empty: pins that no case (true, true) exists to claim
        // it — resurrecting the deleted combined arm ahead of `case (true, _)`
        // would go uncaught otherwise. TidePoint has no public init outside
        // SlackwaterKit, so the tide side is real data borrowed from the tide-only
        // build above; only the current side is synthesized.
        let both = TimelineGeo(data: TimelineData(
            tz: tideData.tz, anchor: tideData.anchor, today: tideData.today, start: tideData.start, end: tideData.end,
            days: tideData.days, tidePoints: tideData.tidePoints, tideRates: tideData.tideRates,
            tideExtremes: tideData.tideExtremes,
            currentPoints: [CurrentPoint(time: tideData.start, speed: 1)], currentEvents: [],
            snapTimes: tideData.snapTimes, slackWindows: []))
        XCTAssert(both.hasTide && both.hasCurrent)
        XCTAssertEqual(both.height, tide.height,
                       "combined input resolves tide-first — no combined case exists (spec §1/§2)")
        XCTAssertEqual(both.curTop, 0)
    }

    /// Both surfaces draw the tide through the shared helpers: the fill
    /// anchored at chart datum and the line coloured by the tide-rate ramp,
    /// with no chevron glyphs. A source scan, because what it guards is a
    /// surface quietly growing its own fill again.
    func testTideTracksShareTheDatumFillAndRateColouredLine() throws {
        for (file, from, to) in [("Slackwater/TimelineStrip.swift", "private func drawTide(", "private func deg("),
                                 ("Slackwater/StationCardGraph.swift", "var body: some View {", "func cardWindows(")] {
            let lines = try repoSource(file).components(separatedBy: .newlines)
            guard let start = lines.firstIndex(where: { $0.contains(from) }),
                  let end = lines[(start + 1)...].firstIndex(where: { $0.contains(to) })
            else { return XCTFail("\(file): tide drawing not found") }
            let body = lines[start..<end].joined(separator: "\n")
            XCTAssertTrue(body.contains("CurveDrawing.datumFill("), "\(file): the tide fill is the shared datum fill")
            XCTAssertTrue(body.contains("CurveDrawing.tideLine("), "\(file): the stroke takes its colour from the tide-rate ramp")
            XCTAssertFalse(body.contains("››››"), "\(file): chevrons are gone; the line carries the rate")
            XCTAssertFalse(body.contains("Gradient("), "\(file): no fill or stroke gradient of its own")
            // The strip fills only below datum; the card, and the widgets and
            // complications that draw it, keep the blue above datum.
            XCTAssertEqual(body.contains("fillsAboveDatum: false"), file.hasSuffix("TimelineStrip.swift"),
                           "\(file): only the strip leaves the water above datum unfilled")
        }
        // Both hues vanish on the datum line, so a low under datum reads as
        // less water than the chart shows with no seam at the crossing. Two
        // stops at the same location is what makes that edge invisible;
        // either one alone puts a hard line across the fill.
        let helpers = try repoSource("Slackwater/CurveDrawing.swift")
        XCTAssertTrue(helpers.contains("SN.graphLine.opacity(CurveStyle.fillOpacity), location: 0"), "blue at the top")
        XCTAssertTrue(helpers.contains("SN.graphLine.opacity(0), location: fadeStop"), "fading out at datum or the lowest trough")
        XCTAssertTrue(helpers.contains("SN.graphLow.opacity(0), location: fadeStop"), "the below-datum hue fades in from the same line")
    }

    /// A station whose whole day is below chart datum (Tesoro Marine
    /// Terminal, −0.8 to −0.2 ft) puts datum above the plot. The amber there
    /// covered all the sky over the curve and was cut off by the plot's top
    /// edge, so neither surface draws it. Y grows downward.
    func testDatumFillSkipsDatumAboveThePlot() {
        for strip in [true, false] {
            let fillsAboveDatum = !strip
            XCTAssertFalse(CurveDrawing.datumFillShows(plotTop: 20, datumY: -40, lowestY: 120,
                                                       fillsAboveDatum: fillsAboveDatum),
                           "datum above the plot draws nothing (strip: \(strip))")
            XCTAssertTrue(CurveDrawing.datumFillShows(plotTop: 20, datumY: 60, lowestY: 120,
                                                      fillsAboveDatum: fillsAboveDatum),
                          "a low under a datum inside the plot keeps its amber (strip: \(strip))")
        }
        // Datum below every trough: the card fades its blue at the trough, the strip draws nothing.
        XCTAssertTrue(CurveDrawing.datumFillShows(plotTop: 20, datumY: 200, lowestY: 120, fillsAboveDatum: true))
        XCTAssertFalse(CurveDrawing.datumFillShows(plotTop: 20, datumY: 200, lowestY: 120, fillsAboveDatum: false))
    }

    /// Below the ramp floor the line is the base colour; above it the stroke
    /// follows the absolute tide-rate ramp, so a lazy tide never leaves blue
    /// and a Fundy run reaches red.
    func testTideRateStopsColourOnlyFastWater() {
        let lazy = [(x: CGFloat(0), rate: 0.2), (x: CGFloat(100), rate: -0.5)]
        XCTAssertTrue(CurveDrawing.tideRateStops(lazy, width: 100).allSatisfy { $0.color == SN.graphLine })

        let fundy = [(x: CGFloat(0), rate: 0.2), (x: CGFloat(50), rate: 1.8), (x: CGFloat(100), rate: 0.2)]
        let stops = CurveDrawing.tideRateStops(fundy, width: 100)
        XCTAssertEqual(stops[0].color, SN.graphLine)
        XCTAssertEqual(stops[1].color, SN.speedColour(1), "1.8 m/hr is the red ceiling")
        XCTAssertEqual(stops[2].color, SN.graphLine)
        XCTAssertEqual(stops[1].location, 0.5, accuracy: 0.001)
    }

    /// The speed thread: clear below the ramp's first anchor, its yellow
    /// fading in to the second, the absolute ramp above — so two peaks of
    /// different speed thread different colours and a 6 kn peak threads the
    /// same colour at every station.
    func testSpeedCoreStopsFollowTheAbsoluteRamp() {
        XCTAssertTrue(CurveDrawing.speedCoreStops([], width: 100).isEmpty)
        XCTAssertTrue(CurveDrawing.speedCoreStops([(x: 0, speedKn: 6)], width: 0).isEmpty, "a zero-width plot has no stops")
        let single = CurveDrawing.speedCoreStops([(x: 50, speedKn: 6)], width: 100)
        XCTAssertEqual(single.count, 2, "one sample is doubled so the gradient has two stops")

        let stops = CurveDrawing.speedCoreStops(
            [(x: -10, speedKn: 0.2), (x: 25, speedKn: 3), (x: 50, speedKn: -6), (x: 75, speedKn: 12), (x: 110, speedKn: 0.4)],
            width: 100)
        XCTAssertEqual(stops.map(\.location), stops.map(\.location).sorted(), "locations are in order")
        XCTAssertTrue(stops.allSatisfy { (0...1).contains($0.location) }, "and clamped to the plot")
        XCTAssertEqual(stops[0].color, SN.speedColour(0).opacity(0), "clear below the first anchor")
        XCTAssertEqual(stops[4].color, SN.speedColour(0).opacity(0), "at either end")
        XCTAssertEqual(stops[1].color, SN.speedColour(widgetSpeedRampT(3)), "the ramp from the second anchor")
        XCTAssertEqual(stops[2].color, SN.speedColour(widgetSpeedRampT(6)), "sign is direction, not speed")
        XCTAssertEqual(stops[3].color, SN.speedColour(1), "12 kn is the red ceiling")
        XCTAssertNotEqual(stops[2].color, stops[3].color, "two peaks of different speed thread different colours")
    }

    /// v falls linearly 2 kn → -2 kn over 2 h (slack at +60 min); |v| < 0.5
    /// between +45 and +75 min. Samples every 10 min like the drawn series.
    func testSlackWindowInterpolatesCrossings() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...12).map { i in
            CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600),
                         speed: 2.0 - Double(i) / 3.0)
        }
        let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(3600),
                                          threshold: 0.5))
        XCTAssertEqual(w.start.timeIntervalSince(t0), 2700, accuracy: 1)
        XCTAssertEqual(w.end.timeIntervalSince(t0), 4500, accuracy: 1)
    }

    /// A series that never leaves the window clamps to its edges.
    func testSlackWindowClampsToSeriesEdges() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...6).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 600), speed: 0.1) }
        let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(1800), threshold: 0.5))
        XCTAssertEqual(w.start, pts.first!.time)
        XCTAssertEqual(w.end, pts.last!.time)
    }

    func testSlackWindowIncludesAnExactThresholdPoint() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            CurrentPoint(time: t0, speed: 2),
            CurrentPoint(time: t0.addingTimeInterval(600), speed: 1),
            CurrentPoint(time: t0.addingTimeInterval(1200), speed: 2),
        ]
        let window = try XCTUnwrap(slackWindow(points, around: points[1].time, threshold: 1))
        XCTAssertEqual(window.start, points[1].time)
        XCTAssertEqual(window.end, points[1].time)
    }

    /// A violent gate where the 10-min sampling steps over the band: the
    /// reversal between +4 and −4 kn still crosses ±0.5 kn, so the window is
    /// interpolated on that one segment — 262.5 s and 337.5 s into it.
    func testSlackWindowInterpolatesAReversalThatStepsOverTheBand() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...4).map { i in
            CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600),
                         speed: i < 2 ? 4.0 : -4.0)
        }
        let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(900), threshold: 0.5))
        XCTAssertEqual(w.start.timeIntervalSince(t0), 862.5, accuracy: 0.01)
        XCTAssertEqual(w.end.timeIntervalSince(t0), 937.5, accuracy: 0.01)
    }

    /// A slack outside the sampled series has no window. Events are scanned with a
    /// ±6h pad beyond the strip and the points are clipped to it, so this case is
    /// reachable at both edges — and it used to return a window sitting entirely
    /// before its own slack.
    func testSlackOutsideTheSeriesHasNoWindow() {
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let pts = (0...5).map { i in
            CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600), speed: 0.1)
        }
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(-3600), threshold: 0.5),
                     "a slack before the series has no window")
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(6 * 3600), threshold: 0.5),
                     "a slack after the series must not borrow the trailing run")
    }

    /// The window computation is build-time data now, not a per-view recompute
    /// (gutter spec §3) — so the band on the strip and the duration in the
    /// readout are the same numbers by construction.
    func testSlackWindowsBracketTheirSlacks() throws {
        let station = try XCTUnwrap(CurrentStationRecord.all.first)
        let d = TimelineData.build(tide: nil, current: station, now: Date(), anchor: todayLocal(station.tz))
        let slacks = d.currentEvents.filter { $0.kind == .slack }
        XCTAssertGreaterThan(slacks.count, 10, "a week of slacks must exist to window")
        XCTAssertFalse(d.slackWindows.isEmpty)
        for w in d.slackWindows {
            XCTAssert(w.start <= w.slack && w.slack <= w.end,
                      "a window must bracket its own slack: \(w)")
            XCTAssert(slacks.contains { $0.time == w.slack },
                      "every window belongs to a drawn slack event")
        }
    }

    func testSlackWindowEdgesAreMagneticPoints() throws {
        let station = try XCTUnwrap(CurrentStationRecord.all.first)
        let timeline = TimelineData.build(tide: nil, current: station, now: Date(),
                                          anchor: todayLocal(station.tz), threshold: 1)
        let run = try XCTUnwrap(timeline.windowRuns.first { !$0.isDot })
        XCTAssertTrue(timeline.snapTimes.contains(run.start))
        XCTAssertTrue(timeline.snapTimes.contains(run.end))
    }

    /// The window is half-open: parked on its opening the water is still
    /// slack, parked on its closing it is already leaving — and the closing is
    /// a snap target, so the scrubber does park there. Reporting "Slack · 0m"
    /// at the edge you are being told to leave is the defect this shape
    /// prevents; the commentary names the run that begins instead.
    func testSlackWindowContainsItsOpeningButNotItsClosing() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let run = WindowRun(start: t0.addingTimeInterval(300), end: t0.addingTimeInterval(2_400))

        XCTAssertTrue(run.holdsSlack(at: run.start))
        XCTAssertTrue(run.holdsSlack(at: t0.addingTimeInterval(1_200)))
        XCTAssertTrue(run.holdsSlack(at: run.end.addingTimeInterval(-1)), "a second before the closing is still inside")
        XCTAssertFalse(run.holdsSlack(at: run.end), "the closing itself is outside — the run has begun")
        XCTAssertFalse(run.holdsSlack(at: run.start.addingTimeInterval(-1)))
        XCTAssertFalse(run.holdsSlack(at: run.end.addingTimeInterval(1)))
    }

    /// A derived gate's curve is a schematic ±1 SHAPE, not a velocity, so a
    /// 0.5 kn window measured off it would be fiction (gutter spec §3). Its
    /// slacks fall back to a plain dropline instead.
    func testDerivedGateHasNoSlackWindows() throws {
        let port = TideStationRecord(
            id: "chs-point-atkinson", name: "Point Atkinson", region: "West Vancouver",
            aliases: [], latitude: 49.337, longitude: -123.254,
            timezone: "America/Vancouver", chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        let gate = DerivedGateRecord(gate: ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" }!,
                                     port: port)
        let d = TimelineData.build(gate: gate, now: Date(), anchor: todayLocal(gate.gate.tz))
        XCTAssert(d.hasCurrent, "the schematic track exists")
        XCTAssertFalse(d.currentEvents.isEmpty, "the gate has slack events")
        XCTAssert(d.slackWindows.isEmpty, "but no windows — the curve is a shape (gutter spec §3)")
    }

    /// The strip is wider than one Metal texture. A `Canvas` is a single
    /// backing layer capped at 8192px per side, and the whole chart renders
    /// EMPTY past it — silently, no error, which is why this needs a test and
    /// not a comment. Widening `pph` from 12 to 18 crossed it on a 3× phone
    /// (9720px) and blanked every tide detail; the tiles exist to keep each
    /// layer under the cap, so the assertion is on a tile, not on the strip.
    func testCanvasTilesStayUnderTheTextureCap() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        let cap: CGFloat = 8192
        let scale: CGFloat = 3        // the densest screen this ships to

        XCTAssertGreaterThan(d.totalWidth * scale, cap,
                             "if the whole strip fits in one texture the tiling is dead code — delete it, don't keep an untested branch")
        XCTAssertLessThan(TimelineCanvas.tileWidth * scale, cap,
                          "a tile must fit in one texture at 3×")
        XCTAssertLessThan(TimelineGeo(data: d).height * scale, cap,
                          "and so must its height")
        // Whole points at every scale factor: a fractional boundary antialiases
        // against transparent on both sides and leaves a hairline seam.
        for s in [1.0, 2.0, 3.0] as [CGFloat] {
            XCTAssertEqual((TimelineCanvas.tileWidth * s).truncatingRemainder(dividingBy: 1), 0,
                           "tile boundary must land on a pixel at \(s)×")
        }
    }

    /// Events scanned from a sampled series (online gates draw fetched points,
    /// not a harmonic engine): slacks at interpolated zero crossings, one signed
    /// maximum per run between them.
    func testSampleEventsScanCrossingsAndExtrema() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // 2 → -2 → 2 over 3 h at 15-min samples: crossings at +1h and +2h... use
        // a triangle wave: v(i) = [2,1,0.5,-0.5,-1,-2,-1,-0.5,0.5,1,2] per 15 min.
        let vs: [Double] = [2, 1, 0.5, -0.5, -1, -2, -1, -0.5, 0.5, 1, 2]
        let pts = vs.enumerated().map { CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element) }
        let events = sampleEvents(pts)
        let slacks = events.filter { $0.kind == .slack }
        XCTAssertEqual(slacks.count, 2)
        // First crossing: between samples 2 (0.5) and 3 (-0.5) → halfway, 2250 s.
        XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 2250, accuracy: 1)
        XCTAssertEqual(slacks[1].time.timeIntervalSince(t0), 6750, accuracy: 1)
        let ebbs = events.filter { $0.kind == .maxEbb }
        XCTAssertEqual(ebbs.count, 1)
        XCTAssertEqual(ebbs[0].speed, -2, accuracy: 1e-9)
        XCTAssertEqual(ebbs[0].time.timeIntervalSince(t0), 5 * 900, accuracy: 1)
        // Leading/trailing runs also get their maxima (floods at each end).
        let floods = events.filter { $0.kind == .maxFlood }
        XCTAssertEqual(floods.count, 2)
        XCTAssertEqual(floods[0].speed, 2, accuracy: 1e-9)
        XCTAssertEqual(floods[0].time.timeIntervalSince(t0), 0, accuracy: 1)
        XCTAssertEqual(floods[1].speed, 2, accuracy: 1e-9)
        XCTAssertEqual(floods[1].time.timeIntervalSince(t0), 10 * 900, accuracy: 1)
        // Events alternate: no two slacks adjacent, no two maxima adjacent.
        for (a, b) in zip(events, events.dropFirst()) {
            XCTAssert((a.kind == .slack) != (b.kind == .slack))
        }
    }

    /// A monotone window with no crossing: one maximum, no slacks, no crash.
    func testSampleEventsMonotone() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0..<8).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 900), speed: 1 + Double($0) * 0.1) }
        let events = sampleEvents(pts)
        XCTAssert(events.filter { $0.kind == .slack }.isEmpty)
        XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1)
    }

    // MARK: - The speed ramp's absolute domain (#97)

    func testRampTLandsTheAnchorsWhereTheyBelong() {
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 3), 1.0 / 3, accuracy: 1e-9)
        XCTAssertLessThan(Timeline.rampT(forSpeedKn: 2.2), 0.25,
                          "an ordinary 2.2-kn current remains in yellow")
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 8), 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 12), 1, accuracy: 1e-9)
        // Clamped both ends. Above the ceiling everything is the top colour;
        // "beyond the top of the scale" is not a distinction worth resolving.
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 40), 1, accuracy: 1e-9)
        XCTAssertEqual(Timeline.speedRampAnchorsKn.first, 0.5)
    }

    /// Ordinary currents should remain in the yellow portion of the global
    /// scale; a station-local scale would incorrectly turn them red.
    func testRampTSpreadsOrdinaryGatesAcrossTheRamp() {
        let median = Timeline.rampT(forSpeedKn: 2.26)
        XCTAssertGreaterThan(median, 0.18, "the median station must clear the ramp's floor")
        XCTAssertLessThan(median, 0.30)
        XCTAssertLessThan(Timeline.rampT(forSpeedKn: 5.0), 0.5,
                          "a 5-kn current remains below orange on the global scale")
    }

    /// An exact-zero sample IS the slack — both polarities, no interpolation.
    func testSampleEventsExactZeroSample() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func pts(_ vs: [Double]) -> [CurrentPoint] {
            vs.enumerated().map { CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element) }
        }
        for vs in [[-2.0, -1, 0, 1], [2.0, 1, 0, -1]] {
            let events = sampleEvents(pts(vs))
            let slacks = events.filter { $0.kind == .slack }
            XCTAssertEqual(slacks.count, 1, "\(vs): the zero sample is one slack")
            XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 2 * 900, accuracy: 1)
            XCTAssertEqual(events.filter { $0.kind == .maxEbb }.count, 1, "\(vs)")
            XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1, "\(vs)")
        }
        // Consecutive zeros: one slack, at the first zero sample.
        let events = sampleEvents(pts([1, 0, 0, -1]))
        XCTAssertEqual(events.filter { $0.kind == .slack }.count, 1)
        XCTAssertEqual(events.filter { $0.kind == .slack }[0].time.timeIntervalSince(t0), 900, accuracy: 1)
    }

    /// The online-gate path: build directly from fetched points (no engine
    /// station involved) — current-only strip, standard 340pt geometry, and
    /// every in-window event lands as a snap stop (mirrors the DerivedGateTests
    /// snap assertion for the schematic-gate path).
    func testBuildFromOnlinePointsIsCurrentOnlyAndSnaps() {
        let now = Date()
        let tz = TimeZone(identifier: "America/Vancouver")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: now)
        // The shared definition, not a second derivation of it.
        let (start, end) = Timeline.window(anchor: today)

        // 15-min samples spanning the whole strip window, oscillating with a
        // ~12h period so slack/max events recur across it (real semidiurnal shape).
        var pts: [CurrentPoint] = []
        var t = start
        while t <= end {
            let hours = t.timeIntervalSince(start) / 3600
            pts.append(CurrentPoint(time: t, speed: 2.0 * sin(hours / 6.0 * .pi)))
            t = t.addingTimeInterval(900)
        }

        let d = TimelineData.build(onlinePoints: pts, tz: tz, lat: 48.5, lon: -123.0, now: now, anchor: today)

        XCTAssert(d.hasCurrent && !d.hasTide)
        XCTAssertFalse(d.currentEvents.isEmpty)
        // Fetched official samples are real velocities, so the online-gate path
        // gets slack windows — the derived-gate path does not, because its curve
        // is a schematic shape (gutter spec §3).
        XCTAssertFalse(d.slackWindows.isEmpty,
                       "online gates draw fetched speeds, so their slacks carry windows")
        for w in d.slackWindows {
            XCTAssert(w.start <= w.slack && w.slack <= w.end,
                      "a window must bracket its own slack: \(w)")
        }
        XCTAssert(d.currentEvents
            .filter { $0.time >= d.start && $0.time <= d.end }
            .allSatisfy { e in d.snapTimes.contains { abs($0.timeIntervalSince(e.time)) < 1 } })
    }

    /// A window ending exactly on a slack sample must not trap (the post-loop
    /// run close sees an empty run) — and the zero still reads as the slack.
    func testSampleEventsTrailingZero() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [1.0, -1, 0].enumerated().map {
            CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element)
        }
        let events = sampleEvents(pts)
        let slacks = events.filter { $0.kind == .slack }
        XCTAssertEqual(slacks.count, 2)                       // the crossing + the trailing zero
        XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 450, accuracy: 1)
        XCTAssertEqual(slacks[1].time.timeIntervalSince(t0), 1800, accuracy: 1)
        XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1)
        XCTAssertEqual(events.filter { $0.kind == .maxEbb }.count, 1)
    }

    // MARK: - The range bar label (spec §5)

    /// One label, the shapes it has to take. Was three tests with one assert
    /// each and the same two setup lines.
    /// Sunrise and sunset times share one ink wherever they print; the symbol tells them apart.
    func testSunTimesShareTheSunriseInk() throws {
        for (name, source) in try appSources() {
            for line in source.components(separatedBy: .newlines) {
                XCTAssertFalse(codeOnly(line).contains("SN.sunset"), "\(name) gives sunset its own ink: \(line)")
            }
        }
    }

    func testWeekRangeLabel() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        let today = vancouverMidnight(2026, 9, 12)
        let american = Locale(identifier: "en_US")
        let cases: [(y: Int, m: Int, d: Int, expected: String, why: String)] = [
            // Anchor Aug 11 → groups Aug 11…Aug 17. The label names Aug 17, the
            // last day ON SCREEN, never the exclusive Aug 18 boundary.
            (2026, 8, 11, "Aug 11\u{2009}–\u{2009}17", "names the last day shown"),
            (2026, 8, 28, "Aug 28\u{2009}–\u{2009}Sep 3", "spells the month when it changes"),
            (2026, 12, 29, "Dec 29, 2026\u{2009}–\u{2009}Jan 4, 2027", "shows both years when they change"),
            (2026, 6, 1, "Jun 1\u{2009}–\u{2009}7", "a range in today's year never prints a year"),
            // Out of today's year, the year is all that tells next March from this one.
            (2027, 3, 3, "Mar 3\u{2009}–\u{2009}9, 2027", "a later year prints it"),
            (2025, 3, 3, "Mar 3\u{2009}–\u{2009}9, 2025", "an earlier year prints it"),
        ]
        for c in cases {
            XCTAssertEqual(weekRangeLabel(anchor: vancouverMidnight(c.y, c.m, c.d),
                                          today: today, tz: tz, locale: american),
                           c.expected, c.why)
        }
        XCTAssertEqual(weekRangeLabel(anchor: vancouverMidnight(2026, 8, 11),
                                      today: today, tz: tz,
                                      locale: Locale(identifier: "fr_FR")),
                       "11–17 août")
    }
}
