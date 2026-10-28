import XCTest
import SlackwaterKit
import SlackwaterIWLS
@testable import Slackwater

final class ChsGridTests: XCTestCase {
    func testTheRecipesDriveRequestResolutionAndFiltering() throws {
        let chunk = ChsChunk(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400))
        let requiredSeries = ["wlp", "wcsp1", "wcdp1"]
        XCTAssertEqual(Set(IwlsFetch.fitSeries), Set(requiredSeries))
        for code in requiredSeries {
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

    func testFitValidationUsesTheAppPackageRevision() throws {
        let revisions = try repoSource("project.yml").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("revision: ") }
        XCTAssertEqual(revisions.count, 1)
        let revision = String(try XCTUnwrap(revisions.first).dropFirst("revision: ".count))
        XCTAssertTrue(try repoSource("tools/FitValidation/Package.swift").contains("revision: \"\(revision)\""))
        let resolved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(repoSource("tools/FitValidation/Package.resolved").utf8)) as? [String: Any])
        let pins = try XCTUnwrap(resolved["pins"] as? [[String: Any]])
        let slackwater = try XCTUnwrap(pins.first { $0["identity"] as? String == "slackwater" })
        XCTAssertEqual((slackwater["state"] as? [String: Any])?["revision"] as? String, revision)
    }

}
