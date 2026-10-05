import XCTest
@testable import Slackwater

final class ChsTidePreviewTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func preview(_ values: [Double]) -> ChsTidePreview {
        ChsTidePreview(stationID: "chs-test", fetchedAt: start, samples: values.enumerated().map {
            .init(time: start.addingTimeInterval(Double($0.offset) * 900), height: $0.element)
        })
    }

    func testReadingInterpolatesButNeverInventsWaterOutsideCoverage() {
        let p = preview([-1, 1, 3])
        XCTAssertEqual(p.height(at: start.addingTimeInterval(450)), 0)
        XCTAssertEqual(p.height(at: start.addingTimeInterval(1800)), 3)
        XCTAssertNil(p.height(at: start.addingTimeInterval(-1)))
        XCTAssertNil(p.height(at: start.addingTimeInterval(1801)))
        XCTAssertEqual(p.heights(from: start.addingTimeInterval(-900), to: start.addingTimeInterval(2700), step: 900).map(\.height), [-1, 1, 3])
    }

    func testGapCannotMasqueradeAsDownloadedCoverage() {
        let p = ChsTidePreview(stationID: "chs-test", fetchedAt: start, samples: [
            .init(time: start, height: 1),
            .init(time: start.addingTimeInterval(3600), height: 2),
        ])
        XCTAssertNil(p.coverage)
        XCTAssertNil(p.height(at: start.addingTimeInterval(1800)))
    }

    func testTurnsKeepHighsLowsAndTheMiddleOfAFlatStand() {
        let p = preview([0, 1, 1, 0, -1, 0])
        let turns = p.extremes(from: start, to: start.addingTimeInterval(4500))
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].kind, .high)
        XCTAssertEqual(turns[0].time, start.addingTimeInterval(1350))
        XCTAssertEqual(turns[0].height, 1)
        XCTAssertEqual(turns[1].kind, .low)
        XCTAssertEqual(turns[1].time, start.addingTimeInterval(3600))
        XCTAssertEqual(turns[1].height, -1)
    }

    func testRateUsesElapsedTimeAndKeepsItsSign() {
        let p = preview([1, 2, 1])
        let rates = p.rates(from: start, to: start.addingTimeInterval(900), step: 900)
        XCTAssertEqual(rates.map(\.rate), [4, -4])
    }

    func testCachedPreviewRoundTripsAndRetainsItsBounds() throws {
        let p = preview([1, 2, 1])
        let loaded = try JSONDecoder().decode(ChsTidePreview.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(loaded.stationID, "chs-test")
        XCTAssertEqual(loaded.coverage, start...start.addingTimeInterval(1800))
        XCTAssertNil(loaded.height(at: start.addingTimeInterval(1801)))
    }

    func testPlacesWithoutReadingsGetAPreviewBeforeOtherModelsFinish() {
        let near = ChsJob(id: "near", name: "Near", region: "", isCurrent: false, latitude: 0, longitude: 0, fitDays: 60)
        let far = ChsJob(id: "far", name: "Far", region: "", isCurrent: false, latitude: 1, longitude: 0, fitDays: 60)
        var queue = ChsQueue([near, far])
        XCTAssertEqual(queue.nextPending(previewedIDs: ["near"])?.id, "far")
        XCTAssertEqual(queue.nextPending(previewedIDs: ["near", "far"])?.id, "near")
        queue.promote("near")
        XCTAssertEqual(queue.nextPending(previewedIDs: ["near"])?.id, "near")
        queue.set("near", .downloading)
        XCTAssertEqual(queue.nextPending(previewedIDs: ["near"])?.id, "far")
    }

    func testPreviewPriorityHonorsRetryDelays() {
        let near = ChsJob(id: "near", name: "Near", region: "", isCurrent: false, latitude: 0, longitude: 0, fitDays: 60)
        let far = ChsJob(id: "far", name: "Far", region: "", isCurrent: false, latitude: 1, longitude: 0, fitDays: 60)
        var queue = ChsQueue([near, far])
        queue.deferRetry("far", error: "offline", at: start)
        XCTAssertEqual(queue.nextPending(at: start, previewedIDs: ["near"])?.id, "near")
        XCTAssertEqual(queue.nextPending(at: start.addingTimeInterval(61), previewedIDs: ["near"])?.id, "far")
    }
}
