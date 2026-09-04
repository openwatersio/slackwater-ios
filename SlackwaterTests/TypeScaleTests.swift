import XCTest
@testable import Slackwater

final class TypeScaleTests: XCTestCase {

    /// Repo-wide, not file-scoped, and deliberately so: the last time this
    /// project guarded a retired token one file at a time, the survivor was in
    /// the file nobody thought to check.
    func testNoSourceFileSpellsARetiredFont() throws {
        let retired = [".fraunces(", ".geist(", ".geistMono(",
                       "Fraunces-", "Geist-", "GeistMono-"]
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated() {
                for token in retired where line.contains(token) {
                    offenders.append("\(name):\(n + 1): \(token)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "retired font reference still in source:\n" + offenders.joined(separator: "\n"))
    }

    /// The bundled families must not come back via Info.plist either.
    func testNoBundledFontsDeclared() throws {
        let projectYml = try repoSource("project.yml")
        XCTAssertFalse(projectYml.contains("UIAppFonts"),
                       "UIAppFonts must be gone — bundled fonts are retired")
        XCTAssertFalse(projectYml.contains(".ttf"),
                       "no .ttf should be referenced from project.yml")
    }
}
