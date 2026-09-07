// Slackwater — GPL v3. The 2026-08-28 partial is the fixture throughout: it is
// Almanac's own pinned regression case (umbral magnitude ~0.93, visible at peak
// from Victoria, not from Athens), and Friday Harbor sits in the same sky.
import Almanac
import SwiftUI
import UIKit
import XCTest
@testable import Slackwater

final class EclipseTests: XCTestCase {
    static let victoria = try! Observer(latitudeDeg: 48.42, longitudeDeg: -123.37)
    /// The not-visible fixture, and it is not a coin flip: the whole event
    /// falls in Perth's daylight on the day of the full moon, and a full moon
    /// is below the horizon while the sun is up.
    static let perth = try! Observer(latitudeDeg: -31.95, longitudeDeg: 115.86)

    let friday = TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!

    private func utc(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    /// The local midnight `iso` falls inside, at this station.
    private func anchor(_ iso: String, _ tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.startOfDay(for: utc(iso))
    }

    /// A timeline anchored on the eclipse's own LOCAL day — which is 2026-08-27
    /// at Friday Harbor, not the 08-28 the eclipse is named for: the whole
    /// event runs from 18:24 to 00:01 PDT on the evening of the 27th. Anchored
    /// on the 28th the start lands in the 48-hour back-pad, inside the strip's
    /// window but outside `scheduleRange`, and the list row disappears.
    private func eclipseTimeline() throws -> (TimelineData, WindowEclipse) {
        let at = anchor("2026-08-27T12:00:00Z", friday.tz)
        let tl = TimelineData.build(tide: friday, current: nil, now: at, anchor: at)
        return (tl, try XCTUnwrap(tl.eclipses.first))
    }

    // MARK: - The window search

    func testTheWindowFindsThe2026PartialAndDescribesIt() throws {
        let found = visibleEclipses(from: utc("2026-08-25T00:00:00Z"),
                                  to: utc("2026-08-31T00:00:00Z"),
                                  observer: Self.victoria)
        XCTAssertEqual(found.count, 1)
        let e = try XCTUnwrap(found.first)
        XCTAssertEqual(e.kind, .partial)
        XCTAssertEqual(e.start, e.eclipse.u1)
        XCTAssertEqual(e.contacts,
                       [e.eclipse.p1, e.eclipse.u1!, e.peak, e.eclipse.u4!, e.eclipse.p4])
        XCTAssertEqual(e.contacts, e.contacts.sorted())
        XCTAssertTrue(e.anyContactVisible)
    }

    func testAnEclipseNobodyHereCanSeeIsDropped() {
        let found = visibleEclipses(from: utc("2026-08-25T00:00:00Z"),
                                  to: utc("2026-08-31T00:00:00Z"),
                                  observer: Self.perth)
        XCTAssertTrue(found.isEmpty, "Perth is in daylight for the whole event")
    }

    func testShadowIsZeroOutsideAndPeaksAtTheUmbralMagnitude() throws {
        let e = try XCTUnwrap(visibleEclipses(from: utc("2026-08-25T00:00:00Z"),
                                            to: utc("2026-08-31T00:00:00Z"),
                                            observer: Self.victoria).first)
        XCTAssertEqual(e.shadow(at: e.eclipse.p1.addingTimeInterval(-60)), 0)
        XCTAssertEqual(e.shadow(at: e.eclipse.p4.addingTimeInterval(60)), 0)
        // A penumbral leg is a dimming, not a bite.
        XCTAssertEqual(e.shadow(at: e.eclipse.p1.addingTimeInterval(60)), 0)
        XCTAssertEqual(e.shadow(at: e.peak), e.eclipse.magUmbral, accuracy: 0.001)
        XCTAssertEqual(e.shadow(at: try XCTUnwrap(e.eclipse.u1)), 0, accuracy: 0.001)
        XCTAssertEqual(e.shadow(at: try XCTUnwrap(e.eclipse.u4)), 0, accuracy: 0.001)

        let u1 = try XCTUnwrap(e.eclipse.u1)
        let half = u1.addingTimeInterval(e.peak.timeIntervalSince(u1) / 2)
        XCTAssertGreaterThan(e.shadow(at: half), 0)
        XCTAssertLessThan(e.shadow(at: half), e.eclipse.magUmbral)

        XCTAssertTrue(e.underway(at: e.peak))
        XCTAssertTrue(e.underway(at: e.eclipse.p1))
        XCTAssertFalse(e.underway(at: e.eclipse.p4.addingTimeInterval(60)))
    }

    func testAQuietMonthHasNoEclipse() {
        // October 2026 carries a full moon and no lunar eclipse; the next one
        // after 2026-08-28 is in 2027.
        XCTAssertTrue(visibleEclipses(from: utc("2026-10-01T00:00:00Z"),
                                    to: utc("2026-10-31T00:00:00Z"),
                                    observer: Self.victoria).isEmpty)
    }

    func testThePenumbralLegDimsTheMoonWhereTheUmbraDoesNot() throws {
        let e = try XCTUnwrap(visibleEclipses(from: utc("2026-08-25T00:00:00Z"),
                                            to: utc("2026-08-31T00:00:00Z"),
                                            observer: Self.victoria).first)
        // Between P1 and U1 the moon is IN the penumbra and nowhere near the
        // umbra. Without the wash the app would draw an untouched moon while
        // saying an eclipse was underway — which is what the first screenshots
        // of a penumbral eclipse showed.
        let u1 = try XCTUnwrap(e.eclipse.u1)
        let leg = e.eclipse.p1.addingTimeInterval(u1.timeIntervalSince(e.eclipse.p1) / 2)
        XCTAssertEqual(e.shadow(at: leg), 0)
        XCTAssertGreaterThan(e.wash(at: leg), 0)

        XCTAssertEqual(e.wash(at: e.eclipse.p1), 0, accuracy: 0.001)
        XCTAssertEqual(e.wash(at: e.eclipse.p4), 0, accuracy: 0.001)
        XCTAssertEqual(e.wash(at: e.eclipse.p1.addingTimeInterval(-60)), 0)
        // Clamped: magPenumbral runs above 1 for a deep partial.
        XCTAssertLessThanOrEqual(e.wash(at: e.peak), 1)
        XCTAssertGreaterThan(e.wash(at: e.peak), 0.5)
    }

    // MARK: - The glyph

    func testTheUmbraDiscSlidesFromTouchingToCovering() {
        // Same shape as moonLimbShift: an equal-radius disc offset across the
        // moon. Tangent at zero coverage (2r), concentric when covered.
        XCTAssertEqual(moonUmbraShift(coverage: 0, radius: 10), 20, accuracy: 0.001)
        XCTAssertEqual(moonUmbraShift(coverage: 1, radius: 10), 0, accuracy: 0.001)
        XCTAssertEqual(moonUmbraShift(coverage: 0.5, radius: 10), 10, accuracy: 0.001)
        // A total eclipse reports magUmbral above 1; the disc stops at covered.
        XCTAssertEqual(moonUmbraShift(coverage: 1.4, radius: 10), 0, accuracy: 0.001)
    }

    @MainActor
    func testTheEclipsedGlyphDrawsSomethingTheCleanOneDoesNot() throws {
        func shot(_ umbra: Double, _ wash: Double) throws -> UIImage {
            let renderer = ImageRenderer(content:
                MoonGlyph(fraction: 1, waxing: false, size: 44, umbra: umbra, wash: wash)
                    .frame(width: 60, height: 60)
                    .background(SN.canvas))
            renderer.scale = 2
            return try XCTUnwrap(renderer.uiImage)
        }
        // Copper pixels, not ink: the umbra REPLACES lit moon rather than
        // adding to it, so the not-background count barely moves (measured:
        // 0.388 clean against 0.389 eclipsed).
        let clean = try shot(0, 0)
        let eclipsed = try shot(0.93, 1)
        // A penumbral eclipse has NO umbral bite — the wash is its only mark,
        // so what matters is that it changes the moon at all.
        let penumbral = try shot(0, 0.9)
        XCTAssertEqual(copperFraction(clean), 0, accuracy: 0.001,
                       "a clear moon has nothing copper on it")
        XCTAssertGreaterThan(copperFraction(eclipsed), 0.1,
                             "the shadow covers most of the disc — got \(copperFraction(eclipsed))")
        let washed = differingFraction(penumbral, clean)
        XCTAssertGreaterThan(washed, 0.1, "a penumbral eclipse left the moon untouched")
        XCTAssertLessThan(copperFraction(penumbral), copperFraction(eclipsed),
                          "the wash must read lighter than the umbra")
    }

    // MARK: - The Moon sheet

    func testTheTileNamesTheEclipseInsteadOfThePhase() {
        XCTAssertEqual(eclipseTileText(.total), "Total Eclipse")
        XCTAssertEqual(eclipseTileText(.partial), "Partial Eclipse")
        XCTAssertEqual(eclipseTileText(.penumbral), "Penumbral Eclipse")
    }

    func testMoonFactsFindAnEclipseOnEitherSideOfTheNight() throws {
        let facts = try XCTUnwrap(moonFacts(at: utc("2026-09-07T12:00:00Z"),
                                            observer: Self.victoria,
                                            tz: TimeZone(identifier: "America/Vancouver")!))
        // Ten days on from the partial, it is the one behind us. An hour of
        // slack around Espenak's 04:12 UT greatest: Almanac holds that to 60 s,
        // so this only fails if the WRONG eclipse was found.
        let last = try XCTUnwrap(facts.last)
        XCTAssertEqual(last.peak.timeIntervalSince(utc("2026-08-28T04:12:00Z")), 0, accuracy: 3600)
        XCTAssertEqual(last.kind, .partial)

        let next = try XCTUnwrap(facts.next)
        XCTAssertGreaterThan(next.peak, utc("2026-09-07T12:00:00Z"))

        XCTAssertNotNil(facts.closest)
        XCTAssertNotNil(facts.farthest)
        XCTAssertGreaterThan(facts.distanceKm, 350_000)
        XCTAssertLessThan(facts.distanceKm, 410_000)
    }

    /// The sheet does its searching in a `.task`, but a sheet that renders
    /// empty for half a second is its own bug.
    func testMoonFactsStayUnderHalfASecond() {
        let t0 = Date()
        _ = moonFacts(at: utc("2026-09-07T12:00:00Z"), observer: Self.victoria,
                      tz: TimeZone(identifier: "America/Vancouver")!)
        let elapsed = Date().timeIntervalSince(t0)
        print("moonFacts \(elapsed * 1000) ms")
        XCTAssertLessThan(elapsed, 0.5)
    }

    // MARK: - In the schedule

    func testTheEclipseRowMergesIntoTheScheduleInTimeOrder() throws {
        let (tl, e) = try eclipseTimeline()
        let rows = eclipseEntries(tl)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.time, e.start)
        XCTAssertEqual(rows.first?.pill, .eclipse)
        // The value column carries the peak — the one instant worth quoting.
        XCTAssertEqual(rows.first?.value, chartTime(e.peak, tl.tz))
        XCTAssertTrue(tl.scheduleRange.contains(e.start))

        // And it sorts in among the tide turns rather than landing at an end.
        // The tide rows are rebuilt here rather than reached for: the detail
        // view's builder is private to it, and only the ORDER matters.
        let tides = tl.tideExtremes
            .filter { tl.scheduleRange.contains($0.time) }
            .map { ScheduleEntry(time: $0.time, pill: $0.kind == .high ? .high : .low) }
        let merged = (tides + rows).sorted { $0.time < $1.time }
        let index = try XCTUnwrap(merged.firstIndex { $0.pill == .eclipse })
        XCTAssertGreaterThan(index, 0, "the eclipse is not the first event of the week")
        XCTAssertLessThan(index, merged.count - 1, "nor the last")
    }

