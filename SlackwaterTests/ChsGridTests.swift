import XCTest
import SlackwaterKit
import SlackwaterIWLS
@testable import Slackwater

final class ChsGridTests: XCTestCase {
    func testTheRecipesDriveRequestResolutionAndFiltering() throws {
        let chunk = ChsChunk(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400))
        for code in IwlsFetch.fitSeries {
            let minutes = code == "wlp" ? ChsTideFit.sampleMinutes : ChsCurrentFit.sampleMinutes
            let grid = try IwlsFetcher.grid(for: code)
            XCTAssertEqual(grid.sampleMinutes, minutes)
            let step = Double(minutes) * 60_000
            let samples = stride(from: 0.0, through: 2 * step, by: 60_000).map { ChsSample(t: $0, v: 1) }
            XCTAssertEqual(IwlsFetch.onGrid(samples, grid: grid).map(\.t), [0, step, 2 * step])
            let url = try IwlsFetch.dataURL(code, stationID: "id", chunk: chunk, grid: grid)
            let resolution = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "resolution" }?.value
            XCTAssertEqual(resolution, grid.resolution, code)
        }
        XCTAssertEqual(ChsOnlineWindow.sampleInterval, Double(ChsCurrentFit.sampleMinutes) * 60)
        XCTAssertEqual(ChsGrid.tideSeconds, Double(ChsTideFit.sampleMinutes) * 60)
    }

    /// Current gates keep the basis their bar was measured on. When an engine
    /// bump changes the tide recipe, this fails, so the change is a decision:
    /// update `currentBasis` with a current revalidation, or keep the split.
    func testTheEngineTideBasisIsStillTheValidatedCurrentBasis() {
        XCTAssertEqual(ChsFitter.tideBasis, ChsFitter.currentBasis)
    }
}
