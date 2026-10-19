import XCTest
import SlackwaterKit
@testable import Slackwater

final class ChsGridTests: XCTestCase {
    func testTheGridIsTheEngineRecipes() {
        XCTAssertEqual(ChsGrid.minutes, ChsTideFit.sampleMinutes)
        XCTAssertEqual(ChsGrid.ms, Double(ChsTideFit.sampleMinutes) * 60_000)
    }

    func testRequestsAskIwlsForTheGrid() {
        let chunk = ChsChunk(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 7 * 86_400))
        XCTAssertTrue(IwlsFetcher.dataPath("wlp", "id", chunk).hasSuffix("&resolution=\(ChsGrid.resolution)"))
    }

    func testOnlyStepsIwlsServesHaveAResolution() {
        XCTAssertEqual(ChsGrid.iwlsResolution(1), "ONE_MINUTE")
        XCTAssertEqual(ChsGrid.iwlsResolution(3), "THREE_MINUTES")
        XCTAssertEqual(ChsGrid.iwlsResolution(5), "FIVE_MINUTES")
        XCTAssertEqual(ChsGrid.iwlsResolution(15), "FIFTEEN_MINUTES")
        XCTAssertEqual(ChsGrid.iwlsResolution(60), "SIXTY_MINUTES")
        XCTAssertNil(ChsGrid.iwlsResolution(10))
    }

    /// Chunks already on disk were written on the 15-minute grid and keep
    /// their names; a finer grid must not read them back.
    func testCachedChunksKeepTheirNamesOnTheFifteenMinuteGrid() throws {
        try XCTSkipUnless(ChsGrid.minutes == 15)
        let chunk = ChsChunk(start: Date(timeIntervalSince1970: 604_800), end: Date(timeIntervalSince1970: 1_209_600))
        XCTAssertEqual(ChsChunkStore.url("chs-victoria", "wlp", chunk).lastPathComponent, "chs-victoria-wlp-604800.json")
    }
}
