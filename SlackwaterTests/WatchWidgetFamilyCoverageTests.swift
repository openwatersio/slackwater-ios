// Slackwater — GPL v3. The watch's provider builds a card for the families
// on its list and a complication reading for the rest; the widgets declare
// their families in another file. A source scan, as WidgetFamilyCoverageTests
// does, because the unit tests do not link the watch extension.
import XCTest

final class WatchWidgetFamilyCoverageTests: XCTestCase {
    private func list(after marker: String, in path: String) throws -> Set<String> {
        let source = try repoSource(path)
        let start = try XCTUnwrap(source.range(of: marker), "\(marker) is gone from \(path)")
        let open = try XCTUnwrap(source.range(of: "[", range: start.upperBound..<source.endIndex))
        let close = try XCTUnwrap(source.range(of: "]", range: open.upperBound..<source.endIndex))
        return Set(source[open.upperBound..<close.lowerBound].components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty })
    }

    /// The rectangular renders `entry.card`; a family declared there but
    /// missing from the provider's list would get a nil card forever.
    func testCardFamiliesMatchTheRectangularWidget() throws {
        XCTAssertEqual(
            try list(after: "cardFamilies: Set<WidgetFamily> =", in: "SlackwaterWatchWidgets/ComplicationProvider.swift"),
            try list(after: "// card families", in: "SlackwaterWatchWidgets/ComplicationWidgets.swift"))
    }
}
