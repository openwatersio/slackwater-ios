// Slackwater — GPL v3. Derived current gates (Malibu Rapids): bundled identity
// from the registry, the search path, and the slack-derivation math — the
// reference port's HW/LW plus the fixed lags (web chs/current.ts parity).
import XCTest
@testable import Slackwater
import TideEngine

final class DerivedGateTests: XCTestCase {
    let malibu = ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" }

    // MARK: - Bundled identity (chs-gates.json, generated from the registry)

    func testMalibuBundledWithRegistryLags() throws {
        let gate = try XCTUnwrap(malibu, "Malibu Rapids missing from chs-gates.json")
        XCTAssertEqual(gate.name, "Malibu Rapids")
        XCTAssertEqual(gate.region, "Princess Louisa Inlet")
        XCTAssertEqual(gate.reference, "chs-point-atkinson")
        XCTAssertEqual(gate.hwLagMinutes, 25)
        XCTAssertEqual(gate.lwLagMinutes, 35)
        // The reference must be a bundled CHS port the app can actually fit.
        XCTAssert(ChsStationInfo.all.contains { $0.id == gate.reference },
                  "reference port not in chs-stations.json")
    }

    // MARK: - Search: name, region, and the registry aliases all find the gate

    func testSearchFindsMalibu() {
        for query in ["malibu", "princess louisa", "malibu islet"] {
            let hits = StationItem.search(query, near: firstRunFix)
            XCTAssert(hits.contains { $0.id == "chs-malibu-rapids" },
                      "search '\(query)' did not find Malibu Rapids")
        }
        // It joins the pin pool as a current gate (web: series "current").
        let item = StationItem.all.first { $0.id == "chs-malibu-rapids" }
        XCTAssertEqual(item?.pinKind, "current")
    }

    // MARK: - Slack derivation: reference extremes + lags, HW/LW flagged

    /// A synthetic semidiurnal reference (one M2 constituent) makes the
    /// extremes analytic — every derived slack must sit exactly one lag after
    /// a reference extreme, flagged with that extreme's kind.
    func testSlacksAreLaggedReferenceExtremes() {
        let reference = Station(constituents: [HarmonicConstituent(name: "M2", amplitude: 1.5, phase: 0)],
                                offset: 3.0)
        let gate = DerivedSlackStation(reference: reference, hwLagMinutes: 25, lwLagMinutes: 35)
        let from = Date(timeIntervalSince1970: 1_753_920_000)  // 2025-07-31 00:00 UTC
        let to = from.addingTimeInterval(48 * 3600)

        let extremes = reference.extremes(from: from, to: to)
        let slacks = gate.slacks(from: from, to: to)
        XCTAssertGreaterThanOrEqual(slacks.count, 6, "48h of M2 must yield ≥6 slacks")

        for slack in slacks {
            let lag = slack.highWater ? 25.0 * 60 : 35.0 * 60
            let origin = slack.time.addingTimeInterval(-lag)
            let match = extremes.min { abs($0.time.timeIntervalSince(origin)) < abs($1.time.timeIntervalSince(origin)) }
            XCTAssertNotNil(match)
            XCTAssertEqual(match!.time.timeIntervalSince(origin), 0, accuracy: 60,
                           "slack must sit exactly one lag after a reference extreme")
            XCTAssertEqual(match!.kind == .high, slack.highWater,
                           "HW slack must come from a high, LW slack from a low")
        }
    }

    /// Phase mirrors the web: slack within ±12 min of a slack, flood toward a
    /// high-water slack, ebb toward a low-water one.
    func testPhaseFollowsTideTrend() {
        let reference = Station(constituents: [HarmonicConstituent(name: "M2", amplitude: 1.5, phase: 0)],
                                offset: 3.0)
        let gate = DerivedSlackStation(reference: reference, hwLagMinutes: 25, lwLagMinutes: 35)
        let from = Date(timeIntervalSince1970: 1_753_920_000)
        let slacks = gate.slacks(from: from, to: from.addingTimeInterval(48 * 3600))
        let first = slacks[0], second = slacks[1]

        XCTAssertEqual(gate.phase(at: first.time, slacks: slacks), .slack)
        let mid = first.time.addingTimeInterval(second.time.timeIntervalSince(first.time) / 2)
        XCTAssertEqual(gate.phase(at: mid, slacks: slacks), second.highWater ? .flood : .ebb,
                       "mid-cycle phase must follow the tide trend toward the next slack")
    }

    // MARK: - The strip: schematic shape (±1, no speed), slack-only events

    func testTimelineIsSchematicAndSlackOnly() {
        // A fitted-model-shaped record around a synthetic M2-only reference.
        let port = TideStationRecord(
            id: "chs-point-atkinson", name: "Point Atkinson", region: "West Vancouver",
            aliases: [], latitude: 49.337, longitude: -123.254,
            timezone: "America/Vancouver", chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        let gate = DerivedGateRecord(gate: ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" }!,
                                     port: port)
        let d = TimelineData.build(gate: gate, now: Date(), anchor: todayLocal(gate.gate.tz))

        XCTAssertFalse(d.hasTide, "a derived gate's strip is single-track — no tide track (split-scrubbers spec §3)")
        XCTAssert(d.tideExtremes.isEmpty, "no port turns in the data — they'd re-enter snapTimes and the schedule")
        XCTAssert(d.hasCurrent, "the schematic current track must be present")
        XCTAssert(d.currentEvents.allSatisfy { $0.kind == .slack && $0.speed == 0 },
                  "a derived gate has slack events only, never a speed")
        let maxAbs = d.currentPoints.map { abs($0.speed) }.max() ?? 0
        XCTAssert(maxAbs <= 1.0001 && maxAbs > 0.5,
                  "schematic curve must be normalised to ±1, got \(maxAbs)")
        // In-window slacks are snap stops, so the scrubber parks on them
        // (snapTimes clips to the strip; events keep the ±6h scan pad).
        XCTAssert(d.currentEvents
            .filter { $0.time >= d.start && $0.time <= d.end }
            .allSatisfy { e in d.snapTimes.contains { abs($0.timeIntervalSince(e.time)) < 1 } })
    }
}
