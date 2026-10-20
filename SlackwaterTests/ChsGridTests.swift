import XCTest
import SlackwaterKit
import SlackwaterIWLS
@testable import Slackwater

final class ChsGridTests: XCTestCase {
    /// SlackwaterIWLS fetches on a fixed grid while the engine's recipes name
    /// theirs. When an engine bump moves either recipe, this fails until the
    /// shared client follows, instead of the app fitting a recipe it never
    /// fetched (slackwater#444).
    func testTheRecipesNameTheGridTheSharedClientFetches() throws {
        XCTAssertEqual(ChsTideFit.sampleMinutes, ChsGrid.minutes)
        XCTAssertEqual(ChsCurrentFit.sampleMinutes, ChsGrid.minutes)
        // Every whole minute across two steps: a filter on any other step
        // keeps a different set.
        let samples = stride(from: 0.0, through: 2 * ChsGrid.ms, by: 60_000).map { ChsSample(t: $0, v: 1) }
        XCTAssertEqual(IwlsFetch.onGrid(samples).map(\.t), [0, ChsGrid.ms, 2 * ChsGrid.ms])
        // And it asks IWLS for that step, not one it then thins, for every
        // series the app fetches.
        XCTAssertEqual(IwlsFetch.fitSeries, ["wlp", "wcsp1", "wcdp1"])
        let chunk = ChsChunk(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400))
        for code in IwlsFetch.fitSeries {
            let url = try IwlsFetch.dataURL(code, stationID: "id", chunk: chunk)
            let resolution = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "resolution" }?.value
            XCTAssertEqual(resolution, "FIFTEEN_MINUTES", code)
        }
        XCTAssertEqual(ChsGrid.minutes, 15, "update the resolution name above with the grid")
        XCTAssertEqual(ChsOnlineWindow.sampleInterval, ChsGrid.seconds)
    }

    /// Current gates keep the basis their bar was measured on. When an engine
    /// bump changes the tide recipe, this fails, so the change is a decision:
    /// update `currentBasis` with a current revalidation, or keep the split.
    func testTheEngineTideBasisIsStillTheValidatedCurrentBasis() {
        XCTAssertEqual(ChsFitter.tideBasis, ChsFitter.currentBasis)
    }
}
