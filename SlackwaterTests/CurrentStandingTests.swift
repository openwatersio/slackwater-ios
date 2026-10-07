import XCTest
import SlackwaterKit
@testable import Slackwater

/// Where one current maximum sits among the maxima around it.
///
/// Floods rank against floods and ebbs against ebbs. Most gates are not
/// symmetric — the ebb runs harder than the flood or the other way about — so
/// ranking them together would mean the weaker direction never marks at all,
/// however remarkable it is for that direction.
final class CurrentStandingTests: XCTestCase {
    /// Deception Pass: a strong, well-known Salish Sea gate with its own
    /// constituents rather than a subordinate's offsets.
    private let station = CurrentStationRecord.all.first { $0.name.contains("Deception Pass") && $0.reference == nil }
    private let at = Date(timeIntervalSince1970: 1_780_000_000)

    private func events() throws -> (station: CurrentStationRecord, all: [CurrentEvent],
                                     window: (start: Date, end: Date)) {
        let s = try XCTUnwrap(station, "no Deception Pass reference station in the bundle")
        let w = TideStanding.window(around: at, tz: s.tz)
        return (s, s.engineStation.events(from: w.start, to: w.end), w)
    }

    func testFloodsAndEbbsAreRankedSeparately() throws {
        let (s, all, w) = try events()
        let floods = CurrentStanding.peaks(all, kind: .maxFlood)
        let ebbs = CurrentStanding.peaks(all, kind: .maxEbb)
        XCTAssertGreaterThan(floods.count, 20, "a fortnight either side holds plenty of floods")
        XCTAssertGreaterThan(ebbs.count, 20)
        // Magnitudes are unsigned, so a direction's ranking is about its own
        // strength rather than about the sign the engine gives it.
        XCTAssertTrue(floods.allSatisfy { $0.magnitude > 0 })
        XCTAssertTrue(ebbs.allSatisfy { $0.magnitude > 0 })
        _ = (s, w)
    }

    /// The asymmetry that makes separate ranking necessary rather than tidy.
    func testTheWeakerDirectionStillHasItsOwnBiggest() throws {
        let (_, all, w) = try events()
        let floods = CurrentStanding.peaks(all, kind: .maxFlood)
        let ebbs = CurrentStanding.peaks(all, kind: .maxEbb)
        let weaker = (floods.map(\.magnitude).max() ?? 0) < (ebbs.map(\.magnitude).max() ?? 0) ? floods : ebbs
        let biggest = try XCTUnwrap(weaker.max { $0.magnitude < $1.magnitude })
        let standing = try XCTUnwrap(PeakStanding.at(biggest.magnitude, time: biggest.time,
                                                     among: weaker, window: w))
        XCTAssertTrue(standing.marks, "the weaker direction's own biggest must still mark")
        XCTAssertNil(standing.nextBigger)
    }

    /// Ranked across both directions, that same maximum would be buried.
    func testRankingBothDirectionsTogetherWouldHideIt() throws {
        let (_, all, w) = try events()
        let floods = CurrentStanding.peaks(all, kind: .maxFlood)
        let ebbs = CurrentStanding.peaks(all, kind: .maxEbb)
        let fMax = floods.map(\.magnitude).max() ?? 0, eMax = ebbs.map(\.magnitude).max() ?? 0
        try XCTSkipUnless(abs(fMax - eMax) / Swift.max(fMax, eMax) > 0.08,
                          "this gate runs near-symmetric, so the two rankings agree")
        let weaker = fMax < eMax ? floods : ebbs
        let biggest = try XCTUnwrap(weaker.max { $0.magnitude < $1.magnitude })
        let together = try XCTUnwrap(PeakStanding.at(biggest.magnitude, time: biggest.time,
                                                     among: floods + ebbs, window: w))
        XCTAssertFalse(together.marks,
                       "if this marked anyway the test proves nothing about the split")
    }

    func testAMiddlingMaximumDoesNotMark() throws {
        let (_, all, w) = try events()
        let ebbs = CurrentStanding.peaks(all, kind: .maxEbb).sorted { $0.magnitude < $1.magnitude }
        let middling = ebbs[ebbs.count / 2]
        XCTAssertFalse(try XCTUnwrap(PeakStanding.at(middling.magnitude, time: middling.time,
                                                     among: ebbs, window: w)).marks)
    }

    /// The caption keeps the time in every state: it is the half a reader acts
    /// on, and a standing with no "when" is trivia.
    func testTheCaptionKeepsItsTimeWhetherMarkedOrNot() throws {
        let (_, all, w) = try events()
        let ebbs = CurrentStanding.peaks(all, kind: .maxEbb)
        let biggest = try XCTUnwrap(ebbs.max { $0.magnitude < $1.magnitude })
        let middling = ebbs.sorted { $0.magnitude < $1.magnitude }[ebbs.count / 2]
        for s in [PeakStanding.at(biggest.magnitude, time: biggest.time, among: ebbs, window: w),
                  PeakStanding.at(middling.magnitude, time: middling.time, among: ebbs, window: w),
                  nil] {
            XCTAssertTrue(maxCaption(standing: s, kind: .maxEbb, time: "1:09 PM").contains("1:09 PM"))
        }
    }

    func testAnUnrankedMaximumReadsTheOrdinaryWay() {
        XCTAssertEqual(maxCaption(standing: nil, kind: .maxFlood, time: "1:09 PM"),
                       String(localized: "Flood at 1:09 PM"))
    }

    func testSlackEventsAreNotPeaks() throws {
        let (_, all, _) = try events()
        XCTAssertFalse(all.isEmpty)
        let peaks = CurrentStanding.peaks(all, kind: .maxFlood) + CurrentStanding.peaks(all, kind: .maxEbb)
        XCTAssertEqual(peaks.count, all.filter { $0.kind != .slack }.count)
    }
}
