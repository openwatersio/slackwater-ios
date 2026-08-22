// Slackwater — GPL v3. WidgetSnapshot: next event, slack window, and a
// normalized day-curve — deterministic given (station, now).
import XCTest
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
        XCTAssert(leading.contains { $0 > 0.01 }, "leading samples are flat — backward pad missing")
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
