// Slackwater — GPL v3. M51: the fast answer. Three things have to hold, and
// each one is a way the feature could quietly become dishonest:
//   1. the window is PER GATE, and the four gates validated at 60 d never show
//      a provisional stage at all — their first fit is final;
//   2. a gate only offers a fast answer when its MEASURED 60-day slack error
//      cleared the usefulness floor, and the copy names that gate's own number;
//   3. the 60-day chunks are the newest chunks of the full plan, cached, so a
//      job that stepped aside resumes without paying for the same bytes twice.
import XCTest
@testable import Slackwater

final class ChsProvisionalTests: XCTestCase {
    /// The floor set in tools/gen-chs-gates.mjs, restated here so the bundle
    /// cannot drift past it unnoticed: 45 min of 60-day WORST slack error, the
    /// point past which the warning is itself the instruction not to use the
    /// number. Worst, not median — worst is what the copy quotes.
    private let floorMinutes = 45

    private func gate(_ id: String) -> ChsCurrentGateInfo {
        ChsCurrentGateInfo.all.first { $0.id == id }!
    }

    // MARK: - The bundled per-gate windows

    func testEveryBundledGateCarriesItsOwnValidatedWindow() {
        // +7 online fit-reject identities (online-gates task 1): fitDays 0 is
        // their documented never-fitted sentinel, so the window check below
        // is scoped to the fitted (offline) gates.
        XCTAssertEqual(ChsCurrentGateInfo.all.count, 18)
        for g in ChsCurrentGateInfo.all where !g.isOnline {
            XCTAssert(g.fitDays == 60 || g.fitDays == 210, "\(g.id): unexpected window \(g.fitDays)")
        }
        let fast = ChsCurrentGateInfo.all.filter { $0.fitDays == 60 }.map(\.id).sorted()
        XCTAssertEqual(fast, ["chs-active-pass", "chs-first-narrows",
                              "chs-johnstone-strait-central", "chs-seymour-narrows"],
                       "the 60-day passers are exactly the four the M47 harness scored as PASS at 60 d")
    }

    /// A gate final at 60 d has nothing provisional to show: it goes straight
    /// to the real thing, and offering a hedge on it would be a lie the other
    /// way round.
    func testAGateValidatedAt60DaysNeverOffersAFastAnswer() {
        for g in ChsCurrentGateInfo.all where g.fitDays == 60 {
            XCTAssertNil(g.provisionalSlackMinutes, "\(g.id)")
            XCTAssertFalse(g.offersProvisional, "\(g.id)")
        }
    }

    /// The floor, enforced against the shipped bundle — not just against the
    /// generator that wrote it.
    func testEveryProvisionalGateIsUnderTheUsefulnessFloor() {
        for g in ChsCurrentGateInfo.all where g.fitDays > 60 {
            guard let minutes = g.provisionalSlackMinutes else { continue }  // held pending: fine
            XCTAssert(minutes <= floorMinutes,
                      "\(g.id): a ±\(minutes) min fast answer is past the \(floorMinutes) min floor — hold it pending instead")
            XCTAssert(minutes > 0 && minutes % 5 == 0, "\(g.id): tolerances round UP to 5 min")
            XCTAssert(g.offersProvisional, "\(g.id)")
        }
    }

    /// The measured numbers, per gate, as recorded by the M47 harness at the
    /// 60-day window and rounded up to 5 min. If a regeneration changes one of
    /// these, the copy in front of the user changed — that is worth a failure.
    func testTheShippedTolerancesAreTheMeasuredOnes() {
        let expected = ["chs-blackney-passage": 35, "chs-dodd-narrows": 35,
                        "chs-gillard-passage": 20, "chs-hole-in-the-wall": 20,
                        "chs-porlier-pass": 35, "chs-race-passage": 30,
                        "chs-weynton-passage": 35]
        for (id, minutes) in expected {
            XCTAssertEqual(gate(id).provisionalSlackMinutes, minutes, id)
        }
    }

    // MARK: - The copy

