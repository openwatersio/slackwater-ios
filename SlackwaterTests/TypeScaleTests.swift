import XCTest
@testable import Slackwater

final class TypeScaleTests: XCTestCase {

    /// Repo-wide, not file-scoped, and deliberately so: the last time this
    /// project guarded a retired token one file at a time, the survivor was in
    /// the file nobody thought to check.
    func testNoSourceFileSpellsARetiredFont() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SlackwaterTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Slackwater")
        let retired = [".fraunces(", ".geist(", ".geistMono(",
                       "Fraunces-", "Geist-", "GeistMono-"]
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not walk \(root.path)")
        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in source.components(separatedBy: .newlines).enumerated() {
                for token in retired where line.contains(token) {
                    offenders.append("\(url.lastPathComponent):\(n + 1): \(token)")
                }
            }
        }
        // A scan that silently found no files would pass forever.
        XCTAssertGreaterThan(scanned, 10, "expected to scan the app's sources, walked \(scanned) files")
        XCTAssertTrue(offenders.isEmpty,
                      "retired font reference still in source:\n" + offenders.joined(separator: "\n"))
    }

    /// The bundled families must not come back via Info.plist either.
    func testNoBundledFontsDeclared() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let projectYml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertFalse(projectYml.contains("UIAppFonts"),
                       "UIAppFonts must be gone — bundled fonts are retired")
        XCTAssertFalse(projectYml.contains(".ttf"),
                       "no .ttf should be referenced from project.yml")
    }
}

extension TypeScaleTests {
    /// Every formatter that produces a number feeds a Text that must not
    /// jitter as digits change. Asserted on source text because SwiftUI
    /// exposes no way to read a resolved Font back off a view.
    func testNumericFormattersAreMonospacedDigit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let formatters = ["formatHeight(", "formatSpeed(", "formatNm(", "cardTime("]
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var checked = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let lines = source.components(separatedBy: .newlines)
            for (n, line) in lines.enumerated() where formatters.contains(where: line.contains) {
                guard line.contains("Text(") else { continue }
                checked += 1
                // The .font() modifier may sit on this line or the next few.
                let window = lines[n..<min(n + 4, lines.count)].joined(separator: "\n")
                if !window.contains("monospacedDigit()") {
                    offenders.append("\(url.lastPathComponent):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertGreaterThan(checked, 5, "expected to find numeric Text sites, found \(checked)")
        XCTAssertTrue(offenders.isEmpty,
                      "numeric reading without .monospacedDigit():\n" + offenders.joined(separator: "\n"))
    }
}
