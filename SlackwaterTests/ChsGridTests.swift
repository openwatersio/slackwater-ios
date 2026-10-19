import XCTest
import SlackwaterKit
@testable import Slackwater

final class ChsGridTests: XCTestCase {
    func testTidesFollowTheEngineRecipeAndCurrentsKeepTheirOwnGrid() {
        XCTAssertEqual(ChsGrid.tide.minutes, ChsTideFit.sampleMinutes)
        XCTAssertEqual(ChsGrid.tide.ms, Double(ChsTideFit.sampleMinutes) * 60_000)
        XCTAssertEqual(ChsGrid.current.minutes, 15)
        XCTAssertEqual(ChsGrid.of("wlp").minutes, ChsGrid.tide.minutes)
        for code in ["wcsp1", "wcdp1"] { XCTAssertEqual(ChsGrid.of(code).minutes, ChsGrid.current.minutes) }
        XCTAssertEqual(ChsOnlineWindow.sampleInterval, ChsGrid.current.seconds)
    }

    /// Current gates keep the basis their bar was measured on. When an engine
    /// bump changes the tide recipe, this fails, so the change is a decision:
    /// update `currentBasis` with a current revalidation, or keep the split.
    func testTheEngineTideBasisIsStillTheValidatedCurrentBasis() {
        XCTAssertEqual(ChsFitter.tideBasis, ChsFitter.currentBasis)
    }

    func testRequestsAskIwlsForTheirSeriesGrid() throws {
        let chunk = ChsChunk(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 7 * 86_400))
        for code in ["wlp", "wcsp1"] {
            let grid = ChsGrid.of(code)
            let resolution = try XCTUnwrap(grid.resolution, "IWLS serves no \(grid.minutes)-minute resolution")
            XCTAssertTrue(try IwlsFetcher.dataPath(code, "id", chunk).hasSuffix("&resolution=\(resolution)"), code)
        }
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
        let chunk = ChsChunk(start: Date(timeIntervalSince1970: 604_800), end: Date(timeIntervalSince1970: 1_209_600))
        XCTAssertEqual(ChsChunkStore.url("chs-dodd-narrows", "wcsp1", chunk).lastPathComponent,
                       "chs-dodd-narrows-wcsp1-604800.json")
        try XCTSkipUnless(ChsGrid.tide.minutes == 15)
        XCTAssertEqual(ChsChunkStore.url("chs-victoria", "wlp", chunk).lastPathComponent, "chs-victoria-wlp-604800.json")
    }
}