    /// The warning names THIS station's number, never a generic hedge, and
    /// says what to do about it and roughly how long.
    func testTheWarningNamesTheStationAndItsOwnNumber() {
        let dodd = gate("chs-dodd-narrows")
        XCTAssertEqual(dodd.provisionalHeadline,
                       "Fitted from the last 60 days — slack at Dodd Narrows can be off by up to ~35 min.")
        XCTAssertEqual(dodd.provisionalExpectation,
                       "Stay connected for about 2 minutes more and Slackwater refines it to the full 210-day model, in place — nothing to tap.")
        XCTAssertEqual(dodd.provisionalTolerance, "±35 min")
        // Gillard is a different pass with a different error: different copy.
        XCTAssert(gate("chs-gillard-passage").provisionalHeadline.contains("~20 min"))
    }

    // MARK: - Chunks

    func testThe60DayChunksAreTheNewestChunksOfThe210DayPlan() {
        let end = Date(timeIntervalSince1970: 1_785_000_000)
        let full = ChsFitService.chunkPlan(days: 210, end: end)
        let fast = ChsFitService.chunkPlan(days: 60, end: end)
        XCTAssertEqual(full.count, 31)
        XCTAssertEqual(fast.count, 10)
        XCTAssertEqual(Array(full.prefix(fast.count)), fast,
                       "the fast answer must cost no request the full fetch would not have made anyway")
        XCTAssert(full[0].start > full[1].start, "newest first — that is what makes the fast answer fast")
        XCTAssertEqual(full[0].end, end)
        XCTAssert(full.last!.start <= end.addingTimeInterval(-210 * 86_400),
                  "the plan must cover at least the window it was asked for")
    }

    /// Grid-aligned boundaries: the same chunk keeps the same identity (and the
    /// same cache file) as `end` walks forward day by day.
    func testChunkIdentityIsStableAcrossDays() {
        let day = 86_400.0
        let today = ChsFitService.chunkPlan(days: 210, end: Date(timeIntervalSince1970: 1_785_000_000))
        let tomorrow = ChsFitService.chunkPlan(days: 210, end: Date(timeIntervalSince1970: 1_785_000_000 + day))
        XCTAssertEqual(today.last!.start, tomorrow.last!.start)
        XCTAssertEqual(Set(today.dropFirst().map(\.start)).subtracting(tomorrow.map(\.start)), [],
                       "only the newest, uncached chunk may move")
    }

    /// The resume rule: what a yielded job already fetched is on disk, and it
    /// is served without a request — proved by asking with the network off.
    func testCachedChunksResumeWithoutRefetching() async throws {
        let start = Date(timeIntervalSince1970: 1_784_000_000)
        let chunk = ChsChunk(start: start, end: start.addingTimeInterval(7 * 86_400))
        let missing = ChsChunk(start: start.addingTimeInterval(-7 * 86_400), end: start)
        defer { ChsChunkStore.purge("test-station") }

        ChsChunkStore.save([ChsSample(t: 1, v: 2)], "test-station", "wcsp1", chunk)
        let offline = IwlsFetcher(killSwitch: true)
        let resumed = try await offline.series("wcsp1", stationID: "test-station", chunk: chunk)
        XCTAssertEqual(resumed, [ChsSample(t: 1, v: 2)], "a fetched chunk is never fetched twice")

        do {
            _ = try await offline.series("wcsp1", stationID: "test-station", chunk: missing)
            XCTFail("a chunk that was never fetched must still need the network")
        } catch ChsError.networkDisabled {}
    }

    /// A model stored before M51 has no `fitDays` and was always the full
    /// window — it must not suddenly read as provisional after an upgrade.
    func testALegacyStoredModelIsNotProvisional() throws {
        let json = """
        {"schemaVersion":1,"stationID":"chs-dodd-narrows","iwlsID":"x","iwlsName":"x",
         "fittedAt":770000000,"fitStartMs":0,"fitEndMs":0,"floodDirection":10,
         "ebbDirection":190,"offset":0,"rms":0.1,"constituents":[]}
        """
        let model = try JSONDecoder().decode(ChsCurrentModel.self, from: Data(json.utf8))
        XCTAssertNil(model.fitDays)
        XCTAssertFalse(gate("chs-dodd-narrows").isProvisional(model))
    }
}
