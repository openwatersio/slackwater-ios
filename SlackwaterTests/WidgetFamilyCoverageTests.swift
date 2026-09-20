// Slackwater — GPL v3. The timeline provider builds a snapshot for the
// lock-screen families and a card for the home-screen ones, and its list of
// which is which lives in a different file from the widgets that declare them.
// A source scan, for the usual reason (TestSources.swift): the provider is in
// the widget extension target, which the unit tests do not link.
import XCTest

final class WidgetFamilyCoverageTests: XCTestCase {
    /// The `.someFamily` names in one comma-separated list literal.
    private func families(in list: Substring) -> Set<String> {
        Set(list.components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            .filter { !$0.isEmpty })
    }

    /// The families in every `supportedFamilies([...])` of one widget file,
    /// spelled without the leading dot.
    private func declaredFamilies(_ path: String) throws -> Set<String> {
        let source = try repoSource(path)
        var out: Set<String> = []
        for line in source.components(separatedBy: .newlines) {
            let code = codeOnly(line)
            guard let open = code.range(of: "supportedFamilies(["),
                  let close = code.range(of: "])", range: open.upperBound..<code.endIndex)
            else { continue }
            out.formUnion(families(in: code[open.upperBound..<close.lowerBound]))
        }
        XCTAssertFalse(out.isEmpty, "no supportedFamilies found in \(path)")
        return out
    }

    /// `StationProvider.accessoryFamilies`, the provider's own list.
    private func providerAccessoryFamilies() throws -> Set<String> {
        let source = try repoSource("SlackwaterWidgets/SlackwaterWidgetsBundle.swift")
        let marker = "accessoryFamilies: Set<WidgetFamily> ="
        let start = try XCTUnwrap(source.range(of: marker), "\(marker) is gone")
        let close = try XCTUnwrap(source.range(of: "]", range: start.upperBound..<source.endIndex))
        let open = try XCTUnwrap(source.range(of: "[", range: start.upperBound..<close.lowerBound))
        return families(in: source[open.upperBound..<close.lowerBound])
    }

    /// A lock-screen widget renders `entry.snapshot`, which the provider only
    /// builds for a family on this list. Add a family to a widget and forget
    /// the provider and the widget renders its "Open Slackwater" empty state
    /// forever — nothing crashes, so only this catches it.
    func testEveryAccessoryWidgetFamilyGetsASnapshot() throws {
        XCTAssertEqual(try declaredFamilies("SlackwaterWidgets/AccessoryWidgets.swift"),
                       try providerAccessoryFamilies())
    }

    /// The mirror: a home-screen family on that list would be handed a nil
    /// card and render the same dead empty state.
    func testNoHomeWidgetFamilyIsTreatedAsAccessory() throws {
        let home = try declaredFamilies("SlackwaterWidgets/HomeWidgets.swift")
        XCTAssertTrue(home.isDisjoint(with: try providerAccessoryFamilies()),
                      "a home-screen family must render from the card, not the snapshot")
    }
}
