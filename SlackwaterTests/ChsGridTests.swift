import XCTest
import SlackwaterKit
import SlackwaterIWLS
@testable import Slackwater

final class ChsGridTests: XCTestCase {
    /// SlackwaterIWLS fetches on a fixed grid while the engine's recipes name
    /// theirs. When an engine bump moves either recipe, this fails until the
    /// shared client follows, instead of the app fitting a recipe it never
    /// fetched (slackwater#444).
    func testTheRecipesNameTheGridTheSharedClientFetches() {
        XCTAssertEqual(ChsTideFit.sampleMinutes, ChsGrid.minutes)
        XCTAssertEqual(ChsCurrentFit.sampleMinutes, ChsGrid.minutes)
        let samples = [0, 60_000, ChsGrid.ms - 60_000, ChsGrid.ms, 2 * ChsGrid.ms].map { ChsSample(t: $0, v: 1) }
        XCTAssertEqual(IwlsFetch.onGrid(samples).map(\.t), [0, ChsGrid.ms, 2 * ChsGrid.ms])
        XCTAssertEqual(ChsOnlineWindow.sampleInterval, ChsGrid.seconds)
    }

    /// Current gates keep the basis their bar was measured on. When an engine
    /// bump changes the tide recipe, this fails, so the change is a decision:
    /// update `currentBasis` with a current revalidation, or keep the split.
    func testTheEngineTideBasisIsStillTheValidatedCurrentBasis() {
        XCTAssertEqual(ChsFitter.tideBasis, ChsFitter.currentBasis)
    }
}