    func testAQuietWeekAddsNoScheduleRow() {
        let at = anchor("2026-10-08T12:00:00Z", friday.tz)
        let tl = TimelineData.build(tide: friday, current: nil, now: at, anchor: at)
        XCTAssertTrue(eclipseEntries(tl).isEmpty)
    }

    @MainActor
    func testTheStripMarksTheEclipse() throws {
        let (tl, _) = try eclipseTimeline()

        // The SAME window with the eclipses removed — not a different week, so
        // the tide curve, day chrome and sun dots are pixel-identical and the
        // only difference left is the mark.
        var stripped = tl
        stripped.eclipses = []

        let marked = try XCTUnwrap(stripImage(tl))
        let plain = try XCTUnwrap(stripImage(stripped))
        // A 6.5pt glyph on a 228-hour strip is a handful of pixels, so the
        // measure is "anything at all changed", not a share. A colour
        // threshold cannot help here either: the emoji is not copper.
        let changed = differingFraction(marked, plain)
        XCTAssertGreaterThan(changed, 0, "no eclipse mark on the strip")
    }

    // MARK: - On the dome

    func testTheSkyStateCarriesOnlyTheEclipseUnderwayAtItsTime() throws {
        let (tl, e) = try eclipseTimeline()

        let peak = SkyState(time: e.peak, latitude: friday.latitude, longitude: friday.longitude,
                            days: tl.days, eclipses: tl.eclipses)
        XCTAssertNotNil(peak.eclipse)
        XCTAssertEqual(peak.shadow, e.eclipse.magUmbral, accuracy: 0.001)

        let after = SkyState(time: e.eclipse.p4.addingTimeInterval(3600),
                             latitude: friday.latitude, longitude: friday.longitude,
                             days: tl.days, eclipses: tl.eclipses)
        XCTAssertNil(after.eclipse)
        XCTAssertEqual(after.shadow, 0)
    }

    func testEveryScrubDetailHandsTheSkyItsEclipses() throws {
        for file in ["Slackwater/TideDetailView.swift", "Slackwater/CurrentDetailView.swift",
                     "Slackwater/OnlineGateDetailView.swift", "Slackwater/DerivedGateDetailView.swift"] {
            XCTAssertTrue(try repoSource(file).contains("eclipses: timeline?.eclipses ?? []"), file)
        }
    }

    // MARK: - On the timeline

    func testTheTimelineCarriesTheEclipseAndSnapsToEveryContact() throws {
        let (tl, e) = try eclipseTimeline()
        XCTAssertEqual(e.kind, .partial)
        for c in e.contacts where tl.contains(c) {
            XCTAssertTrue(tl.snapTimes.contains(c), "contact \(c) is not magnetic")
        }
    }

    func testAWindowWithNoFullMoonCarriesNoEclipse() {
        let at = anchor("2026-10-08T12:00:00Z", friday.tz)
        let tl = TimelineData.build(tide: friday, current: nil, now: at, anchor: at)
        XCTAssertTrue(tl.eclipses.isEmpty)
    }

    /// A rebuild is a user action — opening a detail, picking a week — not a
    /// frame. 250 ms is where it stops feeling instant.
    func testBuildingAnEclipseWindowStaysUnderTheRebuildBudget() {
        let eclipseWeek = anchor("2026-08-27T12:00:00Z", friday.tz)
        let t0 = Date()
        _ = TimelineData.build(tide: friday, current: nil, now: eclipseWeek, anchor: eclipseWeek)
        let withEclipse = Date().timeIntervalSince(t0)

        let quietWeek = anchor("2026-10-08T12:00:00Z", friday.tz)
        let t1 = Date()
        _ = TimelineData.build(tide: friday, current: nil, now: quietWeek, anchor: quietWeek)
        let without = Date().timeIntervalSince(t1)

        print("eclipse-week build \(withEclipse * 1000) ms, quiet week \(without * 1000) ms")
        XCTAssertLessThan(withEclipse, 0.25)
        XCTAssertLessThan(without, 0.25)
    }
}
